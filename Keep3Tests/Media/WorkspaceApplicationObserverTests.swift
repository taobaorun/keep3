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
    let observer = WorkspaceApplicationObserver(
      notificationCenter: center,
      activationNotification: .testApplicationActivated,
      reader: reader,
      onFrontmostApplicationChange: { bundleIdentifiers.append($0) }
    )

    observer.start()
    observer.start()
    center.post(
      name: .testApplicationActivated,
      object: nil,
      userInfo: ["bundleIdentifier": "com.spotify.client"]
    )

    XCTAssertEqual(
      bundleIdentifiers,
      ["com.apple.TextEdit", "com.spotify.client"]
    )

    observer.stop()
    center.post(
      name: .testApplicationActivated,
      object: nil,
      userInfo: ["bundleIdentifier": "com.apple.Music"]
    )

    XCTAssertEqual(bundleIdentifiers.count, 2)
  }
}

private extension Notification.Name {
  static let testApplicationActivated = Notification.Name(
    "WorkspaceApplicationObserverTests.didActivate"
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
}
