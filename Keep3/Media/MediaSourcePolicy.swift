import Foundation

struct MediaSourcePolicy: Equatable, Sendable {
  var isMediaFirstEnabled = true
  var hidesFrontmostSource = false
  var suppressedBundleIdentifiers: Set<String> = []

  func allows(_ session: MediaSession, frontmostBundleIdentifier: String?) -> Bool {
    guard isMediaFirstEnabled, session.capabilities.contains(.playPause) else { return false }
    guard let source = session.sourceBundleIdentifier else { return true }
    guard !suppressedBundleIdentifiers.contains(source) else { return false }
    return !hidesFrontmostSource || source != frontmostBundleIdentifier
  }

  func allows(
    _ snapshot: MediaSessionSnapshot,
    frontmostBundleIdentifier: String?
  ) -> Bool {
    (snapshot.playbackState == .playing
      || snapshot.playbackState == .paused)
      && allows(
        snapshot.session,
        frontmostBundleIdentifier: frontmostBundleIdentifier
      )
  }
}
