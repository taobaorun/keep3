import Foundation

private final class MediaRemoteServiceDelegate: NSObject, NSXPCListenerDelegate {
  #if !DEBUG
    private weak var activeConnection: NSXPCConnection?
  #endif

  func listener(
    _: NSXPCListener,
    shouldAcceptNewConnection newConnection: NSXPCConnection
  ) -> Bool {
    #if !DEBUG
      guard activeConnection == nil else {
        return false
      }
    #endif
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
    #if !DEBUG
      activeConnection = newConnection
      newConnection.interruptionHandler = {
        [weak service, weak newConnection] in
        service?.invalidateClient()
        newConnection?.invalidate()
      }
      newConnection.invalidationHandler = {
        [weak self, weak newConnection, weak service] in
        service?.invalidateClient()
        guard let newConnection,
          self?.activeConnection === newConnection
        else {
          return
        }
        self?.activeConnection = nil
      }
    #endif
    newConnection.resume()
    return true
  }
}

private let delegate = MediaRemoteServiceDelegate()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
RunLoop.current.run()
