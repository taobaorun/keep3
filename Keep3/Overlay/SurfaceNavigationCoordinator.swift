import Foundation

@MainActor
final class SurfaceNavigationCoordinator {
  private struct PendingAutomaticSelection {
    let component: SurfaceComponentID
    let source: SurfaceSelectionSource
    let level: SurfaceLevel?
  }

  private let orderedComponents: [SurfaceComponentDescriptor]
  private let onStateChange: (SurfaceNavigationState) -> Void

  private var availability: [SurfaceComponentID: Bool]
  private var selectedComponent: SurfaceComponentID = .priorities
  private var selectionSource: SurfaceSelectionSource = .fallback
  private var level: SurfaceLevel = .hardware
  private var isHovering = false
  private var isHoverPreviewed = false
  private var mediaSessionID: String?
  private var manuallyDismissedMediaSessionID: String?
  private var isSurfaceAvailable = true
  private var isAwaitingReconciliation = false
  private var generation: UInt64 = 0
  private var transitionIntent = SurfaceTransitionIntent.initial
  private var automaticDeferralReasons:
    Set<
      SurfaceAutomaticDeferralReason
    > = []
  private var pendingAutomaticSelection: PendingAutomaticSelection?

  var state: SurfaceNavigationState {
    SurfaceNavigationState(
      selectedComponent: selectedComponent,
      selectionSource: selectionSource,
      level: level,
      isHovering: isHovering,
      isHoverPreviewed: isHoverPreviewed,
      isPresented: isSurfaceAvailable && !isAwaitingReconciliation,
      generation: generation,
      transitionIntent: transitionIntent
    )
  }

  init(
    orderedComponents: [SurfaceComponentDescriptor] =
      SurfaceComponentDescriptor.initialOrder,
    onStateChange: @escaping (SurfaceNavigationState) -> Void = { _ in }
  ) {
    precondition(
      Set(orderedComponents.map(\.id)).count == orderedComponents.count,
      "Surface component IDs must be unique"
    )
    precondition(
      orderedComponents.contains(where: { $0.id == .priorities }),
      "Priorities are the required fallback component"
    )
    self.orderedComponents = orderedComponents
    self.onStateChange = onStateChange
    availability = Dictionary(
      uniqueKeysWithValues: orderedComponents.map { ($0.id, false) }
    )
  }

  func isAvailable(_ component: SurfaceComponentID) -> Bool {
    availability[component] ?? false
  }

  func setAvailability(
    _ isAvailable: Bool,
    for component: SurfaceComponentID
  ) {
    guard availability[component] != isAvailable else {
      return
    }
    availability[component] = isAvailable

    if !automaticDeferralReasons.isEmpty,
      let pendingAutomaticSelection
    {
      switch pendingAutomaticSelection.source {
      case .automaticMedia:
        if self.isAvailable(.media) {
          return
        }
        self.pendingAutomaticSelection = PendingAutomaticSelection(
          component: mediaExitFallbackComponent(),
          source: .mediaExit,
          level: .compact
        )
        return
      case .mediaExit:
        self.pendingAutomaticSelection = PendingAutomaticSelection(
          component: mediaExitFallbackComponent(),
          source: .mediaExit,
          level: pendingAutomaticSelection.level
        )
        return
      case .fallback, .manual:
        break
      }
    }
    if self.isAvailable(selectedComponent),
      pendingAutomaticSelection?.source == .fallback
    {
      pendingAutomaticSelection = nil
    }
    guard !self.isAvailable(selectedComponent) else {
      publish()
      return
    }
    selectFallback(after: selectedComponent)
  }

  func setAutomaticTransitionDeferred(
    _ isDeferred: Bool,
    reason: SurfaceAutomaticDeferralReason
  ) {
    if isDeferred {
      automaticDeferralReasons.insert(reason)
      return
    }
    automaticDeferralReasons.remove(reason)
    guard automaticDeferralReasons.isEmpty,
      let pendingAutomaticSelection
    else {
      return
    }
    self.pendingAutomaticSelection = nil
    applyAutomaticSelection(pendingAutomaticSelection)
  }

  func select(_ component: SurfaceComponentID) {
    guard isAvailable(component) else {
      return
    }
    selectedComponent = component
    selectionSource = .manual
    recordManualMediaSelection()
    pendingAutomaticSelection = nil
    publish(intent: .manualSelection)
  }

