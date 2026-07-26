import Foundation

enum MediaRemoteCommandName: String, Sendable {
  case togglePlayPause
  case next
  case previous
  case shuffle
  case repeatMode
  case seek

  var requiredCapability: MediaCapability {
    switch self {
    case .togglePlayPause:
      return .playPause
    case .next:
      return .next
    case .previous:
      return .previous
    case .shuffle:
      return .shuffle
    case .repeatMode:
      return .repeatMode
    case .seek:
      return .seek
    }
  }
}

@objc(MediaRemoteClientProtocol)
protocol MediaRemoteClientProtocol: AnyObject {
  func mediaRemoteDidUpdate(_ propertyList: NSDictionary)
}

@objc(MediaRemoteServiceProtocol)
protocol MediaRemoteServiceProtocol: AnyObject {
  func compatibilityReport(
    reply: @escaping @Sendable (NSDictionary) -> Void
  )
  func startMonitoring(reply: @escaping @Sendable (Bool) -> Void)
  func stopMonitoring()
  func sendCommand(
    _ action: String,
    sessionID: String,
    capabilityRevision: NSNumber,
    value: NSNumber?,
    reply: @escaping @Sendable (Bool) -> Void
  )
}

enum MediaRemoteXPCInterface {
  static func service() -> NSXPCInterface {
    NSXPCInterface(
      with: MediaRemoteServiceProtocol.self
    )
  }

  static func client() -> NSXPCInterface {
    NSXPCInterface(
      with: MediaRemoteClientProtocol.self
    )
  }
}
