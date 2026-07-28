import AppKit

@MainActor
protocol WorkspaceApplicationReading: AnyObject {
  var currentBundleIdentifier: String? { get }
  func activatedBundleIdentifier(from notification: Notification) -> String?
  func bundleIdentifier(from notification: Notification) -> String?
}

@MainActor
final class WorkspaceApplicationObserver: NSObject {
  private let notificationCenter: NotificationCenter
  private let activationNotification: Notification.Name
  private let lifecycleNotifications: [Notification.Name]
  private let reader: any WorkspaceApplicationReading
  private let onFrontmostApplicationChange: (String?) -> Void
  private let onApplicationLifecycleChange: (String?) -> Void
  private var isStarted = false

  init(
    notificationCenter: NotificationCenter =
      NSWorkspace.shared.notificationCenter,
    activationNotification: Notification.Name =
      NSWorkspace.didActivateApplicationNotification,
    lifecycleNotifications: [Notification.Name] = [
      NSWorkspace.didLaunchApplicationNotification,
      NSWorkspace.didTerminateApplicationNotification,
    ],
    reader: any WorkspaceApplicationReading =
      SystemWorkspaceApplicationReader(),
    onFrontmostApplicationChange: @escaping (String?) -> Void,
    onApplicationLifecycleChange: @escaping (String?) -> Void = { _ in }
  ) {
    self.notificationCenter = notificationCenter
    self.activationNotification = activationNotification
    self.lifecycleNotifications = lifecycleNotifications
    self.reader = reader
    self.onFrontmostApplicationChange = onFrontmostApplicationChange
    self.onApplicationLifecycleChange = onApplicationLifecycleChange
  }

  func start() {
    guard !isStarted else {
      return
    }
    isStarted = true
    notificationCenter.addObserver(
      self,
      selector: #selector(applicationActivated),
      name: activationNotification,
      object: nil
    )
    for notification in lifecycleNotifications {
      notificationCenter.addObserver(
        self,
        selector: #selector(applicationLifecycleChanged),
        name: notification,
        object: nil
      )
    }
    onFrontmostApplicationChange(reader.currentBundleIdentifier)
  }

  func stop() {
    guard isStarted else {
      return
    }
    notificationCenter.removeObserver(
      self,
      name: activationNotification,
      object: nil
    )
    for notification in lifecycleNotifications {
      notificationCenter.removeObserver(
        self,
        name: notification,
        object: nil
      )
    }
    isStarted = false
  }

  @objc private func applicationActivated(_ notification: Notification) {
    onFrontmostApplicationChange(
      reader.activatedBundleIdentifier(from: notification)
        ?? reader.currentBundleIdentifier
    )
  }

  @objc private func applicationLifecycleChanged(
    _ notification: Notification
  ) {
    onApplicationLifecycleChange(reader.bundleIdentifier(from: notification))
  }
}

@MainActor
private final class SystemWorkspaceApplicationReader:
  WorkspaceApplicationReading
{
  var currentBundleIdentifier: String? {
    NSWorkspace.shared.frontmostApplication?.bundleIdentifier
  }

  func activatedBundleIdentifier(from notification: Notification) -> String? {
    (notification.userInfo?[NSWorkspace.applicationUserInfoKey]
      as? NSRunningApplication)?.bundleIdentifier
  }

  func bundleIdentifier(from notification: Notification) -> String? {
    (notification.userInfo?[NSWorkspace.applicationUserInfoKey]
      as? NSRunningApplication)?.bundleIdentifier
  }
}
