import Foundation

@MainActor
protocol SurfaceModeTimerCancellation: AnyObject {
  func cancel()
}

@MainActor
protocol SurfaceModeTimerScheduling {
  func schedule(
    after delay: TimeInterval,
    action: @escaping @MainActor () -> Void
  ) -> any SurfaceModeTimerCancellation
}

@MainActor
final class SurfaceModeCoordinator {
  private static let handoffGrace: TimeInterval = 0.5

  private let scheduler: any SurfaceModeTimerScheduling
  private let onPresentation: (TopSurfacePresentation) -> Void
  private let onMediaOwnershipChange: (Bool) -> Void

  private var focusPayload: FocusSurfacePayload?
  private var mediaPayload: MediaSurfacePayload?
  private var renderedPresentation: TopSurfacePresentation?
  private var generation: UInt64 = 0
  private var handoffGeneration: UInt64 = 0
  private var isSurfaceAvailable = true
  private var isAwaitingReconciliation = false
  private var isInHandoffGrace = false
  private var handoffTimer: (any SurfaceModeTimerCancellation)?
  private var mediaEpoch: UInt64?
  private var mediaSnapshot: MediaSessionSnapshot?
  private var mediaPolicy = MediaSourcePolicy()
  private var mediaAppearance = MediaSurfaceAppearance.standard
  private var mediaExpansionReason = SurfaceExpansionReason.none
  private var isMediaExpanded = false
  private var areMediaControlsEnabled = true
  private var frontmostBundleIdentifier: String?

  var designatedFocusID: UUID? {
    focusPayload?.visibleItemID
  }

  init(
    scheduler: any SurfaceModeTimerScheduling = TaskSurfaceModeTimerScheduler(),
    onPresentation: @escaping (TopSurfacePresentation) -> Void,
    onMediaOwnershipChange: @escaping (Bool) -> Void = { _ in }
  ) {
    self.scheduler = scheduler
    self.onPresentation = onPresentation
    self.onMediaOwnershipChange = onMediaOwnershipChange
  }

  func handleInteraction(_ intent: TopSurfaceInteractionIntent) {
    switch intent {
    case .focus(let visibleItemID, let isExpanded):
      updateFocus(
        .init(
          visibleItemID: visibleItemID,
          isExpanded: isExpanded,
          revision: nextGeneration(),
          expansionReason: isExpanded ? .manual : .none
        )
      )
    }
  }

  func updateFocus(_ payload: FocusSurfacePayload) {
    focusPayload = payload
    generation &+= 1
    reconcile()
  }

  func updateMedia(_ payload: MediaSurfacePayload?) {
    guard mediaPayload != payload else {
      return
    }

    generation &+= 1
    handoffGeneration &+= 1
    handoffTimer?.cancel()
    handoffTimer = nil
    isInHandoffGrace = false

    guard let payload else {
      mediaPayload = nil
      beginHandoffGraceIfNeeded()
      return
    }

    mediaPayload = payload
    reconcile()
  }

  func beginMediaEpoch(_ epoch: UInt64) {
    guard mediaEpoch != epoch else {
      return
    }
    mediaEpoch = epoch
    mediaSnapshot = nil
    removeMediaImmediately()
  }

  func endMediaEpoch(_ epoch: UInt64) {
    guard mediaEpoch == epoch else {
      return
    }
    mediaEpoch = nil
    mediaSnapshot = nil
    removeMediaImmediately()
  }

  func receiveMediaSnapshot(_ snapshot: MediaSessionSnapshot?) {
    guard let mediaEpoch else {
      return
    }
    receiveMediaSnapshot(snapshot, epoch: mediaEpoch)
  }

  func receiveMediaSnapshot(
    _ snapshot: MediaSessionSnapshot?,
    epoch: UInt64
  ) {
    guard mediaEpoch == epoch else {
      return
    }
    guard snapshot?.subscriptionEpoch == epoch || snapshot == nil else {
      return
    }
    mediaSnapshot = snapshot
    reconcileMediaEligibility()
  }

  func updateMediaPolicy(_ policy: MediaSourcePolicy) {
    guard mediaPolicy != policy else {
      return
    }
    mediaPolicy = policy
    reconcileMediaEligibility()
  }

  func updateMediaAppearance(_ appearance: MediaSurfaceAppearance) {
    guard mediaAppearance != appearance else {
      return
    }
    mediaAppearance = appearance
    reconcileMediaEligibility()
  }

  func updateMediaExpansion(
    isExpanded: Bool,
    reason: SurfaceExpansionReason
  ) {
    guard
      isMediaExpanded != isExpanded
        || mediaExpansionReason != reason
    else {
      return
    }
    isMediaExpanded = isExpanded
    mediaExpansionReason = reason
    reconcileMediaEligibility()
  }

  func setMediaControlsEnabled(_ isEnabled: Bool) {
    guard areMediaControlsEnabled != isEnabled else {
      return
    }
    areMediaControlsEnabled = isEnabled
    reconcileMediaEligibility()
  }

