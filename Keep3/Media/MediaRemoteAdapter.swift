import Foundation

actor UnavailableMediaRemoteAdapter: MediaSessionAdapter {
  func start() -> MediaCompatibilityReport {
    .unavailable
  }

  func stop() {}

  func send(
    _: MediaSurfaceAction,
    to _: String,
    capabilityRevision _: UInt64
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
  private var connectionGeneration = MediaAdapterConnectionGeneration()

  init(onSnapshot: @escaping MediaAdapterSnapshotDelivery = { _ in }) {
    self.onSnapshot = onSnapshot
  }

  func start() async -> MediaCompatibilityReport {
    invalidateConnection()
    let generation = connectionGeneration.advance()

    let compatibilityRequest = OneShotRequest<MediaCompatibilityReport>()
    let connection = NSXPCConnection(serviceName: Self.serviceName)
    connection.remoteObjectInterface = MediaRemoteXPCInterface.service()
    connection.exportedInterface = MediaRemoteXPCInterface.client()

    let receiver = MediaRemoteClientReceiver(
      connectionGeneration: generation
    ) { [weak self] deliveryGeneration, snapshot in
      Task {
        await self?.receive(
          snapshot,
          from: deliveryGeneration
        )
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
      invalidateConnection()
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
      invalidateConnection()
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
      invalidateConnection()
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
    invalidateConnection()
    receiver?.publishUnavailable()
  }

  func send(
    _ action: MediaSurfaceAction,
    to sessionID: String,
    capabilityRevision: UInt64
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
      capabilityRevision: NSNumber(value: capabilityRevision),
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

  private func receive(
    _ snapshot: MediaAdapterSnapshot?,
    from generation: UInt64
  ) async {
    guard connectionGeneration.accepts(generation) else {
      return
    }
    await onSnapshot(snapshot)
  }

  private func invalidateConnection() {
    connectionGeneration.invalidate()
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
  private let connectionGeneration: UInt64
  private let onUpdate: @Sendable (UInt64, MediaAdapterSnapshot?) -> Void
  private var didPublishUnavailable = false
  private var retainedArtwork: MediaArtworkPayload?

  init(
    connectionGeneration: UInt64,
    onUpdate: @escaping @Sendable (UInt64, MediaAdapterSnapshot?) -> Void
  ) {
    self.connectionGeneration = connectionGeneration
    self.onUpdate = onUpdate
  }

  func mediaRemoteDidUpdate(_ propertyList: NSDictionary) {
    let snapshot = lock.withLock { () -> MediaAdapterSnapshot? in
      didPublishUnavailable = false
      guard propertyList["isPresent"] as? Bool == true else {
        retainedArtwork = nil
        return nil
      }
      let artworkUpdate =
        (propertyList["artworkUpdate"] as? String)
        .flatMap(MediaArtworkWireUpdate.init(rawValue:))
        ?? (propertyList["artworkData"] is Data ? .replace : .clear)
      guard
        let snapshot = MediaAdapterSnapshot(
          propertyList: propertyList,
          retainedArtwork: retainedArtwork
        )
      else {
        return nil
      }
      switch artworkUpdate {
      case .unchanged:
        break
      case .replace:
        retainedArtwork = snapshot.session.artworkData.map {
          MediaArtworkPayload(
            data: $0,
            mimeType: snapshot.session.artworkMIMEType
          )
        }
      case .clear:
        retainedArtwork = nil
      }
      return snapshot
    }
    onUpdate(connectionGeneration, snapshot)
  }

  func publishUnavailable() {
    let shouldPublish = lock.withLock {
      guard !didPublishUnavailable else {
        return false
      }
      didPublishUnavailable = true
      retainedArtwork = nil
      return true
    }
    guard shouldPublish else {
      return
    }
    onUpdate(connectionGeneration, nil)
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
    case .hideSource, .favorite, .repeatOne, .copySource:
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
