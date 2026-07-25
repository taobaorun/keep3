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
  private let scheduler: any RotationTimerScheduling
  private let onVisibleItemChange: (UUID?) -> Void

  private var schedule = RotationSchedule(
    itemIDs: [],
    currentFocusID: nil
  )
  private var timer: (any RotationTimerCancellation)?
  private var isRotationEnabled = true
  private var isPaused = false

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
    guard !isPaused else {
      return
    }
    isPaused = true
    cancelTimer()
  }

  func resumeResettingToCurrentFocus() {
    guard isPaused else {
      resetToCurrentFocus()
      return
    }
    isPaused = false
    resetToCurrentFocus()
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