  func navigate(_ direction: SurfaceNavigationDirection) {
    guard moveSelection(direction) else {
      return
    }
    pendingAutomaticSelection = nil
    publish(intent: .manualComponent(direction))
  }

  private func moveSelection(_ direction: SurfaceNavigationDirection) -> Bool {
    guard let selectedIndex = index(of: selectedComponent) else {
      selectedComponent = .priorities
      selectionSource = .fallback
      return true
    }

    let step = direction == .next ? 1 : -1
    for offset in 1...orderedComponents.count {
      let candidateIndex =
        (selectedIndex + (step * offset) + orderedComponents.count)
        % orderedComponents.count
      let candidate = orderedComponents[candidateIndex].id
      if isAvailable(candidate) {
        selectedComponent = candidate
        selectionSource = .manual
        recordManualMediaSelection()
        return true
      }
    }
    return false
  }

  func setLevel(_ level: SurfaceLevel) {
    guard self.level != level else {
      return
    }
    let intent: SurfaceTransitionIntent =
      level.depth > self.level.depth ? .expansion : .collapse
    self.level = level
    publish(intent: intent)
  }

  func setHovering(_ isHovering: Bool) {
    let previousEffectiveLevel = state.effectiveLevel
    let didHoverChange = self.isHovering != isHovering
    self.isHovering = isHovering

    if !isHovering,
      selectedComponent == .media,
      level == .expanded
    {
      isHoverPreviewed = false
      level = .compact
      publish(intent: .collapse)
      return
    }

    let shouldPreview = isHovering && level == .hardware
    guard didHoverChange || isHoverPreviewed != shouldPreview else {
      return
    }
    isHoverPreviewed = shouldPreview
    publish(
      intent: transitionIntent(
        from: previousEffectiveLevel,
        to: state.effectiveLevel
      )
    )
  }

  func apply(_ intent: SurfaceGestureIntent) {
    switch intent {
    case .previousTrack, .nextTrack:
      return
    case .advanceDepth, .retreatDepth, .previousComponent, .nextComponent:
      break
    }

    let previousComponent = selectedComponent
    let previousLevel = state.effectiveLevel
    var didChange = isHoverPreviewed
    isHoverPreviewed = false
    switch intent {
    case .advanceDepth:
      switch level {
      case .hardware:
        level = .compact
        didChange = true
      case .compact:
        level = .expanded
        didChange = true
      case .expanded:
        didChange = moveSelection(.next)
        if level != .compact {
          level = .compact
          didChange = true
        }
      }
    case .retreatDepth:
      switch level {
      case .hardware:
        break
      case .compact:
        level = .hardware
        didChange = true
      case .expanded:
        level = .compact
        didChange = true
      }
    case .previousComponent:
      didChange = moveSelection(.previous)
      if level != .compact {
        level = .compact
        didChange = true
      }
    case .nextComponent:
      didChange = moveSelection(.next)
      if level != .compact {
        level = .compact
        didChange = true
      }
    case .previousTrack, .nextTrack:
      return
    }
    if didChange {
      pendingAutomaticSelection = nil
      let publicationIntent: SurfaceTransitionIntent
      if selectedComponent != previousComponent {
        let direction: SurfaceNavigationDirection =
          intent == .previousComponent ? .previous : .next
        publicationIntent = .manualComponent(direction)
      } else {
        publicationIntent = transitionIntent(
          from: previousLevel,
          to: state.effectiveLevel
        )
      }
      publish(intent: publicationIntent)
    }
  }

  func beginMediaSession(_ sessionID: String) {
    guard mediaSessionID != sessionID || !isAvailable(.media) else {
      return
    }
    let preservesManualSelection =
      mediaSessionID == sessionID
      && manuallyDismissedMediaSessionID == sessionID
    mediaSessionID = sessionID
    availability[.media] = true
    if preservesManualSelection {
      selectionSource = .manual
      if automaticDeferralReasons.isEmpty {
        publish(intent: .automaticComponent)
      }
      return
    }
    manuallyDismissedMediaSessionID = nil
    deferOrApplyAutomaticSelection(
      PendingAutomaticSelection(
        component: .media,
        source: .automaticMedia,
        level: nil
      )
    )
  }

  func refreshMediaSession(_ sessionID: String) {
    guard mediaSessionID == sessionID else {
      beginMediaSession(sessionID)
      return
    }
  }

