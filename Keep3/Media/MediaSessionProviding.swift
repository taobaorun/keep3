import Foundation

protocol MediaSessionProviding: AnyObject {
  func start() async -> MediaCompatibilityReport
  func stop() async
}
