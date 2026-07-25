import Foundation

private final class MediaRemoteServiceDelegate: NSObject, NSXPCListenerDelegate {
  func listener(
    _: NSXPCListener,
    shouldAcceptNewConnection newConnection: NSXPCConnection
  ) -> Bool {
    newConnection.exportedInterface = NSXPCInterface(with: MediaRemoteServiceProtocol.self)
    newConnection.exportedObject = MediaRemoteService()
    newConnection.resume()
    return true
  }
}

private let delegate = MediaRemoteServiceDelegate()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
RunLoop.current.run()
