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
      sessionID: "session-1",
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
      sessionID: "session-1",
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
      sessionID: "session-1",
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

  func testOnlyPlayingEligibleSnapshotTakesOverAndEveryInactiveStateUsesGrace() {
    let inactiveStates: [MediaPlaybackState] = [
      .paused, .stopped, .interrupted, .unknown,
    ]

    for state in inactiveStates {
      let scheduler = ManualSurfaceModeTimerScheduler()
      var presentations: [TopSurfacePresentation] = []
      let coordinator = SurfaceModeCoordinator(
        scheduler: scheduler,
        onPresentation: { presentations.append($0) }
      )
      coordinator.updateFocus(focus(UUID(), revision: 1))
      coordinator.beginMediaEpoch(7)
      coordinator.receiveMediaSnapshot(snapshot(state: .playing, epoch: 7))

      coordinator.receiveMediaSnapshot(snapshot(state: state, epoch: 7))

      guard case .media(let payload) = presentations.last else {
        return XCTFail("\(state) should retain media during grace")
      }
      XCTAssertFalse(payload.areControlsEnabled)
      XCTAssertEqual(scheduler.activeDelays, [0.5])

      scheduler.fireNext()
      guard case .focus = presentations.last else {
        return XCTFail("\(state) should return focus after grace")
      }
    }
  }

  func testSourceLossAndRecoveryWithinGraceNeverPublishFocus() {
    let scheduler = ManualSurfaceModeTimerScheduler()
    var presentations: [TopSurfacePresentation] = []
    let coordinator = SurfaceModeCoordinator(
      scheduler: scheduler,
      onPresentation: { presentations.append($0) }
    )
    coordinator.updateFocus(focus(UUID(), revision: 1))
    coordinator.beginMediaEpoch(3)
    coordinator.receiveMediaSnapshot(snapshot(sessionID: "first", epoch: 3))

    coordinator.receiveMediaSnapshot(nil, epoch: 3)
    coordinator.receiveMediaSnapshot(
      snapshot(sessionID: "successor", epoch: 3, contentRevision: 2)
    )

    let finalMedia = presentations.suffix(2).compactMap {
      presentation -> MediaSurfacePayload? in
      guard case .media(let payload) = presentation else {
        return nil
      }
      return payload
    }
    XCTAssertEqual(finalMedia.map(\.sessionID), ["first", "successor"])
    XCTAssertEqual(
      finalMedia.map(\.areControlsEnabled),
      [false, true]
    )
    XCTAssertTrue(scheduler.activeDelays.isEmpty)
  }

  func testFrontmostAndSuppressionReturnFocusImmediatelyThenCanRetake() {
    let focusPayload = focus(UUID(), revision: 1)
    var presentations: [TopSurfacePresentation] = []
    let coordinator = SurfaceModeCoordinator {
      presentations.append($0)
    }
    coordinator.updateFocus(focusPayload)
    coordinator.beginMediaEpoch(1)
    coordinator.receiveMediaSnapshot(snapshot(epoch: 1))

    coordinator.updateMediaPolicy(
      MediaSourcePolicy(hidesFrontmostSource: true)
    )
    coordinator.updateFrontmostBundleIdentifier("com.spotify.client")

    XCTAssertEqual(presentations.last, .focus(focusPayload))

    coordinator.updateFrontmostBundleIdentifier("com.apple.TextEdit")

    guard case .media = presentations.last else {
      return XCTFail("Leaving the source should allow current playing media to retake")
    }

    coordinator.updateMediaPolicy(
      MediaSourcePolicy(
        suppressedBundleIdentifiers: ["com.spotify.client"]
      )
    )

    XCTAssertEqual(presentations.last, .focus(focusPayload))
  }

  func testOldEpochDeliveryCannotRestoreMedia() {
    let focusPayload = focus(UUID(), revision: 1)
    var presentations: [TopSurfacePresentation] = []
    let coordinator = SurfaceModeCoordinator {
      presentations.append($0)
    }
    coordinator.updateFocus(focusPayload)
    coordinator.beginMediaEpoch(1)
    coordinator.beginMediaEpoch(2)

    coordinator.receiveMediaSnapshot(snapshot(epoch: 1))

    XCTAssertEqual(presentations.last, .focus(focusPayload))
  }

  func testWakeWaitsForFreshSnapshotInTheNewEpoch() {
    let focusPayload = focus(UUID(), revision: 1)
    var presentations: [TopSurfacePresentation] = []
    let coordinator = SurfaceModeCoordinator {
      presentations.append($0)
    }
    coordinator.updateFocus(focusPayload)
    coordinator.beginMediaEpoch(1)
    coordinator.receiveMediaSnapshot(snapshot(epoch: 1))

    coordinator.setSurfaceAvailable(false)
    coordinator.beginMediaEpoch(2)
    coordinator.setSurfaceAvailable(true)
    coordinator.receiveMediaSnapshot(snapshot(epoch: 1))
    coordinator.reconcileAfterAvailability()

    XCTAssertEqual(presentations.last, .focus(focusPayload))

    coordinator.receiveMediaSnapshot(snapshot(epoch: 2))

    guard case .media = presentations.last else {
      return XCTFail("Only a fresh snapshot may restore media after wake")
    }
  }

  private func focus(_ id: UUID, revision: UInt64) -> FocusSurfacePayload {
    .init(
      visibleItemID: id,
      isExpanded: false,
      revision: revision,
      expansionReason: .none
    )
  }

  private func snapshot(
    sessionID: String = "session-1",
    state: MediaPlaybackState = .playing,
    epoch: UInt64,
    contentRevision: UInt64 = 1
  ) -> MediaSessionSnapshot {
    MediaSessionSnapshot(
      session: MediaSession.normalize(
        .init(
          sessionID: sessionID,
          sourceBundleIdentifier: "com.spotify.client",
          title: "Track",
          artist: "Artist",
          duration: 180,
          progress: 20,
          capabilities: ["playPause", "next"]
        )
      )!,
      playbackState: state,
      subscriptionEpoch: epoch,
      capabilityRevision: 1,
      contentRevision: contentRevision
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
