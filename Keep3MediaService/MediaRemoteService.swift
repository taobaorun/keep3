import Darwin
import Foundation

final class MediaRemoteService: NSObject, MediaRemoteServiceProtocol {
  private static let frameworkPath =
    "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"

  func compatibilityReport(reply: @escaping (NSDictionary) -> Void) {
    reply(Self.probe().propertyList)
  }

  private static func probe() -> MediaCompatibilityReport {
    guard let handle = dlopen(frameworkPath, RTLD_LAZY | RTLD_LOCAL) else {
      return .init(
        status: .unavailable,
        missingMandatorySymbols: MediaRemoteSymbolResolver.mandatorySymbols,
        missingOptionalSymbols: [],
        optionalCapabilities: []
      )
    }
    defer { dlclose(handle) }

    return MediaRemoteSymbolResolver.resolve { symbol in
      dlsym(handle, symbol)
    }
  }
}
