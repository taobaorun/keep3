import AppKit

@MainActor
protocol WorkspaceApplicationReading: AnyObject {
  var currentBundleIdentifier: String? { get }
  func activatedBundleIdentifier(from notification: Notification) -> String?
}

@MainActor
final class WorkspaceApplicationObserver: NSObject {
  private let notificationCenter: NotificationCenter
  private let activationNotification: Notification.Name
  private let reader: any WorkspaceApplicationReading
  private let onFrontmostApplicationChange: (String?) -> Void
  private var isStarted = false

  init(
    notificationCenter: NotificationCenter =
      NSWorkspace.shared.notificationCenter,
    activationNotification: Notification.Name =
      NSWorkspace.didActivateApplicationNotification,
    reader: any WorkspaceApplicationReading =
      SystemWorkspaceApplicationReader(),
    onFrontmostApplicationChange: @escaping (String?) -> Void
  ) {
    self.notificationCenter = notificationCenter
    self.activationNotification = activationNotification
    self.reader = reader
    self.onFrontmostApplicationChange = onFrontmostApplicationChange
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
    isStarted = false
  }

  @objc private func applicationActivated(_ notification: Notification) {
    onFrontmostApplicationChange(
      reader.activatedBundleIdentifier(from: notification)
        ?? reader.currentBundleIdentifier
    )
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
}
