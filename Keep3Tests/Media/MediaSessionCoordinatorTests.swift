import XCTest

@testable import Keep3

@MainActor
final class MediaSessionCoordinatorTests: XCTestCase {
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
    contentRevision: UInt64 = 1
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
      contentRevision: contentRevision
    )
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
