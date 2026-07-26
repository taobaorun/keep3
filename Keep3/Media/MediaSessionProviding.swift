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
