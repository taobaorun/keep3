import AppKit
import XCTest

@testable import Keep3

@MainActor
final class WorkspaceApplicationObserverTests: XCTestCase {
  func testStartsOnceUsesInjectedFrontmostReaderAndStopsDelivery() {
    let center = NotificationCenter()
    let reader = FakeWorkspaceApplicationReader(
      currentBundleIdentifier: "com.apple.TextEdit"
    )
    var bundleIdentifiers: [String?] = []
    var lifecycleBundleIdentifiers: [String?] = []
    let observer = WorkspaceApplicationObserver(
      notificationCenter: center,
      activationNotification: .testApplicationActivated,
      lifecycleNotifications: [
        .testApplicationLaunched,
        .testApplicationTerminated,
      ],
      reader: reader,
      onFrontmostApplicationChange: { bundleIdentifiers.append($0) },
      onApplicationLifecycleChange: {
        lifecycleBundleIdentifiers.append($0)
      }
    )

    observer.start()
    observer.start()
    center.post(
      name: .testApplicationActivated,
      object: nil,
      userInfo: ["bundleIdentifier": "com.spotify.client"]
    )
    center.post(
      name: .testApplicationLaunched,
      object: nil,
      userInfo: ["bundleIdentifier": "com.netease.163music"]
    )
    center.post(
      name: .testApplicationTerminated,
      object: nil,
      userInfo: ["bundleIdentifier": "com.apple.Music"]
    )

    XCTAssertEqual(
      bundleIdentifiers,
      ["com.apple.TextEdit", "com.spotify.client"]
    )
    XCTAssertEqual(
      lifecycleBundleIdentifiers,
      ["com.netease.163music", "com.apple.Music"]
    )

    observer.stop()
    center.post(
      name: .testApplicationActivated,
      object: nil,
      userInfo: ["bundleIdentifier": "com.apple.Music"]
    )
    center.post(
      name: .testApplicationLaunched,
      object: nil,
      userInfo: ["bundleIdentifier": "com.spotify.client"]
    )

    XCTAssertEqual(bundleIdentifiers.count, 2)
    XCTAssertEqual(lifecycleBundleIdentifiers.count, 2)
  }
}

extension Notification.Name {
  fileprivate static let testApplicationActivated = Notification.Name(
    "WorkspaceApplicationObserverTests.didActivate"
  )
  fileprivate static let testApplicationLaunched = Notification.Name(
    "WorkspaceApplicationObserverTests.didLaunch"
  )
  fileprivate static let testApplicationTerminated = Notification.Name(
    "WorkspaceApplicationObserverTests.didTerminate"
  )
}

@MainActor
private final class FakeWorkspaceApplicationReader:
  WorkspaceApplicationReading
{
  let currentBundleIdentifier: String?

  init(currentBundleIdentifier: String?) {
    self.currentBundleIdentifier = currentBundleIdentifier
  }

  func activatedBundleIdentifier(from notification: Notification) -> String? {
    notification.userInfo?["bundleIdentifier"] as? String
  }

  func bundleIdentifier(from notification: Notification) -> String? {
    notification.userInfo?["bundleIdentifier"] as? String
  }
}