  func updateFrontmostBundleIdentifier(_ bundleIdentifier: String?) {
    guard frontmostBundleIdentifier != bundleIdentifier else {
      return
    }
    frontmostBundleIdentifier = bundleIdentifier
    reconcileMediaEligibility()
  }

  func setSurfaceAvailable(_ isAvailable: Bool) {
    guard isSurfaceAvailable != isAvailable else {
      return
    }

    generation &+= 1
    handoffGeneration &+= 1
    handoffTimer?.cancel()
    handoffTimer = nil
    isInHandoffGrace = false
    isSurfaceAvailable = isAvailable
    isAwaitingReconciliation = true

    if !isAvailable {
      publish(.hidden)
    }
  }

  func reconcileAfterAvailability() {
    guard isSurfaceAvailable else {
      return
    }

    isAwaitingReconciliation = false
    generation &+= 1
    reconcile()
  }

  private func beginHandoffGraceIfNeeded() {
    guard case .media(let renderedMedia)? = renderedPresentation else {
      reconcile()
      return
    }

    let disabledMedia = MediaSurfacePayload(
      sessionID: renderedMedia.sessionID,
      contentRevision: renderedMedia.contentRevision,
      isExpanded: renderedMedia.isExpanded,
      areControlsEnabled: false,
      session: renderedMedia.session,
      playbackState: renderedMedia.playbackState,
      capabilityRevision: renderedMedia.capabilityRevision,
      expansionReason: renderedMedia.expansionReason,
      appearance: renderedMedia.appearance
    )
    isInHandoffGrace = true
    publish(.media(disabledMedia))

    let scheduledGeneration = handoffGeneration
    handoffTimer = scheduler.schedule(after: Self.handoffGrace) { [weak self] in
      guard let self, self.handoffGeneration == scheduledGeneration else {
        return
      }
      self.handoffTimer = nil
      self.isInHandoffGrace = false
      self.reconcile()
    }
  }

  private func reconcileMediaEligibility() {
    guard let mediaSnapshot else {
      updateMedia(nil)
      return
    }

    guard mediaSnapshot.playbackState == .playing else {
      updateMedia(nil)
      return
    }

    guard
      mediaPolicy.allows(
        mediaSnapshot,
        frontmostBundleIdentifier: frontmostBundleIdentifier
      )
    else {
      removeMediaImmediately()
      return
    }

    updateMedia(
      .init(
        sessionID: mediaSnapshot.session.sessionID,
        contentRevision: mediaSnapshot.contentRevision,
        isExpanded: isMediaExpanded,
        areControlsEnabled: areMediaControlsEnabled,
        session: mediaSnapshot.session,
        playbackState: mediaSnapshot.playbackState,
        capabilityRevision: mediaSnapshot.capabilityRevision,
        expansionReason: mediaExpansionReason,
        appearance: mediaAppearance
      )
    )
  }

  private func removeMediaImmediately() {
    generation &+= 1
    handoffGeneration &+= 1
    handoffTimer?.cancel()
    handoffTimer = nil
    isInHandoffGrace = false
    mediaPayload = nil
    reconcile()
  }

  private func reconcile() {
    guard isSurfaceAvailable, !isAwaitingReconciliation, !isInHandoffGrace else {
      return
    }

    if let mediaPayload {
      publish(.media(mediaPayload))
    } else if let focusPayload, focusPayload.visibleItemID != nil {
      publish(.focus(focusPayload))
    } else {
      publish(.hidden)
    }
  }

  private func publish(_ presentation: TopSurfacePresentation) {
    guard renderedPresentation != presentation else {
      return
    }

    let wasMedia = renderedPresentation?.isMedia ?? false
    let isMedia = presentation.isMedia
    renderedPresentation = presentation
    onPresentation(presentation)

    if wasMedia != isMedia {
      onMediaOwnershipChange(isMedia)
    }
  }

  private func nextGeneration() -> UInt64 {
    generation &+= 1
    return generation
  }
}

extension TopSurfacePresentation {
  fileprivate var isMedia: Bool {
    if case .media = self {
      return true
    }
    return false
  }
}

@MainActor
private final class TaskSurfaceModeTimerScheduler: SurfaceModeTimerScheduling {
  func schedule(
    after delay: TimeInterval,
    action: @escaping @MainActor () -> Void
  ) -> any SurfaceModeTimerCancellation {
    let task = Task { @MainActor in
      do {
        try await Task.sleep(for: .seconds(delay))
      } catch {
        return
      }
      action()
    }
    return TaskSurfaceModeTimerCancellation(task: task)
  }
}

@MainActor
private final class TaskSurfaceModeTimerCancellation: SurfaceModeTimerCancellation {
  private let task: Task<Void, Never>

  init(task: Task<Void, Never>) {
    self.task = task
  }

  func cancel() {
    task.cancel()
  }
}
