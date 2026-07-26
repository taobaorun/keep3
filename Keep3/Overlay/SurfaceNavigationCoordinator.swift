import Foundation

@MainActor
final class SurfaceNavigationCoordinator {
  private let orderedComponents: [SurfaceComponentDescriptor]
  private let onStateChange: (SurfaceNavigationState) -> Void

  private var availability: [SurfaceComponentID: Bool]
  private var selectedComponent: SurfaceComponentID = .priorities
  private var selectionSource: SurfaceSelectionSource = .fallback
  private var level: SurfaceLevel = .hardware
  private var mediaSessionID: String?
  private var isSurfaceAvailable = true
  private var isAwaitingReconciliation = false
  private var generation: UInt64 = 0

  var state: SurfaceNavigationState {
    SurfaceNavigationState(
      selectedComponent: selectedComponent,
      selectionSource: selectionSource,
      level: level,
      isPresented: isSurfaceAvailable && !isAwaitingReconciliation,
      generation: generation
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
      uniqueKeysWithValues: orderedComponents.map { ($0.id, $0.id == .priorities) }
    )
  }

  func isAvailable(_ component: SurfaceComponentID) -> Bool {
    availability[component] ?? false
  }

  func setAvailability(
    _ isAvailable: Bool,
    for component: SurfaceComponentID
  ) {
    let resolvedAvailability = component == .priorities ? true : isAvailable
    guard availability[component] != resolvedAvailability else {
      return
    }
    availability[component] = resolvedAvailability

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
    publish()
  }

  func navigate(_ direction: SurfaceNavigationDirection) {
    guard let selectedIndex = index(of: selectedComponent) else {
      selectFallback(after: .priorities)
      return
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
        publish()
        return
      }
    }
  }

  func setLevel(_ level: SurfaceLevel) {
    guard self.level != level else {
      return
    }
    self.level = level
    publish()
  }

  func beginMediaSession(_ sessionID: String) {
    guard mediaSessionID != sessionID else {
      return
    }
    mediaSessionID = sessionID
    availability[.media] = true
    selectedComponent = .media
    selectionSource = .automaticMedia
    publish()
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
    mediaSessionID = nil
    availability[.media] = false
    selectedComponent = .priorities
    selectionSource = .mediaExit
    publish()
  }

  func setSurfaceAvailable(_ isAvailable: Bool) {
    guard isSurfaceAvailable != isAvailable else {
      return
    }
    isSurfaceAvailable = isAvailable
    isAwaitingReconciliation = true
    publish()
  }

  func reconcileAfterAvailability() {
    guard isSurfaceAvailable, isAwaitingReconciliation else {
      return
    }
    isAwaitingReconciliation = false
    publish()
  }

  private func selectFallback(after component: SurfaceComponentID) {
    guard let selectedIndex = index(of: component) else {
      selectedComponent = .priorities
      selectionSource = .fallback
      publish()
      return
    }

    for offset in 1...orderedComponents.count {
      let candidate =
        orderedComponents[(selectedIndex + offset) % orderedComponents.count].id
      if isAvailable(candidate) {
        selectedComponent = candidate
        selectionSource = .fallback
        publish()
        return
      }
    }

    selectedComponent = .priorities
    selectionSource = .fallback
    publish()
  }

  private func index(of component: SurfaceComponentID) -> Int? {
    orderedComponents.firstIndex(where: { $0.id == component })
  }

  private func publish() {
    generation &+= 1
    onStateChange(state)
  }
}
