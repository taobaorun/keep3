import Foundation

@objc(MediaRemoteServiceProtocol)
protocol MediaRemoteServiceProtocol: AnyObject {
  func compatibilityReport(reply: @escaping (NSDictionary) -> Void)
}
