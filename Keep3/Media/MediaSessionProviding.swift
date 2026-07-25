import Foundation

typealias MediaAdapterSnapshotDelivery =
  @MainActor @Sendable (MediaAdapterSnapshot?) -> Void

protocol MediaSessionProviding: AnyObject, Sendable {
  func start() async -> MediaCompatibilityReport
  func stop() async
}

protocol MediaSessionAdapter: MediaSessionProviding, MediaCommandSending {}
