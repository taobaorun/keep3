import Foundation

@MainActor
protocol RotationTimerCancellation: AnyObject {
  func cancel()
}

@MainActor
protocol RotationTimerScheduling {
  func schedule(
    after delay: TimeInterval,
    action: @escaping @MainActor () -> Void
  ) -> any RotationTimerCancellation
}

@MainActor
final class RotationCoordinator {
  private enum PauseReason: Hashable {
    case direct
    case focusInteraction
    case mediaSurface
    case surfaceUnavailable
  }

  private enum ResumeBehavior {
    case presentCurrentFocus
    case currentFocusAlreadyPresented
  }

  private let scheduler: any RotationTimerScheduling
  private let onVisibleItemChange: (UUID?) -> Void

  private var schedule = RotationSchedule(
    itemIDs: [],
    currentFocusID: nil
  )
  private var timer: (any RotationTimerCancellation)?
  private var isRotationEnabled = true
  private var pauseReasons: Set<PauseReason> = []

  private var isPaused: Bool {
    !pauseReasons.isEmpty
  }

  init(
    scheduler: any RotationTimerScheduling = TaskRotationTimerScheduler(),
    onVisibleItemChange: @escaping (UUID?) -> Void
  ) {
    self.scheduler = scheduler
    self.onVisibleItemChange = onVisibleItemChange
  }

  func update(
    itemIDs: [UUID],
    currentFocusID: UUID?,
    durations: RotationDurations = .default
  ) {
    cancelTimer()
    schedule = RotationSchedule(
      itemIDs: itemIDs,
      currentFocusID: currentFocusID,
      durations: durations
    )
    onVisibleItemChange(schedule.currentEntry?.itemID)
    scheduleNextDeadlineIfNeeded()
  }

  func setRotationEnabled(_ isEnabled: Bool) {
    guard isRotationEnabled != isEnabled else {
      return
    }
    isRotationEnabled = isEnabled
    resetToCurrentFocus()
  }

  func pause() {
    setPauseReason(.direct, isActive: true)
  }

  func resumeResettingToCurrentFocus() {
    guard pauseReasons.contains(.direct) else {
      resetToCurrentFocus()
      return
    }
    setPauseReason(
      .direct,
      isActive: false,
      resumeBehavior: .presentCurrentFocus
    )
  }

  func resumeAfterCurrentFocusWasPresented() {
    setPauseReason(
      .direct,
      isActive: false,
      resumeBehavior: .currentFocusAlreadyPresented
    )
  }

  func setFocusInteractionPaused(_ isPaused: Bool) {
    setPauseReason(
      .focusInteraction,
      isActive: isPaused,
      resumeBehavior: .presentCurrentFocus
    )
  }

  func setMediaSurfacePresented(_ isPresented: Bool) {
    setPauseReason(
      .mediaSurface,
      isActive: isPresented,
      resumeBehavior: .currentFocusAlreadyPresented
    )
  }

  func setSurfaceAvailable(_ isAvailable: Bool) {
    setPauseReason(
      .surfaceUnavailable,
      isActive: !isAvailable,
      resumeBehavior: .currentFocusAlreadyPresented
    )
  }

  private func resetToCurrentFocus() {
    cancelTimer()
    onVisibleItemChange(schedule.reset()?.itemID)
    scheduleNextDeadlineIfNeeded()
  }

  private func scheduleNextDeadlineIfNeeded() {
    guard isRotationEnabled,
      !isPaused,
      schedule.canRotate,
      let entry = schedule.currentEntry
    else {
      return
    }

    timer = scheduler.schedule(after: entry.duration) { [weak self] in
      self?.deadlineReached()
    }
  }

  private func deadlineReached() {
    timer = nil
    guard isRotationEnabled, !isPaused else {
      return
    }
    onVisibleItemChange(schedule.advance()?.itemID)
    scheduleNextDeadlineIfNeeded()
  }

  private func cancelTimer() {
    timer?.cancel()
    timer = nil
  }

  private func setPauseReason(
    _ reason: PauseReason,
    isActive: Bool,
    resumeBehavior: ResumeBehavior = .currentFocusAlreadyPresented
  ) {
    let wasPaused = isPaused
    if isActive {
      guard pauseReasons.insert(reason).inserted else {
        return
      }
    } else {
      guard pauseReasons.remove(reason) != nil else {
        return
      }
    }

    if !wasPaused, isPaused {
      cancelTimer()
      return
    }

    guard wasPaused, !isPaused else {
      return
    }

    cancelTimer()
    let currentFocusID = schedule.reset()?.itemID
    switch resumeBehavior {
    case .presentCurrentFocus:
      onVisibleItemChange(currentFocusID)
    case .currentFocusAlreadyPresented:
      break
    }
    scheduleNextDeadlineIfNeeded()
  }
}

@MainActor
private final class TaskRotationTimerScheduler: RotationTimerScheduling {
  func schedule(
    after delay: TimeInterval,
    action: @escaping @MainActor () -> Void
  ) -> any RotationTimerCancellation {
    let task = Task { @MainActor in
      do {
        try await Task.sleep(for: .seconds(delay))
      } catch {
        return
      }
      action()
    }
    return TaskRotationTimerCancellation(task: task)
  }
}

@MainActor
private final class TaskRotationTimerCancellation: RotationTimerCancellation {
  private let task: Task<Void, Never>

  init(task: Task<Void, Never>) {
    self.task = task
  }

  func cancel() {
    task.cancel()
  }
}
