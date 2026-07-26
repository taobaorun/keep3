import AppKit
import XCTest

@testable import Keep3

@MainActor
final class MediaCommandCoordinatorTests: XCTestCase {
  func testHoverUsesImmediateAlignmentHapticFeedback() {
    var calls:
      [(
        NSHapticFeedbackManager.FeedbackPattern,
        NSHapticFeedbackManager.PerformanceTime
      )] = []
    let haptic = AppKitSurfaceHapticFeedback {
      calls.append(($0, $1))
    }

    haptic.performHoverFeedback()

    XCTAssertEqual(calls.count, 1)
    XCTAssertEqual(calls.first?.0, .alignment)
    XCTAssertEqual(calls.first?.1, .now)
  }

  func testTrackGestureUsesImmediateGenericHapticFeedback() {
    var calls:
      [(
        NSHapticFeedbackManager.FeedbackPattern,
        NSHapticFeedbackManager.PerformanceTime
      )] = []
    let haptic = AppKitSurfaceHapticFeedback {
      calls.append(($0, $1))
    }

    haptic.performTrackGesture()

    XCTAssertEqual(calls.count, 1)
    XCTAssertEqual(calls.first?.0, .generic)
    XCTAssertEqual(calls.first?.1, .now)
  }

  func testAcceptedTrackCommandConfirmsOnlyAfterNewSameSessionContent() async {
    let sender = CommandSender(result: .accepted)
    let scheduler = ManualCommandTimerScheduler()
    var confirmations: [ConfirmedMediaTrackChange] = []
    let coordinator = MediaCommandCoordinator(
      sender: sender,
      scheduler: scheduler,
      onConfirmedTrackChange: { confirmations.append($0) }
    )
    coordinator.updateContext(snapshot: snapshot(revision: 1), isMediaActive: true)

    let didDispatch = await coordinator.perform(.next)
    XCTAssertTrue(didDispatch)
    XCTAssertTrue(confirmations.isEmpty)
    XCTAssertEqual(coordinator.pendingAction, .next)

    coordinator.receive(snapshot(revision: 1))
    XCTAssertTrue(confirmations.isEmpty)

    coordinator.receive(snapshot(revision: 2))
    XCTAssertEqual(confirmations.map(\.direction), [.next])
    XCTAssertEqual(confirmations.first?.snapshot.contentRevision, 2)
    XCTAssertNil(coordinator.pendingAction)
  }

  func testRejectedTimeoutAndSourceChangeNeverConfirm() async {
    let rejectedSender = CommandSender(result: .rejected)
    let scheduler = ManualCommandTimerScheduler()
    var confirmations: [ConfirmedMediaTrackChange] = []
    let rejected = MediaCommandCoordinator(
      sender: rejectedSender,
      scheduler: scheduler,
      onConfirmedTrackChange: { confirmations.append($0) }
    )
    rejected.updateContext(snapshot: snapshot(revision: 1), isMediaActive: true)
    let didReject = await rejected.perform(.previous)
    XCTAssertFalse(didReject)

    let acceptedSender = CommandSender(result: .accepted)
    let accepted = MediaCommandCoordinator(
      sender: acceptedSender,
      scheduler: scheduler,
      onConfirmedTrackChange: { confirmations.append($0) }
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

    XCTAssertTrue(confirmations.isEmpty)
  }

  func testSnapshotArrivingBeforeRejectedReplyNeverConfirms() async {
    let sender = SuspendedCommandSender()
    var confirmations: [ConfirmedMediaTrackChange] = []
    let coordinator = MediaCommandCoordinator(
      sender: sender,
      scheduler: ManualCommandTimerScheduler(),
      onConfirmedTrackChange: { confirmations.append($0) }
    )
    coordinator.updateContext(snapshot: snapshot(revision: 1), isMediaActive: true)

    let dispatch = Task { await coordinator.perform(.next) }
    await sender.waitUntilSent()
    coordinator.receive(snapshot(revision: 2))

    XCTAssertEqual(coordinator.pendingAction, .next)

    await sender.complete(with: .rejected)

    let result = await dispatch.value
    XCTAssertFalse(result)
    XCTAssertTrue(confirmations.isEmpty)
    XCTAssertNil(coordinator.pendingAction)
  }

  func testSnapshotArrivingBeforeAcceptedReplyConfirmsAfterAcceptance() async {
    let sender = SuspendedCommandSender()
    var confirmations: [ConfirmedMediaTrackChange] = []
    let coordinator = MediaCommandCoordinator(
      sender: sender,
      scheduler: ManualCommandTimerScheduler(),
      onConfirmedTrackChange: { confirmations.append($0) }
    )
    coordinator.updateContext(snapshot: snapshot(revision: 1), isMediaActive: true)

    let dispatch = Task { await coordinator.perform(.previous) }
    await sender.waitUntilSent()
    coordinator.receive(snapshot(revision: 2))
    XCTAssertTrue(confirmations.isEmpty)

    await sender.complete(with: .accepted)

    let result = await dispatch.value
    XCTAssertTrue(result)
    XCTAssertEqual(confirmations.map(\.direction), [.previous])
    XCTAssertEqual(confirmations.first?.snapshot.contentRevision, 2)
    XCTAssertNil(coordinator.pendingAction)
  }

  func testSecondTrackActionAndUnsupportedCapabilityAreRejected() async {
    let sender = CommandSender(result: .accepted)
    let coordinator = MediaCommandCoordinator(
      sender: sender,
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
    to _: String,
    capabilityRevision _: UInt64
  ) -> MediaCommandDispatchResult {
    actions.append(action)
    return result
  }

  func recordedActions() -> [MediaSurfaceAction] {
    actions
  }
}

private actor SuspendedCommandSender: MediaCommandSending {
  private var resultContinuation: CheckedContinuation<MediaCommandDispatchResult, Never>?
  private var sentContinuation: CheckedContinuation<Void, Never>?
  private var hasSent = false

  func send(
    _: MediaSurfaceAction,
    to _: String,
    capabilityRevision _: UInt64
  ) async -> MediaCommandDispatchResult {
    hasSent = true
    sentContinuation?.resume()
    sentContinuation = nil
    return await withCheckedContinuation { continuation in
      resultContinuation = continuation
    }
  }

  func waitUntilSent() async {
    guard !hasSent else {
      return
    }
    await withCheckedContinuation { continuation in
      sentContinuation = continuation
    }
  }

  func complete(with result: MediaCommandDispatchResult) {
    resultContinuation?.resume(returning: result)
    resultContinuation = nil
  }
}

@MainActor
private final class ManualCommandTimerScheduler:
  AppTimerScheduling
{
  private final class Timer: AppTimerCancellation {
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
  ) -> any AppTimerCancellation {
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
