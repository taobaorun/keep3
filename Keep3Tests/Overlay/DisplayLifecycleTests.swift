import AppKit
import XCTest

@testable import Keep3

@MainActor
final class DisplayLifecycleTests: XCTestCase {
  func testDisplayAndSpaceChangesRefreshOnlyWhileAvailable() {
    var refreshCount = 0
    let coordinator = DisplayLifecycleCoordinator(
      onRefresh: { refreshCount += 1 },
      onDeactivate: {},
      onActivate: {}
    )

    coordinator.handle(.displayConfigurationChanged)
    coordinator.handle(.activeSpaceChanged)
    coordinator.handle(.sessionResigned)
    coordinator.handle(.displayConfigurationChanged)

    XCTAssertEqual(refreshCount, 2)
  }

  func testOverlappingUnavailableReasonsRestoreOnlyAfterAllClear() {
    var deactivateCount = 0
    var activateCount = 0
    let coordinator = DisplayLifecycleCoordinator(
      onRefresh: {},
      onDeactivate: { deactivateCount += 1 },
      onActivate: { activateCount += 1 }
    )

    coordinator.handle(.willSleep)
    coordinator.handle(.willSleep)
    coordinator.handle(.screensSlept)
    coordinator.handle(.didWake)

    XCTAssertEqual(deactivateCount, 1)
    XCTAssertEqual(activateCount, 0)

    coordinator.handle(.screensWoke)
    coordinator.handle(.screensWoke)

    XCTAssertEqual(deactivateCount, 1)
    XCTAssertEqual(activateCount, 1)
  }

  func testSessionResignAndBecomeActiveAreIdempotent() {
    var transitions: [String] = []
    let coordinator = DisplayLifecycleCoordinator(
      onRefresh: {},
      onDeactivate: { transitions.append("off") },
      onActivate: { transitions.append("on") }
    )

    coordinator.handle(.sessionResigned)
    coordinator.handle(.sessionResigned)
    coordinator.handle(.sessionBecameActive)
    coordinator.handle(.sessionBecameActive)

    XCTAssertEqual(transitions, ["off", "on"])
  }

  func testObserverStartsOnceAndStopsAllNotificationDelivery() {
    let applicationCenter = NotificationCenter()
    let workspaceCenter = NotificationCenter()
    var events: [DisplayLifecycleEvent] = []
    let observer = DisplayLifecycleObserver(
      applicationCenter: applicationCenter,
      workspaceCenter: workspaceCenter,
      onEvent: { events.append($0) }
    )

    observer.start()
    observer.start()
    applicationCenter.post(
      name: NSApplication.didChangeScreenParametersNotification,
      object: nil
    )
    workspaceCenter.post(
      name: NSWorkspace.activeSpaceDidChangeNotification,
      object: nil
    )
    workspaceCenter.post(
      name: NSWorkspace.willSleepNotification,
      object: nil
    )

    XCTAssertEqual(
      events,
      [.displayConfigurationChanged, .activeSpaceChanged, .willSleep]
    )

    observer.stop()
    workspaceCenter.post(
      name: NSWorkspace.didWakeNotification,
      object: nil
    )
    XCTAssertEqual(events.count, 3)
  }
}
