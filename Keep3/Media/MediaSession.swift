import Foundation

extension NSNumber {
  var exactUInt64: UInt64? {
    guard CFGetTypeID(self) != CFBooleanGetTypeID() else {
      return nil
    }
    var value = decimalValue
    guard !NSDecimalIsNotANumber(&value), value >= 0 else {
      return nil
    }
    var rounded = Decimal()
    NSDecimalRound(&rounded, &value, 0, .down)
    guard rounded == value,
      value <= Decimal(string: "18446744073709551615")!
    else {
      return nil
    }
    return NSDecimalNumber(decimal: value).uint64Value
  }

  var finiteDoubleExcludingBoolean: Double? {
    guard CFGetTypeID(self) != CFBooleanGetTypeID(),
      doubleValue.isFinite
    else {
      return nil
    }
    return doubleValue
  }
}

enum MediaCapability: String, CaseIterable, Codable, Hashable, Sendable {
  case playPause
  case previous
  case next
  case seek
  case favorite
  case shuffle
  case repeatMode
  case repeatOne
  case copySource
}

enum MediaRemoteCapabilityPolicy {
  static func capability(forEnabledCommand command: Int32) -> MediaCapability? {
    switch command {
    case 2:
      return .playPause
    case 4:
      return .next
    case 5:
      return .previous
    case 6:
      return .shuffle
    case 7:
      return .repeatMode
    default:
      return nil
    }
  }
}

enum MediaPlaybackState: String, Codable, Equatable, Sendable {
  case playing
  case paused
  case stopped
  case interrupted
  case unknown
}

enum MediaArtworkWireUpdate: String, Sendable {
  case unchanged
  case replace
  case clear
}

struct MediaArtworkPayload: Equatable, Sendable {
  let data: Data
  let mimeType: String?
}

struct MediaSession: Equatable, Sendable {
  static let maximumArtworkBytes = 5_000_000
  static let maximumSessionIDBytes = 128
  static let maximumBundleIdentifierBytes = 255
  static let maximumMetadataBytes = 512
  static let maximumApplicationNameBytes = 128
  static let maximumMimeTypeBytes = 128

  let sessionID: String
  let sourceBundleIdentifier: String?
  let title: String?
  let artist: String?
  let album: String?
  let applicationName: String?
  let publicShareURL: URL?
  let artworkData: Data?
  let artworkMIMEType: String?
  let duration: TimeInterval?
  let progress: TimeInterval?
  let capabilities: Set<MediaCapability>

  static func normalize(_ wire: MediaSessionWirePayload) -> MediaSession? {
    guard
      let sessionID = bounded(
        wire.sessionID,
        maximum: maximumSessionIDBytes
      )
    else { return nil }
    let duration = wire.duration.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
    let progress = wire.progress.flatMap {
      $0.isFinite && $0 >= 0 && (duration == nil || $0 <= duration!) ? $0 : nil
    }
    return .init(
      sessionID: sessionID,
      sourceBundleIdentifier: bounded(
        wire.sourceBundleIdentifier,
        maximum: maximumBundleIdentifierBytes
      ),
      title: bounded(wire.title, maximum: maximumMetadataBytes),
      artist: bounded(wire.artist, maximum: maximumMetadataBytes),
      album: bounded(wire.album, maximum: maximumMetadataBytes),
      applicationName: bounded(
        wire.applicationName,
        maximum: maximumApplicationNameBytes
      ),
      publicShareURL: validatedPublicHTTPSURL(wire.publicShareURL),
      artworkData: wire.artworkData.flatMap {
        $0.isEmpty || $0.count > Self.maximumArtworkBytes ? nil : $0
      },
      artworkMIMEType: bounded(
        wire.artworkMIMEType,
        maximum: maximumMimeTypeBytes
      ),
      duration: duration,
      progress: progress,
      capabilities: Set(wire.capabilities.compactMap(MediaCapability.init(rawValue:)))
    )
  }

