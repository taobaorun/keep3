import AppKit

enum DisplayLifecycleEvent: Equatable {
  case displayConfigurationChanged
  case activeSpaceChanged
  case sessionResigned
  case sessionBecameActive
  case willSleep
  case didWake
  case screensSlept
  case screensWoke
}

@MainActor
final class DisplayLifecycleCoordinator {
  private enum UnavailableReason: Hashable {
    case inactiveSession
    case systemSleep
    case screensUnavailable
  }

  private let onRefresh: () -> Void
  private let onDeactivate: () -> Void
  private let onActivate: () -> Void
  private var unavailableReasons: Set<UnavailableReason> = []

  init(
    onRefresh: @escaping () -> Void,
    onDeactivate: @escaping () -> Void,
    onActivate: @escaping () -> Void
  ) {
    self.onRefresh = onRefresh
    self.onDeactivate = onDeactivate
    self.onActivate = onActivate
  }

  func handle(_ event: DisplayLifecycleEvent) {
    switch event {
    case .displayConfigurationChanged, .activeSpaceChanged:
      guard unavailableReasons.isEmpty else {
        return
      }
      onRefresh()
    case .sessionResigned:
      becomeUnavailable(for: .inactiveSession)
    case .sessionBecameActive:
      becomeAvailable(for: .inactiveSession)
    case .willSleep:
      becomeUnavailable(for: .systemSleep)
    case .didWake:
      becomeAvailable(for: .systemSleep)
    case .screensSlept:
      becomeUnavailable(for: .screensUnavailable)
    case .screensWoke:
      becomeAvailable(for: .screensUnavailable)
    }
  }

  private func becomeUnavailable(for reason: UnavailableReason) {
    let wasAvailable = unavailableReasons.isEmpty
    unavailableReasons.insert(reason)
    if wasAvailable {
      onDeactivate()
    }
  }

  private func becomeAvailable(for reason: UnavailableReason) {
    guard unavailableReasons.remove(reason) != nil,
      unavailableReasons.isEmpty
    else {
      return
    }
    onActivate()
  }
}

@MainActor
final class DisplayLifecycleObserver: NSObject {
  private let applicationCenter: NotificationCenter
  private let workspaceCenter: NotificationCenter
  private let onEvent: (DisplayLifecycleEvent) -> Void
  private var isStarted = false

  init(
    applicationCenter: NotificationCenter = .default,
    workspaceCenter: NotificationCenter =
      NSWorkspace.shared.notificationCenter,
    onEvent: @escaping (DisplayLifecycleEvent) -> Void
  ) {
    self.applicationCenter = applicationCenter
    self.workspaceCenter = workspaceCenter
    self.onEvent = onEvent
  }

  func start() {
    guard !isStarted else {
      return
    }
    isStarted = true

    applicationCenter.addObserver(
      self,
      selector: #selector(displayConfigurationChanged),
      name: NSApplication.didChangeScreenParametersNotification,
      object: nil
    )
    addWorkspaceObserver(
      #selector(activeSpaceChanged),
      name: NSWorkspace.activeSpaceDidChangeNotification
    )
    addWorkspaceObserver(
      #selector(sessionResigned),
      name: NSWorkspace.sessionDidResignActiveNotification
    )
    addWorkspaceObserver(
      #selector(sessionBecameActive),
      name: NSWorkspace.sessionDidBecomeActiveNotification
    )
    addWorkspaceObserver(
      #selector(willSleep),
      name: NSWorkspace.willSleepNotification
    )
    addWorkspaceObserver(
      #selector(didWake),
      name: NSWorkspace.didWakeNotification
    )
    addWorkspaceObserver(
      #selector(screensSlept),
      name: NSWorkspace.screensDidSleepNotification
    )
    addWorkspaceObserver(
      #selector(screensWoke),
      name: NSWorkspace.screensDidWakeNotification
    )
  }

  func stop() {
    guard isStarted else {
      return
    }
    applicationCenter.removeObserver(self)
    workspaceCenter.removeObserver(self)
    isStarted = false
  }

  private func addWorkspaceObserver(
    _ selector: Selector,
    name: Notification.Name
  ) {
    workspaceCenter.addObserver(
      self,
      selector: selector,
      name: name,
      object: nil
    )
  }

  @objc private func displayConfigurationChanged() {
    onEvent(.displayConfigurationChanged)
  }

  @objc private func activeSpaceChanged() {
    onEvent(.activeSpaceChanged)
  }

  @objc private func sessionResigned() {
    onEvent(.sessionResigned)
  }

  @objc private func sessionBecameActive() {
    onEvent(.sessionBecameActive)
  }

  @objc private func willSleep() {
    onEvent(.willSleep)
  }

  @objc private func didWake() {
    onEvent(.didWake)
  }

  @objc private func screensSlept() {
    onEvent(.screensSlept)
  }

  @objc private func screensWoke() {
    onEvent(.screensWoke)
  }
}
