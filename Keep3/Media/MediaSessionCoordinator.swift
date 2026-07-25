import Foundation

actor MediaSessionCoordinator {
  typealias SnapshotDelivery =
    @MainActor @Sendable (MediaSessionSnapshot?) -> Void

  private let onSnapshot: SnapshotDelivery
  private var epoch: UInt64 = 0
  private var currentSnapshot: MediaSessionSnapshot?

  init(onSnapshot: @escaping SnapshotDelivery) {
    self.onSnapshot = onSnapshot
  }

  @discardableResult
  func beginSubscription() -> UInt64 {
    epoch &+= 1
    currentSnapshot = nil
    return epoch
  }

  func endSubscription() async {
    epoch &+= 1
    currentSnapshot = nil
    await onSnapshot(nil)
  }

  func receive(_ snapshot: MediaSessionSnapshot) async {
    guard snapshot.subscriptionEpoch == epoch,
      acceptsRevision(snapshot)
    else {
      return
    }
    guard currentSnapshot != snapshot else {
      return
    }

    currentSnapshot = snapshot
    await onSnapshot(snapshot)
  }

  func requestUserInitiatedProviderEnrichment(
    for snapshot: MediaSessionSnapshot,
    using service: ProviderEnrichmentService
  ) async -> ProviderEnrichment? {
    guard isCurrent(snapshot) else {
      return nil
    }

    let enrichment = await service.requestUserInitiatedEnrichment(
      for: snapshot.session
    )

    guard isCurrent(snapshot),
      enrichment?.bundleIdentifier == snapshot.session.sourceBundleIdentifier
    else {
      return nil
    }
    return enrichment
  }

  private func acceptsRevision(_ candidate: MediaSessionSnapshot) -> Bool {
    guard let currentSnapshot,
      currentSnapshot.session.sessionID == candidate.session.sessionID
    else {
      return true
    }
    return candidate.capabilityRevision
      >= currentSnapshot.capabilityRevision
      && candidate.contentRevision >= currentSnapshot.contentRevision
  }

  private func isCurrent(_ candidate: MediaSessionSnapshot) -> Bool {
    guard candidate.subscriptionEpoch == epoch,
      let currentSnapshot
    else {
      return false
    }
    return currentSnapshot.session.sessionID == candidate.session.sessionID
      && currentSnapshot.subscriptionEpoch == candidate.subscriptionEpoch
      && currentSnapshot.capabilityRevision == candidate.capabilityRevision
      && currentSnapshot.contentRevision == candidate.contentRevision
  }
}