  static func bounded(_ value: String?, maximum: Int) -> String? {
    guard let value else { return nil }
    guard !value.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }),
      !value.isEmpty,
      value.utf8.count <= maximum
    else { return nil }
    return value
  }

  static func validatedPublicHTTPSURL(_ value: String?) -> URL? {
    guard let value = bounded(value, maximum: 2_048),
      let components = URLComponents(string: value),
      components.scheme?.lowercased() == "https",
      components.user == nil,
      components.password == nil,
      components.port == nil || components.port == 443,
      let host = components.host?.lowercased(),
      isPublicHost(host),
      let url = components.url
    else {
      return nil
    }
    return url
  }

  private static func isPublicHost(_ host: String) -> Bool {
    guard !host.isEmpty,
      host != "localhost",
      !host.hasSuffix(".localhost"),
      !host.hasSuffix(".local"),
      !host.hasSuffix(".internal"),
      !host.hasSuffix(".home"),
      !host.hasSuffix(".lan")
    else {
      return false
    }

    if host.contains(":") {
      return false
    }

    let hostParts = host.split(
      separator: ".",
      omittingEmptySubsequences: false
    )
    let octets = hostParts.compactMap { UInt8($0) }
    if octets.count == 4 {
      let first = octets[0]
      let second = octets[1]
      return first != 0
        && first != 10
        && first != 127
        && first < 224
        && !(first == 100 && (64...127).contains(second))
        && !(first == 169 && second == 254)
        && !(first == 172 && (16...31).contains(second))
        && !(first == 192 && second == 168)
        && !(first == 198 && (second == 18 || second == 19))
        && !(first == 192 && second == 0 && octets[2] == 2)
        && !(first == 198 && second == 51 && octets[2] == 100)
        && !(first == 203 && second == 0 && octets[2] == 113)
    }
    if host.unicodeScalars.allSatisfy({
      CharacterSet.decimalDigits.contains($0) || $0 == "."
    }) {
      return false
    }

    return host.contains(".")
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

  init(
    session: MediaSession,
    playbackState: MediaPlaybackState,
    capabilityRevision: UInt64,
    contentRevision: UInt64
  ) {
    self.session = session
    self.playbackState = playbackState
    self.capabilityRevision = capabilityRevision
    self.contentRevision = contentRevision
  }

  init?(
    propertyList: NSDictionary,
    retainedArtwork: MediaArtworkPayload? = nil
  ) {
    let artworkUpdate =
      (propertyList["artworkUpdate"] as? String)
      .flatMap(MediaArtworkWireUpdate.init(rawValue:))
      ?? (propertyList["artworkData"] is Data ? .replace : .clear)
    let artwork: MediaArtworkPayload?
    switch artworkUpdate {
    case .unchanged:
      artwork = retainedArtwork
    case .replace:
      artwork = (propertyList["artworkData"] as? Data).map {
        MediaArtworkPayload(
          data: $0,
          mimeType: propertyList["artworkMIMEType"] as? String
        )
      }
    case .clear:
      artwork = nil
    }

    guard
      let protocolVersion = propertyList["protocolVersion"] as? NSNumber,
      protocolVersion.exactUInt64
        == UInt64(MediaCompatibilityReport.protocolVersion),
      propertyList["isPresent"] as? Bool == true,
      let sessionID = propertyList["sessionID"] as? String,
      let playbackValue = propertyList["playbackState"] as? String,
      let playbackState = MediaPlaybackState(rawValue: playbackValue),
      let capabilityNumber = propertyList["capabilityRevision"] as? NSNumber,
      let capabilityRevision = capabilityNumber.exactUInt64,
      let contentNumber = propertyList["contentRevision"] as? NSNumber,
      let contentRevision = contentNumber.exactUInt64,
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
          publicShareURL: propertyList["publicShareURL"] as? String,
          artworkData: artwork?.data,
          artworkMIMEType: artwork?.mimeType,
          duration: (propertyList["duration"] as? NSNumber)?
            .finiteDoubleExcludingBoolean,
          progress: (propertyList["progress"] as? NSNumber)?
            .finiteDoubleExcludingBoolean,
          capabilities: capabilities
        )
      )
    else {
      return nil
    }

    self.session = session
    self.playbackState = playbackState
    self.capabilityRevision = capabilityRevision
    self.contentRevision = contentRevision
  }
}

struct MediaSessionWirePayload: Equatable, Sendable {
  let sessionID: String
  let sourceBundleIdentifier: String?
  let title: String?
  let artist: String?
  let album: String?
  let applicationName: String?
  let publicShareURL: String?
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
    publicShareURL: String? = nil,
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
    self.publicShareURL = publicShareURL
    self.artworkData = artworkData
    self.artworkMIMEType = artworkMIMEType
    self.duration = duration
    self.progress = progress
    self.capabilities = capabilities
  }
}
