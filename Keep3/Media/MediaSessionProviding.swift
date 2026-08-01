import Foundation

typealias MediaAdapterSnapshotDelivery =
  @MainActor @Sendable (MediaAdapterSnapshot?) -> Void

protocol MediaSessionProviding: AnyObject, Sendable {
  func start() async -> MediaCompatibilityReport
  func stop() async
}

protocol MediaSessionAdapter: MediaSessionProviding, MediaCommandSending {}

@MainActor
final class SerialMediaLifecycleQueue {
  private var tail: Task<Void, Never>?

  func enqueue(
    _ operation: @escaping @MainActor () async -> Void
  ) {
    let precedingOperation = tail
    tail = Task { @MainActor in
      await precedingOperation?.value
      await operation()
    }
  }

  func waitUntilIdle() async {
    await tail?.value
  }
}

struct MediaAdapterConnectionGeneration {
  private var current: UInt64 = 0
  private var active: UInt64?

  mutating func advance() -> UInt64 {
    current &+= 1
    active = current
    return current
  }

  mutating func invalidate() {
    current &+= 1
    active = nil
  }

  func accepts(_ candidate: UInt64) -> Bool {
    active == candidate
  }
}

struct MediaAdapterConnectionRecoveryPolicy {
  private static let retryDelays: [TimeInterval] = [0.5, 2, 5, 15, 30]
  private(set) var isMonitoring = false
  private var retryAttempt = 0

  mutating func beginMonitoring() {
    isMonitoring = true
    retryAttempt = 0
  }

  mutating func endMonitoring() {
    isMonitoring = false
    retryAttempt = 0
  }

  mutating func didRecover() {
    retryAttempt = 0
  }

  mutating func nextRetryDelay() -> TimeInterval? {
    guard isMonitoring else {
      return nil
    }
    let delay = Self.retryDelays[
      min(retryAttempt, Self.retryDelays.count - 1)
    ]
    retryAttempt = min(retryAttempt + 1, Self.retryDelays.count - 1)
    return delay
  }
}
