import Foundation

enum MediaRemoteSymbolResolver {
  static let mandatorySymbols = [
    "MRMediaRemoteGetNowPlayingInfo",
    "MRMediaRemoteGetNowPlayingApplicationIsPlaying",
    "MRMediaRemoteGetNowPlayingApplicationPID",
    "MRMediaRemoteRegisterForNowPlayingNotifications",
    "MRMediaRemoteUnregisterForNowPlayingNotifications",
    "MRMediaRemoteSendCommand",
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
