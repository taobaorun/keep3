import XCTest

@testable import Keep3

@MainActor
final class MediaSessionCoordinatorTests: XCTestCase {
  func testLifecycleOperationsRemainOrderedAcrossStopAndRestart() async {
    let queue = SerialMediaLifecycleQueue()
    let gate = SuspendedLifecycleOperation()
    var events: [String] = []

    queue.enqueue {
      events.append("old-stop-started")
      await gate.wait()
      events.append("old-stop-finished")
    }
    queue.enqueue {
      events.append("new-start")
    }

    await Task.yield()
    XCTAssertEqual(events, ["old-stop-started"])

    await gate.resume()
    await queue.waitUntilIdle()

    XCTAssertEqual(
      events,
      ["old-stop-started", "old-stop-finished", "new-start"]
    )
  }

  func testConnectionGenerationRejectsCallbacksAfterStopOrRestart() {
    var generation = MediaAdapterConnectionGeneration()
    let firstConnection = generation.advance()

    generation.invalidate()
    let secondConnection = generation.advance()

    XCTAssertFalse(generation.accepts(firstConnection))
    XCTAssertTrue(generation.accepts(secondConnection))

    generation.invalidate()

    XCTAssertFalse(generation.accepts(secondConnection))
  }

  func testConnectionRecoveryKeepsRetryingUntilTransportRecovers() {
    var recovery = MediaAdapterConnectionRecoveryPolicy()

    recovery.beginMonitoring()

    XCTAssertEqual(recovery.nextRetryDelay(), 0.5)
    XCTAssertEqual(recovery.nextRetryDelay(), 2)
    XCTAssertEqual(recovery.nextRetryDelay(), 5)
    XCTAssertEqual(recovery.nextRetryDelay(), 15)
    XCTAssertEqual(recovery.nextRetryDelay(), 30)
    XCTAssertEqual(recovery.nextRetryDelay(), 30)

    recovery.didRecover()

    XCTAssertEqual(recovery.nextRetryDelay(), 0.5)
  }

  func testConnectionRecoveryStopsWithMediaSubscription() {
    var recovery = MediaAdapterConnectionRecoveryPolicy()

    recovery.beginMonitoring()
    XCTAssertEqual(recovery.nextRetryDelay(), 0.5)

    recovery.endMonitoring()

    XCTAssertNil(recovery.nextRetryDelay())
  }

  func testRejectsOldEpochAndRegressingRevisions() async {
    var deliveries: [MediaSessionSnapshot?] = []
    let coordinator = MediaSessionCoordinator {
      deliveries.append($0)
    }
    let firstEpoch = await coordinator.beginSubscription()
    await coordinator.receive(
      snapshot(epoch: firstEpoch, capabilityRevision: 2, contentRevision: 3)
    )
    let secondEpoch = await coordinator.beginSubscription()

    await coordinator.receive(
      snapshot(epoch: firstEpoch, capabilityRevision: 3, contentRevision: 4)
    )
    await coordinator.receive(
      snapshot(epoch: secondEpoch, capabilityRevision: 2, contentRevision: 3)
    )
    await coordinator.receive(
      snapshot(epoch: secondEpoch, capabilityRevision: 1, contentRevision: 4)
    )
    await coordinator.receive(
      snapshot(epoch: secondEpoch, capabilityRevision: 2, contentRevision: 2)
    )

    XCTAssertEqual(deliveries.count, 2)
    XCTAssertEqual(deliveries.last??.subscriptionEpoch, secondEpoch)
  }

  func testRejectsRegressingArtworkRevisionWithinTheSameTrack() async {
    var deliveries: [MediaSessionSnapshot?] = []
    let coordinator = MediaSessionCoordinator {
      deliveries.append($0)
    }
    let epoch = await coordinator.beginSubscription()

    await coordinator.receive(
      snapshot(epoch: epoch, artworkRevision: 5)
    )
    await coordinator.receive(
      snapshot(epoch: epoch, artworkRevision: 4)
    )
    await coordinator.receive(
      snapshot(epoch: epoch, artworkRevision: 6)
    )

    XCTAssertEqual(deliveries.compactMap { $0?.artworkRevision }, [5, 6])
  }

  func testEndSubscriptionRejectsLateActorToMainDelivery() async {
    var deliveries: [MediaSessionSnapshot?] = []
    let coordinator = MediaSessionCoordinator {
      deliveries.append($0)
    }
    let epoch = await coordinator.beginSubscription()

    await coordinator.endSubscription()
    await coordinator.receive(snapshot(epoch: epoch))

    XCTAssertEqual(deliveries, [nil])
  }

  func testPermissionCompletionCannotEnrichAReplacementEpoch() async {
    let requester = SuspendedAutomationPermissionRequester()
    let service = ProviderEnrichmentService(
      permissionRequester: requester,
      isApplicationRunning: { _ in true }
    )
    let coordinator = MediaSessionCoordinator { _ in }
    let epoch = await coordinator.beginSubscription()
    let current = snapshot(epoch: epoch)
    await coordinator.receive(current)

    let enrichmentTask = Task {
      await coordinator.requestUserInitiatedProviderEnrichment(
        for: current,
        using: service
      )
    }
    await requester.waitUntilRequested()
    _ = await coordinator.beginSubscription()
    await requester.complete(with: .granted)

    let enrichment = await enrichmentTask.value
    XCTAssertNil(enrichment)
  }

  private func snapshot(
    epoch: UInt64,
    capabilityRevision: UInt64 = 1,
    contentRevision: UInt64 = 1,
    artworkRevision: UInt64? = nil
  ) -> MediaSessionSnapshot {
    .init(
      session: MediaSession.normalize(
        .init(
          sessionID: "session-1",
          sourceBundleIdentifier: "com.spotify.client",
          title: "Track",
          artist: nil,
          duration: nil,
          progress: nil,
          capabilities: ["playPause"]
        )
      )!,
      playbackState: .playing,
      subscriptionEpoch: epoch,
      capabilityRevision: capabilityRevision,
      contentRevision: contentRevision,
      artworkRevision: artworkRevision
    )
  }
}

private actor SuspendedLifecycleOperation {
  private var continuation: CheckedContinuation<Void, Never>?
  private var isResumed = false

  func wait() async {
    guard !isResumed else {
      return
    }
    await withCheckedContinuation { continuation in
      self.continuation = continuation
    }
  }

  func resume() {
    isResumed = true
    continuation?.resume()
    continuation = nil
  }
}

private actor SuspendedAutomationPermissionRequester:
  AutomationPermissionRequesting
{
  private var requestContinuation: CheckedContinuation<Void, Never>?
  private var resultContinuation: CheckedContinuation<AutomationPermissionOutcome, Never>?

  func requestPermission(
    for _: ProviderAutomationTarget
  ) async -> AutomationPermissionOutcome {
    requestContinuation?.resume()
    requestContinuation = nil
    return await withCheckedContinuation { continuation in
      resultContinuation = continuation
    }
  }

  func waitUntilRequested() async {
    guard resultContinuation == nil else {
      return
    }
    await withCheckedContinuation { continuation in
      requestContinuation = continuation
    }
  }

  func complete(with result: AutomationPermissionOutcome) {
    resultContinuation?.resume(returning: result)
    resultContinuation = nil
  }
}
