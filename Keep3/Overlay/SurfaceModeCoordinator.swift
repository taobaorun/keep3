import Foundation

@MainActor
final class SurfaceModeCoordinator {
  private static let handoffGrace: TimeInterval = 0.5

  private let scheduler: any AppTimerScheduling
  private let onPresentation: (TopSurfacePresentation) -> Void
  private let onMediaOwnershipChange: (Bool) -> Void

  private var focusPayload: FocusSurfacePayload?
  private var currentDesignatedFocusID: UUID?
  private var mediaPayload: MediaSurfacePayload?
  private var renderedPresentation: TopSurfacePresentation?
  private var generation: UInt64 = 0
  private var handoffGeneration: UInt64 = 0
  private var isSurfaceAvailable = true
  private var isAwaitingReconciliation = false
  private var isInHandoffGrace = false
  private var handoffTimer: (any AppTimerCancellation)?
  private var mediaEpoch: UInt64?
  private var mediaSnapshot: MediaSessionSnapshot?
  private var mediaPolicy = MediaSourcePolicy()
  private var mediaAppearance = MediaSurfaceAppearance.standard
  private var mediaExpansionReason = SurfaceExpansionReason.none
  private var isMediaExpanded = false
  private var areMediaControlsEnabled = true
  private var mediaTrackChangeDirection: MediaTrackDirection?
  private var mediaTrackPeek: MediaTrackPeek?
  private var frontmostBundleIdentifier: String?

  var designatedFocusID: UUID? {
    currentDesignatedFocusID
  }

  var currentFocusPayload: FocusSurfacePayload? {
    focusPayload
  }

  init(
    scheduler: any AppTimerScheduling = TaskAppTimerScheduler(),
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
    if currentDesignatedFocusID == nil {
      currentDesignatedFocusID = payload.visibleItemID
    }
    focusPayload = payload
    generation &+= 1
    reconcile()
  }

  func updateDesignatedFocusID(_ focusID: UUID?) {
    currentDesignatedFocusID = focusID
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
      prepareDesignatedFocusForMediaExit()
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
    if mediaSnapshot?.session.sessionID != snapshot?.session.sessionID {
      mediaTrackChangeDirection = nil
      mediaTrackPeek = nil
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

  func updateMediaTrackChangeDirection(
    _ direction: MediaTrackDirection?
  ) {
    guard mediaTrackChangeDirection != direction else {
      return
    }
    mediaTrackChangeDirection = direction
    reconcileMediaEligibility()
  }

  func updateMediaTrackPeek(_ peek: MediaTrackPeek?) {
    guard mediaTrackPeek != peek else {
      return
    }
    mediaTrackPeek = peek
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
        appearance: mediaAppearance,
        trackChangeDirection: mediaTrackChangeDirection,
        trackPeek: mediaTrackPeek
      )
    )
  }

  private func removeMediaImmediately() {
    generation &+= 1
    handoffGeneration &+= 1
    handoffTimer?.cancel()
    handoffTimer = nil
    isInHandoffGrace = false
    prepareDesignatedFocusForMediaExit()
    mediaPayload = nil
    reconcile()
  }

  private func prepareDesignatedFocusForMediaExit() {
    guard
      mediaPayload != nil || renderedPresentation?.isMedia == true
    else {
      return
    }
    guard let currentDesignatedFocusID else {
      focusPayload = nil
      return
    }
    if let focusPayload,
      focusPayload.visibleItemID == currentDesignatedFocusID,
      !focusPayload.isExpanded,
      focusPayload.expansionReason == .none
    {
      return
    }
    focusPayload = FocusSurfacePayload(
      visibleItemID: currentDesignatedFocusID,
      isExpanded: false,
      revision: nextGeneration(),
      expansionReason: .none
    )
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
