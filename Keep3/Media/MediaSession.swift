import Foundation

enum MediaCapability: String, CaseIterable, Codable, Hashable, Sendable {
  case playPause
  case previous
  case next
  case seek
  case shuffle
  case repeatMode
}

enum MediaPlaybackState: String, Codable, Equatable, Sendable {
  case playing
  case paused
  case stopped
  case interrupted
  case unknown
}

struct MediaSession: Equatable, Sendable {
  let sessionID: String
  let sourceBundleIdentifier: String?
  let title: String?
  let artist: String?
  let duration: TimeInterval?
  let progress: TimeInterval?
  let capabilities: Set<MediaCapability>

  static func normalize(_ wire: MediaSessionWirePayload) -> MediaSession? {
    guard let sessionID = bounded(wire.sessionID, maximum: 128) else { return nil }
    let duration = wire.duration.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
    let progress = wire.progress.flatMap {
      $0.isFinite && $0 >= 0 && (duration == nil || $0 <= duration!) ? $0 : nil
    }
    return .init(
      sessionID: sessionID,
      sourceBundleIdentifier: bounded(wire.sourceBundleIdentifier, maximum: 255),
      title: bounded(wire.title, maximum: 512),
      artist: bounded(wire.artist, maximum: 512),
      duration: duration,
      progress: progress,
      capabilities: Set(wire.capabilities.compactMap(MediaCapability.init(rawValue:)))
    )
  }

  private static func bounded(_ value: String?, maximum: Int) -> String? {
    guard let value else { return nil }
    guard !value.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }),
      !value.isEmpty,
      value.utf8.count <= maximum
    else { return nil }
    return value
  }
}

struct MediaSessionSnapshot: Equatable, Sendable {
  let session: MediaSession
  let playbackState: MediaPlaybackState
  let subscriptionEpoch: UInt64
  let capabilityRevision: UInt64
  let contentRevision: UInt64
}

struct MediaSessionWirePayload: Equatable, Sendable {
  let sessionID: String
  let sourceBundleIdentifier: String?
  let title: String?
  let artist: String?
  let duration: TimeInterval?
  let progress: TimeInterval?
  let capabilities: [String]
}
