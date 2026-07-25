import Foundation

enum MediaCommandDispatchResult: Equatable, Sendable {
  case rejected
  case accepted
  case confirmed
}

protocol MediaCommandSending: Sendable {
  func send(
    _ action: MediaSurfaceAction,
    to sessionID: String
  ) async -> MediaCommandDispatchResult
}

@MainActor
final class MediaCommandCoordinator {
  private static let confirmationTimeout: TimeInterval = 2

  private struct PendingCommand: Equatable {
    let token: UUID
    let action: MediaSurfaceAction
    let sessionID: String
    let subscriptionEpoch: UInt64
    let capabilityRevision: UInt64
    let contentRevisionBeforeDispatch: UInt64

    var requiresTrackConfirmation: Bool {
      action == .previous || action == .next
    }
  }

  private let sender: any MediaCommandSending
  private let haptic: any MediaHapticPerforming
  private let scheduler: any AppTimerScheduling
  private let onPendingActionChange: (MediaSurfaceAction?) -> Void
  private var currentSnapshot: MediaSessionSnapshot?
  private var isMediaActive = false
  private var pending: PendingCommand?
  private var timeout: (any AppTimerCancellation)?
  private var lastCompletedToken: UUID?

  init(
    sender: any MediaCommandSending,
    haptic: any MediaHapticPerforming = AppKitMediaHapticFeedback(),
    scheduler: any AppTimerScheduling =
      TaskAppTimerScheduler(),
    onPendingActionChange: @escaping (MediaSurfaceAction?) -> Void = {
      _ in
    }
  ) {
    self.sender = sender
    self.haptic = haptic
    self.scheduler = scheduler
    self.onPendingActionChange = onPendingActionChange
  }

  var pendingAction: MediaSurfaceAction? {
    pending?.action
  }

  func updateContext(
    snapshot: MediaSessionSnapshot?,
    isMediaActive: Bool
  ) {
    guard isMediaActive, let snapshot else {
      currentSnapshot = snapshot
      self.isMediaActive = false
      clearPending()
      return
    }

    if let currentSnapshot,
      currentSnapshot.subscriptionEpoch != snapshot.subscriptionEpoch
        || currentSnapshot.session.sessionID != snapshot.session.sessionID
        || currentSnapshot.capabilityRevision != snapshot.capabilityRevision
    {
      clearPending()
    }
    currentSnapshot = snapshot
    self.isMediaActive = true
  }

  @discardableResult
  func perform(_ action: MediaSurfaceAction) async -> Bool {
    guard isMediaActive, pending == nil, let snapshot = currentSnapshot,
      supports(action, in: snapshot.session)
    else {
      return false
    }

    let command = PendingCommand(
      token: UUID(),
      action: action,
      sessionID: snapshot.session.sessionID,
      subscriptionEpoch: snapshot.subscriptionEpoch,
      capabilityRevision: snapshot.capabilityRevision,
      contentRevisionBeforeDispatch: snapshot.contentRevision
    )
    lastCompletedToken = nil
    pending = command
    onPendingActionChange(action)

    let result = await sender.send(
      action,
      to: snapshot.session.sessionID
    )
    guard pending?.token == command.token else {
      return lastCompletedToken == command.token
    }

    switch result {
    case .rejected:
      clearPending()
      return false
    case .confirmed:
      complete(command)
      return true
    case .accepted:
      guard command.requiresTrackConfirmation else {
        clearPending()
        return true
      }
      scheduleTimeout(for: command)
      return true
    }
  }

  func receive(_ snapshot: MediaSessionSnapshot) {
    defer {
      currentSnapshot = snapshot
    }
    guard isMediaActive, let pending,
      pending.requiresTrackConfirmation,
      snapshot.subscriptionEpoch == pending.subscriptionEpoch,
      snapshot.session.sessionID == pending.sessionID,
      snapshot.capabilityRevision == pending.capabilityRevision,
      snapshot.contentRevision > pending.contentRevisionBeforeDispatch
    else {
      if let currentSnapshot,
        snapshot.subscriptionEpoch != currentSnapshot.subscriptionEpoch
          || snapshot.session.sessionID
            != currentSnapshot.session.sessionID
          || snapshot.capabilityRevision
            != currentSnapshot.capabilityRevision
      {
        clearPending()
      }
      return
    }

    complete(pending)
  }

  func cancel() {
    isMediaActive = false
    currentSnapshot = nil
    clearPending()
  }

  private func supports(
    _ action: MediaSurfaceAction,
    in session: MediaSession
  ) -> Bool {
    let requiredCapability: MediaCapability?
    switch action {
    case .previous:
      requiredCapability = .previous
    case .togglePlayPause:
      requiredCapability = .playPause
    case .next:
      requiredCapability = .next
    case .seek:
      requiredCapability = .seek
    case .shuffle:
      requiredCapability = .shuffle
    case .repeatMode:
      requiredCapability = .repeatMode
    case .hideSource:
      return false
    }
    return requiredCapability.map(session.capabilities.contains) ?? false
  }

  private func complete(_ command: PendingCommand) {
    guard pending?.token == command.token else {
      return
    }
    lastCompletedToken = command.token
    clearPending()
    if command.requiresTrackConfirmation {
      haptic.performConfirmedTrackChange()
    }
  }

  private func scheduleTimeout(for command: PendingCommand) {
    timeout?.cancel()
    timeout = scheduler.schedule(after: Self.confirmationTimeout) {
      [weak self] in
      guard self?.pending?.token == command.token else {
        return
      }
      self?.clearPending()
    }
  }

  private func clearPending() {
    let hadPending = pending != nil
    timeout?.cancel()
    timeout = nil
    pending = nil
    if hadPending {
      onPendingActionChange(nil)
    }
  }
}
