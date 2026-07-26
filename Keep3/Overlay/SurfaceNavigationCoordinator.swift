import Foundation

@MainActor
final class SurfaceNavigationCoordinator {
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

    guard !self.isAvailable(selectedComponent) else {
      publish()
      return
    }
    selectFallback(after: selectedComponent)
  }

  func select(_ component: SurfaceComponentID) {
    guard isAvailable(component) else {
      return
    }
    selectedComponent = component
    selectionSource = .manual
    recordManualMediaSelection()
    publish(intent: .manualSelection)
  }

  func navigate(_ direction: SurfaceNavigationDirection) {
    guard moveSelection(direction) else {
      return
    }
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
      publish(intent: .automaticComponent)
      return
    }
    manuallyDismissedMediaSessionID = nil
    selectedComponent = .media
    selectionSource = .automaticMedia
    publish(intent: .automaticComponent)
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
    if isAvailable(.priorities) {
      selectedComponent = .priorities
    } else if let fallback = firstAvailableComponent(after: .media) {
      selectedComponent = fallback
    } else {
      selectedComponent = .priorities
    }
    selectionSource = .mediaExit
    isHoverPreviewed = false
    level = .compact
    publish(intent: .automaticComponent)
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
    selectedComponent = firstAvailableComponent(after: component) ?? .priorities
    selectionSource = .fallback
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
