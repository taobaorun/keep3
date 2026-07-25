import Foundation

@MainActor
final class MediaSurfaceInteractionModel {
  private let scheduler: any InteractionTimerScheduling
  private let onExpansion: (Bool, SurfaceExpansionReason) -> Void

  private var expansionTrigger: SurfaceExpansionTrigger = .hover
  private var isQuickPeekEnabled = true
  private var quickPeekDuration: TimeInterval = 2
  private var expansionReason: SurfaceExpansionReason = .none
  private var quickPeekTimer: (any InteractionTimerCancellation)?
  private var contentIdentity: ContentIdentity?

  init(
    scheduler: any InteractionTimerScheduling =
      TaskInteractionTimerScheduler(),
    onExpansion: @escaping (Bool, SurfaceExpansionReason) -> Void
  ) {
    self.scheduler = scheduler
    self.onExpansion = onExpansion
  }

  func updatePreferences(
    expansionTrigger: SurfaceExpansionTrigger,
    isQuickPeekEnabled: Bool,
    quickPeekDuration: TimeInterval
  ) {
    self.expansionTrigger = expansionTrigger
    self.quickPeekDuration = quickPeekDuration
    guard self.isQuickPeekEnabled != isQuickPeekEnabled else {
      return
    }
    self.isQuickPeekEnabled = isQuickPeekEnabled
    if !isQuickPeekEnabled, expansionReason == .quickPeek {
      collapse()
    }
  }

  func receive(_ snapshot: MediaSessionSnapshot?) {
    guard let snapshot, snapshot.playbackState == .playing else {
      reset()
      return
    }
    let identity = ContentIdentity(
      sessionID: snapshot.session.sessionID,
      title: snapshot.session.title,
      artist: snapshot.session.artist,
      album: snapshot.session.album
    )
    guard identity != contentIdentity else {
      return
    }
    contentIdentity = identity
    guard isQuickPeekEnabled,
      expansionReason == .none || expansionReason == .quickPeek
    else {
      return
    }
    beginQuickPeek()
  }

  func pointerEntered() {
    guard expansionTrigger == .hover else {
      return
    }
    quickPeekTimer?.cancel()
    quickPeekTimer = nil
    expand(reason: .hover)
  }

  func pointerExited() {
    guard expansionTrigger == .hover, expansionReason == .hover else {
      return
    }
    collapse()
  }

  func activateSurface() {
    guard expansionTrigger == .click else {
      return
    }
    if expansionReason == .manual || expansionReason == .click {
      collapse()
    } else {
      quickPeekTimer?.cancel()
      quickPeekTimer = nil
      expand(reason: .click)
    }
  }

  func dismiss() {
    collapse()
  }

  func reset() {
    contentIdentity = nil
    collapse()
  }

  private func beginQuickPeek() {
    quickPeekTimer?.cancel()
    expand(reason: .quickPeek)
    let identity = contentIdentity
    quickPeekTimer = scheduler.schedule(after: quickPeekDuration) {
      [weak self] in
      guard let self, self.contentIdentity == identity,
        self.expansionReason == .quickPeek
      else {
        return
      }
      self.quickPeekTimer = nil
      self.collapse()
    }
  }

  private func expand(reason: SurfaceExpansionReason) {
    guard expansionReason != reason else {
      return
    }
    expansionReason = reason
    onExpansion(true, reason)
  }

  private func collapse() {
    quickPeekTimer?.cancel()
    quickPeekTimer = nil
    guard expansionReason != .none else {
      return
    }
    expansionReason = .none
    onExpansion(false, .none)
  }
}

private struct ContentIdentity: Equatable {
  let sessionID: String
  let title: String?
  let artist: String?
  let album: String?
}
