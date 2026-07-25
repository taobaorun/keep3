import Foundation

actor UnavailableMediaRemoteAdapter: MediaSessionAdapter {
  func start() -> MediaCompatibilityReport {
    .unavailable
  }

  func stop() {}

  func send(
    _: MediaSurfaceAction,
    to _: String
  ) -> MediaCommandDispatchResult {
    .rejected
  }
}

actor MediaRemoteAdapter: MediaSessionAdapter {
  static let serviceName = "com.apple.controlcenter.Keep3MediaService"
  private static let requestTimeout: TimeInterval = 2

  private let onSnapshot: MediaAdapterSnapshotDelivery
  private var connection: NSXPCConnection?
  private var receiver: MediaRemoteClientReceiver?

  init(onSnapshot: @escaping MediaAdapterSnapshotDelivery = { _ in }) {
    self.onSnapshot = onSnapshot
  }

  func start() async -> MediaCompatibilityReport {
    disconnect()

    let compatibilityRequest = OneShotRequest<MediaCompatibilityReport>()
    let connection = NSXPCConnection(serviceName: Self.serviceName)
    connection.remoteObjectInterface = MediaRemoteXPCInterface.service()
    connection.exportedInterface = MediaRemoteXPCInterface.client()

    let receiver = MediaRemoteClientReceiver { [onSnapshot] propertyList in
      let snapshot = MediaAdapterSnapshot(propertyList: propertyList)
      Task { @MainActor in
        onSnapshot(snapshot)
      }
    }
    connection.exportedObject = receiver
    connection.interruptionHandler = { [weak receiver] in
      compatibilityRequest.complete(with: .unavailable)
      receiver?.publishUnavailable()
    }
    connection.invalidationHandler = { [weak receiver] in
      compatibilityRequest.complete(with: .unavailable)
      receiver?.publishUnavailable()
    }
    self.connection = connection
    self.receiver = receiver
    connection.resume()

    guard
      let service = remoteService(
        from: connection,
        onError: {
          compatibilityRequest.complete(with: .unavailable)
        }
      )
    else {
      disconnect()
      return .unavailable
    }

    service.compatibilityReport { propertyList in
      compatibilityRequest.complete(
        with:
          MediaCompatibilityReport(propertyList: propertyList)
          ?? .unavailable
      )
    }

    let report = await compatibilityRequest.value(
      timeout: Self.requestTimeout,
      fallback: .unavailable
    )
    guard report.status == .available else {
      disconnect()
      return report
    }

    let monitoringRequest = OneShotRequest<Bool>()
    service.startMonitoring { started in
      monitoringRequest.complete(with: started)
    }
    guard
      await monitoringRequest.value(
        timeout: Self.requestTimeout,
        fallback: false
      )
    else {
      disconnect()
      return .unavailable
    }
    return report
  }

  func stop() async {
    if let connection,
      let service = remoteService(from: connection)
    {
      service.stopMonitoring()
    }
    let receiver = receiver
    disconnect()
    receiver?.publishUnavailable()
  }

  func send(
    _ action: MediaSurfaceAction,
    to sessionID: String
  ) async -> MediaCommandDispatchResult {
    guard let command = action.remoteCommand,
      let connection,
      let service = remoteService(from: connection)
    else {
      return .rejected
    }

    let request = OneShotRequest<Bool>()
    service.sendCommand(
      command.name.rawValue,
      sessionID: sessionID,
      value: command.value
    ) { accepted in
      request.complete(with: accepted)
    }
    return
      await request.value(
        timeout: Self.requestTimeout,
        fallback: false
      ) ? .accepted : .rejected
  }

  private func remoteService(
    from connection: NSXPCConnection,
    onError: @escaping () -> Void = {}
  ) -> (any MediaRemoteServiceProtocol)? {
    connection.remoteObjectProxyWithErrorHandler { _ in
      onError()
    } as? MediaRemoteServiceProtocol
  }

  private func disconnect() {
    let connection = connection
    self.connection = nil
    receiver = nil
    connection?.interruptionHandler = nil
    connection?.invalidationHandler = nil
    connection?.invalidate()
  }
}

private final class MediaRemoteClientReceiver: NSObject,
  MediaRemoteClientProtocol, @unchecked Sendable
{
  private let lock = NSLock()
  private let onUpdate: @Sendable (NSDictionary) -> Void
  private var didPublishUnavailable = false

  init(onUpdate: @escaping @Sendable (NSDictionary) -> Void) {
    self.onUpdate = onUpdate
  }

  func mediaRemoteDidUpdate(_ propertyList: NSDictionary) {
    lock.withLock {
      didPublishUnavailable = false
    }
    onUpdate(propertyList)
  }

  func publishUnavailable() {
    let shouldPublish = lock.withLock {
      guard !didPublishUnavailable else {
        return false
      }
      didPublishUnavailable = true
      return true
    }
    guard shouldPublish else {
      return
    }
    onUpdate([
      "protocolVersion": NSNumber(
        value: MediaCompatibilityReport.protocolVersion
      ),
      "isPresent": false,
    ])
  }
}

private struct MediaRemoteCommand {
  let name: MediaRemoteCommandName
  let value: NSNumber?
}

extension MediaSurfaceAction {
  fileprivate var remoteCommand: MediaRemoteCommand? {
    switch self {
    case .previous:
      return MediaRemoteCommand(name: .previous, value: nil)
    case .togglePlayPause:
      return MediaRemoteCommand(name: .togglePlayPause, value: nil)
    case .next:
      return MediaRemoteCommand(name: .next, value: nil)
    case .seek(let time):
      guard time.isFinite, time >= 0 else {
        return nil
      }
      return MediaRemoteCommand(
        name: .seek,
        value: NSNumber(value: time)
      )
    case .shuffle:
      return MediaRemoteCommand(name: .shuffle, value: nil)
    case .repeatMode:
      return MediaRemoteCommand(name: .repeatMode, value: nil)
    case .hideSource:
      return nil
    }
  }
}

private final class OneShotRequest<Value: Sendable>: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<Value, Never>?
  private var result: Value?
  private var hasCompleted = false

  func value(
    timeout: TimeInterval,
    fallback: Value
  ) async -> Value {
    let timeoutWorkItem = DispatchWorkItem { [weak self] in
      self?.complete(with: fallback)
    }
    DispatchQueue.global(qos: .utility).asyncAfter(
      deadline: .now() + timeout,
      execute: timeoutWorkItem
    )

    let resolved: Value = await withCheckedContinuation { continuation in
      let existing = lock.withLock { () -> Value? in
        guard hasCompleted else {
          self.continuation = continuation
          return nil
        }
        return result
      }
      if let existing {
        continuation.resume(returning: existing)
      }
    }
    timeoutWorkItem.cancel()
    return resolved
  }

  func complete(with result: Value) {
    let continuation = lock.withLock {
      () -> CheckedContinuation<Value, Never>? in
      guard !hasCompleted else {
        return nil
      }
      hasCompleted = true
      self.result = result
      let pendingContinuation = self.continuation
      self.continuation = nil
      return pendingContinuation
    }
    continuation?.resume(returning: result)
  }
}
