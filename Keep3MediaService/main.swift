import Foundation

private final class MediaRemoteServiceDelegate: NSObject, NSXPCListenerDelegate {
  func listener(
    _: NSXPCListener,
    shouldAcceptNewConnection newConnection: NSXPCConnection
  ) -> Bool {
    let service = MediaRemoteService()
    newConnection.exportedInterface = MediaRemoteXPCInterface.service()
    newConnection.exportedObject = service
    newConnection.remoteObjectInterface = MediaRemoteXPCInterface.client()
    guard
      let client = newConnection.remoteObjectProxyWithErrorHandler({
        _ in
      }) as? MediaRemoteClientProtocol
    else {
      return false
    }
    service.attach(client: client)
    newConnection.resume()
    return true
  }
}

private let delegate = MediaRemoteServiceDelegate()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
RunLoop.current.run()
