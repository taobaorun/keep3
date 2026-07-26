import Foundation

@MainActor
final class MediaSurfaceInteractionModel {
  private let scheduler: any AppTimerScheduling
  private let onTrackPeek: (MediaTrackPeek?) -> Void

  private var isQuickPeekEnabled = true
  private var quickPeekDuration: TimeInterval = 2
  private var trackPeekTimer: (any AppTimerCancellation)?
  private var trackPeek: MediaTrackPeek?
  private var contentIdentity: ContentIdentity?

  init(
    scheduler: any AppTimerScheduling =
      TaskAppTimerScheduler(),
    onTrackPeek: @escaping (MediaTrackPeek?) -> Void = { _ in }
  ) {
    self.scheduler = scheduler
    self.onTrackPeek = onTrackPeek
  }

  func updatePreferences(
    isQuickPeekEnabled: Bool,
    quickPeekDuration: TimeInterval
  ) {
    self.quickPeekDuration = quickPeekDuration
    guard self.isQuickPeekEnabled != isQuickPeekEnabled else {
      return
    }
    self.isQuickPeekEnabled = isQuickPeekEnabled
    if !isQuickPeekEnabled {
      clearTrackPeek()
    }
  }

  func receiveConfirmedTrackChange(_ change: ConfirmedMediaTrackChange) {
    let snapshot = change.snapshot
    guard snapshot.playbackState == .playing else {
      clearTrackPeek()
      return
    }
    let identity = ContentIdentity(
      sessionID: snapshot.session.sessionID,
      title: snapshot.session.title,
      artist: snapshot.session.artist,
      album: snapshot.session.album
    )
    contentIdentity = identity
    guard isQuickPeekEnabled else {
      return
    }
    beginTrackPeek(
      MediaTrackPeek(
        title: snapshot.session.title ?? "正在播放",
        artist: snapshot.session.artist
      )
    )
  }

  func reset() {
    contentIdentity = nil
    clearTrackPeek()
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
