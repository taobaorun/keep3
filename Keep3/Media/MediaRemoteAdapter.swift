import Foundation

actor UnavailableMediaRemoteAdapter: MediaSessionProviding {
  func start() -> MediaCompatibilityReport {
    .unavailable
  }

  func stop() {}
}

actor MediaRemoteAdapter: MediaSessionProviding {
  static let serviceName = "dev.keep3.Keep3.MediaRemoteService"

  private var connection: NSXPCConnection?

  func start() async -> MediaCompatibilityReport {
    disconnect()

    let request = CompatibilityRequest()
    let connection = NSXPCConnection(serviceName: Self.serviceName)
    connection.remoteObjectInterface = NSXPCInterface(with: MediaRemoteServiceProtocol.self)
    connection.interruptionHandler = {
      request.complete(with: .unavailable)
    }
    connection.invalidationHandler = {
      request.complete(with: .unavailable)
    }
    self.connection = connection
    connection.resume()

    guard
      let service = connection.remoteObjectProxyWithErrorHandler({ _ in
        request.complete(with: .unavailable)
      }) as? MediaRemoteServiceProtocol
    else {
      disconnect()
      return .unavailable
    }

    service.compatibilityReport { propertyList in
      request.complete(
        with: MediaCompatibilityReport(propertyList: propertyList) ?? .unavailable
      )
    }

    let report = await request.value()
    if report.status == .unavailable {
      disconnect()
    }
    return report
  }

  func stop() {
    disconnect()
  }

  private func disconnect() {
    let connection = connection
    self.connection = nil
    connection?.interruptionHandler = nil
    connection?.invalidationHandler = nil
    connection?.invalidate()
  }
}

private final class CompatibilityRequest: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<MediaCompatibilityReport, Never>?
  private var report: MediaCompatibilityReport?

  func value() async -> MediaCompatibilityReport {
    await withCheckedContinuation { continuation in
      lock.withLock {
        if let report {
          continuation.resume(returning: report)
        } else {
          self.continuation = continuation
        }
      }
    }
  }

  func complete(with report: MediaCompatibilityReport) {
    lock.withLock {
      guard self.report == nil else { return }
      self.report = report
      continuation?.resume(returning: report)
      continuation = nil
    }
  }
}
