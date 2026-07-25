import XCTest

@testable import Keep3

@MainActor
final class SurfaceModeCoordinatorTests: XCTestCase {
  func testEligibleMediaPreemptsFocusAndPreservesTheDesignatedFocus() {
    let focusID = UUID()
    var presentations: [TopSurfacePresentation] = []
    let coordinator = SurfaceModeCoordinator { presentations.append($0) }

    coordinator.updateFocus(
      .init(
        visibleItemID: focusID,
        isExpanded: false,
        revision: 1,
        expansionReason: .none
      )
    )
    let media = MediaSurfacePayload(
      sessionID: UUID(),
      contentRevision: 1,
      isExpanded: false,
      areControlsEnabled: true
    )

    coordinator.updateMedia(media)

    XCTAssertEqual(presentations.last, .media(media))
    XCTAssertEqual(coordinator.designatedFocusID, focusID)
  }

  func testMediaExitKeepsDisabledMediaForGraceThenReturnsLatestFocus() {
    let firstFocusID = UUID()
    let latestFocusID = UUID()
    let scheduler = ManualSurfaceModeTimerScheduler()
    var presentations: [TopSurfacePresentation] = []
    var mediaOwnership: [Bool] = []
    let coordinator = SurfaceModeCoordinator(
      scheduler: scheduler,
      onPresentation: { presentations.append($0) },
      onMediaOwnershipChange: { mediaOwnership.append($0) }
    )
    coordinator.updateFocus(focus(firstFocusID, revision: 1))
    let media = MediaSurfacePayload(
      sessionID: UUID(),
      contentRevision: 1,
      isExpanded: false,
      areControlsEnabled: true
    )
    coordinator.updateMedia(media)
    coordinator.updateFocus(focus(latestFocusID, revision: 2))

    coordinator.updateMedia(nil)

    XCTAssertEqual(
      presentations.last,
      .media(
        .init(
          sessionID: media.sessionID,
          contentRevision: media.contentRevision,
          isExpanded: false,
          areControlsEnabled: false
        )
      )
    )
    XCTAssertEqual(scheduler.activeDelays, [0.5])

    scheduler.fireNext()

    XCTAssertEqual(presentations.last, .focus(focus(latestFocusID, revision: 2)))
    XCTAssertEqual(mediaOwnership, [true, false])
  }

  func testFocusUpdateDuringHandoffGraceDoesNotRevealFocusEarly() {
    let scheduler = ManualSurfaceModeTimerScheduler()
    var presentations: [TopSurfacePresentation] = []
    let coordinator = SurfaceModeCoordinator(
      scheduler: scheduler,
      onPresentation: { presentations.append($0) }
    )
    let media = MediaSurfacePayload(
      sessionID: UUID(),
      contentRevision: 1,
      isExpanded: false,
      areControlsEnabled: true
    )
    coordinator.updateFocus(focus(UUID(), revision: 1))
    coordinator.updateMedia(media)
    coordinator.updateMedia(nil)

    let latestFocus = focus(UUID(), revision: 2)
    coordinator.updateFocus(latestFocus)

    XCTAssertEqual(
      presentations.last,
      .media(
        .init(
          sessionID: media.sessionID,
          contentRevision: media.contentRevision,
          isExpanded: false,
          areControlsEnabled: false
        )
      )
    )

    scheduler.fireNext()

    XCTAssertEqual(presentations.last, .focus(latestFocus))
  }

  func testActivationRemainsHiddenUntilFreshReconciliation() {
    let focusID = UUID()
    var presentations: [TopSurfacePresentation] = []
    let coordinator = SurfaceModeCoordinator { presentations.append($0) }
    coordinator.updateFocus(focus(focusID, revision: 1))

    coordinator.setSurfaceAvailable(false)
    coordinator.setSurfaceAvailable(true)

    XCTAssertEqual(presentations.last, .hidden)

    coordinator.reconcileAfterAvailability()

    XCTAssertEqual(presentations.last, .focus(focus(focusID, revision: 1)))
  }

  private func focus(_ id: UUID, revision: UInt64) -> FocusSurfacePayload {
    .init(
      visibleItemID: id,
      isExpanded: false,
      revision: revision,
      expansionReason: .none
    )
  }
}

@MainActor
private final class ManualSurfaceModeTimerScheduler: SurfaceModeTimerScheduling {
  private final class Timer: SurfaceModeTimerCancellation {
    let delay: TimeInterval
    let action: () -> Void
    var isCancelled = false

    init(delay: TimeInterval, action: @escaping () -> Void) {
      self.delay = delay
      self.action = action
    }

    func cancel() {
      isCancelled = true
    }
  }

  private var timers: [Timer] = []

  var activeDelays: [TimeInterval] {
    timers.filter { !$0.isCancelled }.map(\.delay)
  }

  func schedule(
    after delay: TimeInterval,
    action: @escaping @MainActor () -> Void
  ) -> any SurfaceModeTimerCancellation {
    let timer = Timer(delay: delay, action: action)
    timers.append(timer)
    return timer
  }

  func fireNext() {
    guard let timer = timers.first(where: { !$0.isCancelled }) else {
      return
    }
    timer.isCancelled = true
    timer.action()
  }
}