  func endMediaSession(_ sessionID: String) {
    guard mediaSessionID == sessionID else {
      return
    }
    availability[.media] = false
    deferOrApplyAutomaticSelection(
      PendingAutomaticSelection(
        component: mediaExitFallbackComponent(),
        source: .mediaExit,
        level: .compact
      )
    )
  }

  private func recordManualMediaSelection() {
    guard let mediaSessionID else {
      return
    }
    manuallyDismissedMediaSessionID =
      selectedComponent == .media ? nil : mediaSessionID
  }

  func setSurfaceAvailable(_ isAvailable: Bool) {
    guard isSurfaceAvailable != isAvailable else {
      return
    }
    isSurfaceAvailable = isAvailable
    isAwaitingReconciliation = true
    publish(intent: .lifecycleHide)
  }

  func reconcileAfterAvailability() {
    guard isSurfaceAvailable, isAwaitingReconciliation else {
      return
    }
    isAwaitingReconciliation = false
    publish(intent: .lifecycleRestore)
  }

  private func selectFallback(after component: SurfaceComponentID) {
    deferOrApplyAutomaticSelection(
      PendingAutomaticSelection(
        component: fallbackComponent(after: component),
        source: .fallback,
        level: nil
      )
    )
  }

  private func fallbackComponent(
    after component: SurfaceComponentID
  ) -> SurfaceComponentID {
    firstAvailableComponent(after: component) ?? .priorities
  }

  private func mediaExitFallbackComponent() -> SurfaceComponentID {
    if isAvailable(.priorities) {
      return .priorities
    }
    return firstAvailableComponent(after: .media) ?? .priorities
  }

  private func deferOrApplyAutomaticSelection(
    _ selection: PendingAutomaticSelection
  ) {
    guard automaticDeferralReasons.isEmpty else {
      pendingAutomaticSelection = selection
      return
    }
    applyAutomaticSelection(selection)
  }

  private func applyAutomaticSelection(
    _ proposedSelection: PendingAutomaticSelection
  ) {
    var selection = proposedSelection
    if selection.source == .fallback {
      guard !isAvailable(selectedComponent) else {
        return
      }
      selection = PendingAutomaticSelection(
        component: fallbackComponent(after: selectedComponent),
        source: .fallback,
        level: selection.level
      )
    } else if selection.source == .mediaExit {
      selection = PendingAutomaticSelection(
        component: mediaExitFallbackComponent(),
        source: .mediaExit,
        level: selection.level
      )
    }
    if selection.component == .media {
      if isAvailable(.media) {
        guard manuallyDismissedMediaSessionID != mediaSessionID else {
          return
        }
      } else {
        selection = PendingAutomaticSelection(
          component: mediaExitFallbackComponent(),
          source: .mediaExit,
          level: .compact
        )
      }
    }
    if selection.component != .priorities,
      !isAvailable(selection.component)
    {
      selection = PendingAutomaticSelection(
        component: fallbackComponent(after: selection.component),
        source: selection.source,
        level: selection.level
      )
    }

    selectedComponent = selection.component
    selectionSource = selection.source
    if let level = selection.level {
      self.level = level
    }
    isHoverPreviewed = false
    publish(intent: .automaticComponent)
  }

  private func firstAvailableComponent(
    after component: SurfaceComponentID
  ) -> SurfaceComponentID? {
    guard let selectedIndex = index(of: component) else {
      return orderedComponents.lazy.map(\.id).first(where: isAvailable)
    }

    for offset in 1...orderedComponents.count {
      let candidate =
        orderedComponents[(selectedIndex + offset) % orderedComponents.count].id
      if isAvailable(candidate) {
        return candidate
      }
    }
    return nil
  }

  private func index(of component: SurfaceComponentID) -> Int? {
    orderedComponents.firstIndex(where: { $0.id == component })
  }

  private func transitionIntent(
    from source: SurfaceLevel,
    to target: SurfaceLevel
  ) -> SurfaceTransitionIntent {
    if target.depth > source.depth {
      return .expansion
    }
    if target.depth < source.depth {
      return .collapse
    }
    return .content
  }

  private func publish(intent: SurfaceTransitionIntent = .content) {
    transitionIntent = intent
    generation &+= 1
    onStateChange(state)
  }
}
