import XCTest

@testable import Keep3

@MainActor
final class MediaCommandCoordinatorTests: XCTestCase {
  func testAcceptedTrackCommandHapticsOnlyAfterNewSameSessionContent() async {
    let sender = CommandSender(result: .accepted)
    let haptic = HapticRecorder()
    let scheduler = ManualCommandTimerScheduler()
    let coordinator = MediaCommandCoordinator(
      sender: sender,
      haptic: haptic,
      scheduler: scheduler
    )
    coordinator.updateContext(snapshot: snapshot(revision: 1), isMediaActive: true)

    let didDispatch = await coordinator.perform(.next)
    XCTAssertTrue(didDispatch)
    XCTAssertEqual(haptic.count, 0)
    XCTAssertEqual(coordinator.pendingAction, .next)

    coordinator.receive(snapshot(revision: 1))
    XCTAssertEqual(haptic.count, 0)

    coordinator.receive(snapshot(revision: 2))
    XCTAssertEqual(haptic.count, 1)
    XCTAssertNil(coordinator.pendingAction)
  }

  func testRejectedTimeoutAndSourceChangeNeverHaptic() async {
    let rejectedSender = CommandSender(result: .rejected)
    let haptic = HapticRecorder()
    let scheduler = ManualCommandTimerScheduler()
    let rejected = MediaCommandCoordinator(
      sender: rejectedSender,
      haptic: haptic,
      scheduler: scheduler
    )
    rejected.updateContext(snapshot: snapshot(revision: 1), isMediaActive: true)
    let didReject = await rejected.perform(.previous)
    XCTAssertFalse(didReject)

    let acceptedSender = CommandSender(result: .accepted)
    let accepted = MediaCommandCoordinator(
      sender: acceptedSender,
      haptic: haptic,
      scheduler: scheduler
    )
    accepted.updateContext(snapshot: snapshot(revision: 1), isMediaActive: true)
    let didDispatchBeforeTimeout = await accepted.perform(.next)
    XCTAssertTrue(didDispatchBeforeTimeout)
    scheduler.fireNext()
    accepted.receive(snapshot(revision: 2))

    accepted.updateContext(snapshot: snapshot(revision: 3), isMediaActive: true)
    let didDispatchBeforeReplacement = await accepted.perform(.next)
    XCTAssertTrue(didDispatchBeforeReplacement)
    accepted.updateContext(
      snapshot: snapshot(sessionID: "replacement", revision: 4),
      isMediaActive: true
    )
    accepted.receive(snapshot(sessionID: "replacement", revision: 5))

    XCTAssertEqual(haptic.count, 0)
  }

  func testSecondTrackActionAndUnsupportedCapabilityAreRejected() async {
    let sender = CommandSender(result: .accepted)
    let coordinator = MediaCommandCoordinator(
      sender: sender,
      haptic: HapticRecorder(),
      scheduler: ManualCommandTimerScheduler()
    )
    coordinator.updateContext(snapshot: snapshot(revision: 1), isMediaActive: true)

    let didDispatch = await coordinator.perform(.next)
    let didDispatchSecond = await coordinator.perform(.previous)
    let didDispatchUnsupported = await coordinator.perform(.seek(to: 50))
    let actions = await sender.recordedActions()

    XCTAssertTrue(didDispatch)
    XCTAssertFalse(didDispatchSecond)
    XCTAssertFalse(didDispatchUnsupported)
    XCTAssertEqual(actions, [.next])
  }

  private func snapshot(
    sessionID: String = "session-1",
    revision: UInt64
  ) -> MediaSessionSnapshot {
    .init(
      session: MediaSession.normalize(
        .init(
          sessionID: sessionID,
          sourceBundleIdentifier: "com.netease.163music",
          title: "Track \(revision)",
          artist: "Artist",
          duration: 180,
          progress: 20,
          capabilities: ["previous", "playPause", "next"]
        )
      )!,
      playbackState: .playing,
      subscriptionEpoch: 1,
      capabilityRevision: 1,
      contentRevision: revision
    )
  }
}

private actor CommandSender: MediaCommandSending {
  let result: MediaCommandDispatchResult
  private(set) var actions: [MediaSurfaceAction] = []

  init(result: MediaCommandDispatchResult) {
    self.result = result
  }

  func send(
    _ action: MediaSurfaceAction,
    to _: String
  ) -> MediaCommandDispatchResult {
    actions.append(action)
    return result
  }

  func recordedActions() -> [MediaSurfaceAction] {
    actions
  }
}

@MainActor
private final class HapticRecorder: MediaHapticPerforming {
  var count = 0

  func performConfirmedTrackChange() {
    count += 1
  }
}

@MainActor
private final class ManualCommandTimerScheduler:
  MediaCommandTimerScheduling
{
  private final class Timer: MediaCommandTimerCancellation {
    let action: () -> Void
    var isCancelled = false

    init(action: @escaping () -> Void) {
      self.action = action
    }

    func cancel() {
      isCancelled = true
    }
  }

  private var timers: [Timer] = []

  func schedule(
    after _: TimeInterval,
    action: @escaping @MainActor () -> Void
  ) -> any MediaCommandTimerCancellation {
    let timer = Timer(action: action)
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
