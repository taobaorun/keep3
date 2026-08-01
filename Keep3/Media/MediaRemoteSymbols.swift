import Foundation

enum MediaRemoteSymbolResolver {
  static let mandatorySymbols = [
    "MRMediaRemoteCommandInfoGetCommand",
    "MRMediaRemoteCommandInfoGetEnabled",
    "MRContentItemGetArtworkData",
    "MRContentItemGetArtworkMIMEType",
    "MRMediaRemoteCopySupportedCommands",
    "MRMediaRemoteGetLocalOrigin",
    "MRMediaRemoteGetNowPlayingClient",
    "MRMediaRemoteGetNowPlayingClients",
    "MRMediaRemoteGetNowPlayingInfo",
    "MRMediaRemoteGetNowPlayingInfoForClient",
    "MRMediaRemoteGetNowPlayingInfoForPlayer",
    "MRMediaRemoteGetNowPlayingPlayerForClient",
    "MRMediaRemoteGetNowPlayingApplicationIsPlaying",
    "MRMediaRemoteGetNowPlayingApplicationPID",
    "MRMediaRemoteGetSupportedCommandsForClient",
    "MRMediaRemoteGetSupportedCommandsForPlayer",
    "MRMediaRemoteRegisterForNowPlayingNotifications",
    "MRMediaRemoteRequestNowPlayingPlaybackQueueForPlayerSync",
    "MRMediaRemoteUnregisterForNowPlayingNotifications",
    "MRMediaRemoteSendCommand",
    "MRMediaRemoteSendCommandToClient",
    "MRNowPlayingClientCreate",
    "MRNowPlayingClientGetBundleIdentifier",
    "MRNowPlayingClientGetParentAppBundleIdentifier",
    "MRNowPlayingPlayerPathCreate",
    "MRPlaybackQueueGetContentItemAtOffset",
    "MRPlaybackQueueRequestCreateDefault",
    "MRPlaybackQueueRequestSetIncludeArtwork",
    "MRPlaybackQueueRequestSetReturnContentItemAssetsInUserCompletion",
  ]

  private static let optionalSymbols: [(String, MediaCapability)] = [
    ("MRMediaRemoteSetElapsedTime", .seek),
    ("MRMediaRemoteSetShuffleMode", .shuffle),
    ("MRMediaRemoteSetRepeatMode", .repeatMode),
  ]

  static func resolve(
    using lookup: (String) -> UnsafeMutableRawPointer?
  ) -> MediaCompatibilityReport {
    let missingMandatory = mandatorySymbols.filter { lookup($0) == nil }
    guard missingMandatory.isEmpty else {
      return .init(
        status: .unavailable,
        missingMandatorySymbols: missingMandatory,
        missingOptionalSymbols: [],
        optionalCapabilities: []
      )
    }
    let missingOptional = optionalSymbols.compactMap { symbol, _ in
      lookup(symbol) == nil ? symbol : nil
    }
    let capabilities = Set(
      optionalSymbols.compactMap { symbol, capability in
        lookup(symbol) == nil ? nil : capability
      })
    return .init(
      status: .available,
      missingMandatorySymbols: [],
      missingOptionalSymbols: missingOptional,
      optionalCapabilities: capabilities
    )
  }
}

enum MediaRemoteClientSelectionPolicy {
  static func orderedIndices(
    clientCount: Int,
    systemSelectedIndex: Int?,
    previouslySelectedIndex: Int?
  ) -> [Int] {
    guard clientCount > 0 else {
      return []
    }

    var result: [Int] = []
    for index in [
      systemSelectedIndex,
      previouslySelectedIndex,
    ].compactMap({ $0 }) + Array(0..<clientCount) {
      guard (0..<clientCount).contains(index), !result.contains(index) else {
        continue
      }
      result.append(index)
    }
    return result
  }
}

struct MediaRemoteRunningApplication: Equatable, Sendable {
  let processIdentifier: Int32
  let bundleIdentifier: String
  let applicationName: String?

  init(
    processIdentifier: Int32,
    bundleIdentifier: String,
    applicationName: String?
  ) {
    self.processIdentifier = processIdentifier
    self.bundleIdentifier = bundleIdentifier
    self.applicationName = applicationName
  }

  init?(propertyList: NSDictionary) {
    guard
      let processIdentifierNumber =
        propertyList["processIdentifier"] as? NSNumber,
      let processIdentifier = processIdentifierNumber.exactUInt64,
      processIdentifier > 0,
      processIdentifier <= UInt64(Int32.max),
      let bundleIdentifier = MediaSession.bounded(
        propertyList["bundleIdentifier"] as? String,
        maximum: MediaSession.maximumBundleIdentifierBytes
      ),
      !bundleIdentifier.isEmpty
    else {
      return nil
    }
    self.processIdentifier = Int32(processIdentifier)
    self.bundleIdentifier = bundleIdentifier
    applicationName = MediaSession.bounded(
      propertyList["applicationName"] as? String,
      maximum: MediaSession.maximumApplicationNameBytes
    )
  }

  var propertyList: NSDictionary {
    var result: [String: Any] = [
      "processIdentifier": NSNumber(value: processIdentifier),
      "bundleIdentifier": bundleIdentifier,
    ]
    result["applicationName"] = applicationName
    return result.compactMapValues { $0 } as NSDictionary
  }
}

enum MediaRemoteDormantPlayerPolicy {
  static let upgradeRetryDelays: [TimeInterval] = [0.35, 1.2, 2.5]

  static func select(
    from applications: [MediaRemoteRunningApplication],
    discoveredBundleIdentifiers: Set<String>,
    frontmostBundleIdentifier: String?,
    previouslySelectedBundleIdentifier: String?
  ) -> MediaRemoteRunningApplication? {
    let eligible = applications.filter {
      discoveredBundleIdentifiers.contains($0.bundleIdentifier)
    }
    for bundleIdentifier in [
      frontmostBundleIdentifier,
      previouslySelectedBundleIdentifier,
    ].compactMap({ $0 }) {
      if let application = eligible.first(where: {
        $0.bundleIdentifier == bundleIdentifier
      }) {
        return application
      }
    }
    return eligible.first
  }

  static func playbackState(
    forPlaybackRate playbackRate: Double?
  ) -> MediaPlaybackState {
    playbackRate.map { $0 > 0 ? .playing : .paused } ?? .paused
  }

  static func resolvedCapabilities(
    reported: Set<MediaCapability>
  ) -> Set<MediaCapability> {
    reported.contains(.playPause) ? reported : reported.union([.playPause])
  }
}

struct MediaRemoteAvailabilityRecoveryPolicy {
  private static let retryDelays: [TimeInterval] = [0.5, 2, 5, 15, 30]
  private var retryAttempt = 0

  mutating func nextRetryDelay(
    hasDiscoveredPlayerRunning: Bool
  ) -> TimeInterval? {
    guard hasDiscoveredPlayerRunning else {
      reset()
      return nil
    }
    let delay = Self.retryDelays[
      min(retryAttempt, Self.retryDelays.count - 1)
    ]
    retryAttempt = min(retryAttempt + 1, Self.retryDelays.count - 1)
    return delay
  }

  mutating func reset() {
    retryAttempt = 0
  }
}

enum MediaRemoteClientCommandStatus {
  static func isAccepted(_ status: UInt8) -> Bool {
    status == 0
  }
}
