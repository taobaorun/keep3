import Foundation

@MainActor
final class MediaSurfaceInteractionModel {
  private let scheduler: any AppTimerScheduling
  private let onExpansion: (Bool, SurfaceExpansionReason) -> Void
  private let onTrackPeek: (MediaTrackPeek?) -> Void

  private var expansionTrigger: SurfaceExpansionTrigger = .hover
  private var isQuickPeekEnabled = true
  private var quickPeekDuration: TimeInterval = 2
  private var expansionReason: SurfaceExpansionReason = .none
  private var trackPeekTimer: (any AppTimerCancellation)?
  private var trackPeek: MediaTrackPeek?
  private var contentIdentity: ContentIdentity?

  init(
    scheduler: any AppTimerScheduling =
      TaskAppTimerScheduler(),
    onExpansion: @escaping (Bool, SurfaceExpansionReason) -> Void
  ) {
    self.scheduler = scheduler
    self.onExpansion = onExpansion
    onTrackPeek = { _ in }
  }

  init(
    scheduler: any AppTimerScheduling =
      TaskAppTimerScheduler(),
    onExpansion: @escaping (Bool, SurfaceExpansionReason) -> Void,
    onTrackPeek: @escaping (MediaTrackPeek?) -> Void
  ) {
    self.scheduler = scheduler
    self.onExpansion = onExpansion
    self.onTrackPeek = onTrackPeek
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
    if !isQuickPeekEnabled {
      clearTrackPeek()
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
    guard isQuickPeekEnabled, expansionReason == .none else {
      return
    }
    beginTrackPeek(
      MediaTrackPeek(
        title: snapshot.session.title ?? "正在播放",
        artist: snapshot.session.artist
      )
    )
  }

  func pointerEntered() {
    guard expansionTrigger == .hover else {
      return
    }
    clearTrackPeek()
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
      clearTrackPeek()
      expand(reason: .click)
    }
  }

  func dismiss() {
    collapse()
  }

  func reset() {
    contentIdentity = nil
    clearTrackPeek()
    collapse()
  }

  private func beginTrackPeek(_ peek: MediaTrackPeek) {
    trackPeekTimer?.cancel()
    trackPeek = peek
    onTrackPeek(peek)
    let identity = contentIdentity
    trackPeekTimer = scheduler.schedule(after: quickPeekDuration) {
      [weak self] in
      guard let self, self.contentIdentity == identity else {
        return
      }
      self.trackPeekTimer = nil
      self.trackPeek = nil
      self.onTrackPeek(nil)
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
    guard expansionReason != .none else {
      return
    }
    expansionReason = .none
    onExpansion(false, .none)
  }

  private func clearTrackPeek() {
    trackPeekTimer?.cancel()
    trackPeekTimer = nil
    guard trackPeek != nil else {
      return
    }
    trackPeek = nil
    onTrackPeek(nil)
  }
}

private struct ContentIdentity: Equatable {
  let sessionID: String
  let title: String?
  let artist: String?
  let album: String?
}
