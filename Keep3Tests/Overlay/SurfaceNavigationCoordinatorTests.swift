import XCTest

@testable import Keep3

@MainActor
final class SurfaceNavigationCoordinatorTests: XCTestCase {
  func testNewMediaSessionAutoSelectsOnceAndManualSelectionWinsWithinSession() {
    var states: [SurfaceNavigationState] = []
    let coordinator = SurfaceNavigationCoordinator { states.append($0) }

    coordinator.setAvailability(true, for: .media)
    coordinator.beginMediaSession("session-1")

    XCTAssertEqual(states.last?.selectedComponent, .media)
    XCTAssertEqual(states.last?.selectionSource, .automaticMedia)

    coordinator.select(.priorities)
    coordinator.refreshMediaSession("session-1")

    XCTAssertEqual(states.last?.selectedComponent, .priorities)
    XCTAssertEqual(states.last?.selectionSource, .manual)

    coordinator.beginMediaSession("session-2")

    XCTAssertEqual(states.last?.selectedComponent, .media)
    XCTAssertEqual(states.last?.selectionSource, .automaticMedia)
  }

  func testNavigationWrapsAndSkipsUnavailableComponents() {
    let coordinator = SurfaceNavigationCoordinator()
    coordinator.setAvailability(true, for: .calendar)

    coordinator.navigate(.next)

    XCTAssertEqual(coordinator.state.selectedComponent, .calendar)

    coordinator.navigate(.next)

    XCTAssertEqual(coordinator.state.selectedComponent, .priorities)
  }

  func testSelectedUnavailableFallsForwardThenUltimatelyReturnsPriorities() {
    let coordinator = SurfaceNavigationCoordinator()
    coordinator.setAvailability(true, for: .media)
    coordinator.setAvailability(true, for: .calendar)
    coordinator.select(.media)

    coordinator.setAvailability(false, for: .media)

    XCTAssertEqual(coordinator.state.selectedComponent, .calendar)
    XCTAssertEqual(coordinator.state.selectionSource, .fallback)

    coordinator.setAvailability(false, for: .calendar)

    XCTAssertEqual(coordinator.state.selectedComponent, .priorities)
  }

  func testMediaExitReturnsPrioritiesAndReleasesManualPin() {
    let coordinator = SurfaceNavigationCoordinator()
    coordinator.setAvailability(true, for: .media)
    coordinator.setAvailability(true, for: .calendar)
    coordinator.beginMediaSession("session-1")
    coordinator.select(.calendar)

    coordinator.endMediaSession("session-1")

    XCTAssertEqual(coordinator.state.selectedComponent, .priorities)
    XCTAssertEqual(coordinator.state.selectionSource, .mediaExit)
    XCTAssertFalse(coordinator.isAvailable(.media))
  }

  func testDisplayRecoveryRequiresFreshReconciliation() {
    var states: [SurfaceNavigationState] = []
    let coordinator = SurfaceNavigationCoordinator { states.append($0) }

    coordinator.setSurfaceAvailable(false)
    coordinator.setSurfaceAvailable(true)

    XCTAssertFalse(states.last?.isPresented ?? true)

    coordinator.reconcileAfterAvailability()

    XCTAssertTrue(states.last?.isPresented ?? false)
    XCTAssertEqual(states.last?.selectedComponent, .priorities)
  }
}
