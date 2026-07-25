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
  static let maximumArtworkBytes = 5_000_000

  let sessionID: String
  let sourceBundleIdentifier: String?
  let title: String?
  let artist: String?
  let album: String?
  let applicationName: String?
  let artworkData: Data?
  let artworkMIMEType: String?
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
      album: bounded(wire.album, maximum: 512),
      applicationName: bounded(wire.applicationName, maximum: 128),
      artworkData: wire.artworkData.flatMap {
        $0.isEmpty || $0.count > Self.maximumArtworkBytes ? nil : $0
      },
      artworkMIMEType: bounded(wire.artworkMIMEType, maximum: 128),
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

struct MediaAdapterSnapshot: Equatable, Sendable {
  let session: MediaSession
  let playbackState: MediaPlaybackState
  let capabilityRevision: UInt64
  let contentRevision: UInt64

  init?(propertyList: NSDictionary) {
    guard
      let protocolVersion = propertyList["protocolVersion"] as? NSNumber,
      protocolVersion.intValue == MediaCompatibilityReport.protocolVersion,
      propertyList["isPresent"] as? Bool == true,
      let sessionID = propertyList["sessionID"] as? String,
      let playbackValue = propertyList["playbackState"] as? String,
      let playbackState = MediaPlaybackState(rawValue: playbackValue),
      let capabilityNumber = propertyList["capabilityRevision"] as? NSNumber,
      capabilityNumber.int64Value >= 0,
      let contentNumber = propertyList["contentRevision"] as? NSNumber,
      contentNumber.int64Value >= 0,
      let capabilities = propertyList["capabilities"] as? [String],
      let session = MediaSession.normalize(
        .init(
          sessionID: sessionID,
          sourceBundleIdentifier:
            propertyList["sourceBundleIdentifier"] as? String,
          title: propertyList["title"] as? String,
          artist: propertyList["artist"] as? String,
          album: propertyList["album"] as? String,
          applicationName: propertyList["applicationName"] as? String,
          artworkData: propertyList["artworkData"] as? Data,
          artworkMIMEType: propertyList["artworkMIMEType"] as? String,
          duration: (propertyList["duration"] as? NSNumber)?.doubleValue,
          progress: (propertyList["progress"] as? NSNumber)?.doubleValue,
          capabilities: capabilities
        )
      )
    else {
      return nil
    }

    self.session = session
    self.playbackState = playbackState
    capabilityRevision = capabilityNumber.uint64Value
    contentRevision = contentNumber.uint64Value
  }
}

struct MediaSessionWirePayload: Equatable, Sendable {
  let sessionID: String
  let sourceBundleIdentifier: String?
  let title: String?
  let artist: String?
  let album: String?
  let applicationName: String?
  let artworkData: Data?
  let artworkMIMEType: String?
  let duration: TimeInterval?
  let progress: TimeInterval?
  let capabilities: [String]

  init(
    sessionID: String,
    sourceBundleIdentifier: String?,
    title: String?,
    artist: String?,
    album: String? = nil,
    applicationName: String? = nil,
    artworkData: Data? = nil,
    artworkMIMEType: String? = nil,
    duration: TimeInterval?,
    progress: TimeInterval?,
    capabilities: [String]
  ) {
    self.sessionID = sessionID
    self.sourceBundleIdentifier = sourceBundleIdentifier
    self.title = title
    self.artist = artist
    self.album = album
    self.applicationName = applicationName
    self.artworkData = artworkData
    self.artworkMIMEType = artworkMIMEType
    self.duration = duration
    self.progress = progress
    self.capabilities = capabilities
  }
}
