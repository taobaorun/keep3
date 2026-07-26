import Foundation

struct TopSurfacePresentationState: Equatable, Sendable {
  let visibleItemID: UUID?
  let isExpanded: Bool
}

enum TopSurfaceBrowseDirection {
  case previous
  case next
}

enum TopSurfaceGesturePhase: Equatable, Sendable {
  case none
  case began
  case changed
  case ended
  case cancelled
}

@MainActor
protocol AppTimerCancellation: AnyObject {
  func cancel()
}

@MainActor
protocol AppTimerScheduling {
  func schedule(
    after delay: TimeInterval,
    action: @escaping @MainActor () -> Void
  ) -> any AppTimerCancellation
}

@MainActor
final class TopSurfaceInteractionModel {
  private static let expansionDelay: TimeInterval = 0.4
  private static let collapseDelay: TimeInterval = 0.2
  private static let scrollThreshold: CGFloat = 20

  private let scheduler: any AppTimerScheduling
  private let onIntent: (TopSurfaceInteractionIntent) -> Void
  private let onPauseRotation: () -> Void
  private let onResumeRotation: () -> Void
  private let onOpenItem: (UUID) -> Void

  private var itemIDs: [UUID] = []
  private var currentFocusID: UUID?
  private var expansionTrigger: SurfaceExpansionTrigger = .hover
  private var visibleIndex: Int?
  private var isExpanded = false
  private var isPointerInside = false
  private var isRotationPaused = false
  private var timer: (any AppTimerCancellation)?
  private var scrollAccumulator: CGFloat = 0
  private var didNavigateDuringScrollGesture = false

  init(
    scheduler: any AppTimerScheduling = TaskAppTimerScheduler(),
    onIntent: @escaping (TopSurfaceInteractionIntent) -> Void,
    onPauseRotation: @escaping () -> Void,
    onResumeRotation: @escaping () -> Void,
    onOpenItem: @escaping (UUID) -> Void
  ) {
    self.scheduler = scheduler
    self.onIntent = onIntent
    self.onPauseRotation = onPauseRotation
    self.onResumeRotation = onResumeRotation
    self.onOpenItem = onOpenItem
  }

  func update(itemIDs: [UUID], currentFocusID: UUID?) {
    cancelTimer()
    self.itemIDs = itemIDs
    self.currentFocusID =
      currentFocusID.flatMap {
        itemIDs.contains($0) ? $0 : nil
      } ?? itemIDs.first
    visibleIndex = self.currentFocusID.flatMap { itemIDs.firstIndex(of: $0) }
    isExpanded =
      expansionTrigger == .hover && isPointerInside && !itemIDs.isEmpty
    emitPresentation()
  }

  func setExpansionTrigger(_ trigger: SurfaceExpansionTrigger) {
    guard expansionTrigger != trigger else {
      return
    }

    expansionTrigger = trigger
    cancelTimer()
    isExpanded = false
    resetToCurrentFocus()

    if trigger == .hover, isPointerInside, !itemIDs.isEmpty {
      scheduleExpansion()
    }
  }

  func showRotatedItem(_ itemID: UUID?) {
    guard !isExpanded else {
      return
    }

    visibleIndex = itemID.flatMap { itemIDs.firstIndex(of: $0) }
    emitPresentation()
  }

  func synchronizeToCurrentFocusWithoutPresentation() {
    cancelTimer()
    visibleIndex = currentFocusID.flatMap { itemIDs.firstIndex(of: $0) }
    isExpanded = false
    scrollAccumulator = 0
    didNavigateDuringScrollGesture = false
    resumeRotationIfNeeded()
  }

  func synchronizeUnifiedExpansion(_ shouldExpand: Bool) {
    guard isExpanded != shouldExpand else {
      return
    }

    cancelTimer()
    isExpanded = shouldExpand
    scrollAccumulator = 0
    didNavigateDuringScrollGesture = false

    if shouldExpand {
      pauseRotationIfNeeded()
    } else {
      resetToCurrentFocus()
      resumeRotationIfNeeded()
    }
  }

  func pointerEntered() {
    guard !isPointerInside else {
      return
    }

    isPointerInside = true
    cancelTimer()

    guard expansionTrigger == .hover, !isExpanded, !itemIDs.isEmpty else {
      return
    }

    scheduleExpansion()
  }

  func pointerExited() {
    guard isPointerInside else {
      return
    }

    isPointerInside = false
    cancelTimer()

    guard isExpanded else {
      resetToCurrentFocus()
      resumeRotationIfNeeded()
      return
    }

    timer = scheduler.schedule(after: Self.collapseDelay) { [weak self] in
      guard let self, !self.isPointerInside else {
        return
      }
      self.timer = nil
      self.isExpanded = false
      self.resetToCurrentFocus()
      self.resumeRotationIfNeeded()
    }
  }

  func browse(_ direction: TopSurfaceBrowseDirection) {
    guard isExpanded, itemIDs.count > 1, let visibleIndex else {
      return
    }

    switch direction {
    case .previous:
      self.visibleIndex = (visibleIndex - 1 + itemIDs.count) % itemIDs.count
    case .next:
      self.visibleIndex = (visibleIndex + 1) % itemIDs.count
    }
    emitPresentation()
  }

  func scroll(delta: CGFloat, phase: TopSurfaceGesturePhase) {
    guard isExpanded else {
      return
    }

    switch phase {
    case .none:
      scrollAccumulator = delta
      didNavigateDuringScrollGesture = false
    case .began:
      scrollAccumulator = delta
      didNavigateDuringScrollGesture = false
    case .changed:
      scrollAccumulator += delta
    case .ended, .cancelled:
      scrollAccumulator = 0
      didNavigateDuringScrollGesture = false
      return
    }

    guard !didNavigateDuringScrollGesture,
      abs(scrollAccumulator) >= Self.scrollThreshold
    else {
      return
    }

    browse(scrollAccumulator > 0 ? .next : .previous)
    didNavigateDuringScrollGesture = true

    if phase == .none {
      scrollAccumulator = 0
      didNavigateDuringScrollGesture = false
    }
  }

  func activateVisibleItem() {
    guard let visibleItemID else {
      return
    }
    onOpenItem(visibleItemID)
  }

  func activateSurface() {
    guard expansionTrigger == .click, !isExpanded, !itemIDs.isEmpty else {
      return
    }

    isPointerInside = true
    cancelTimer()
    pauseRotationIfNeeded()
    isExpanded = true
    emitPresentation()
  }

  func dismissExpandedSurface() {
    guard isExpanded || isPointerInside else {
      return
    }

    cancelTimer()
    isPointerInside = false
    isExpanded = false
    resetToCurrentFocus()
    resumeRotationIfNeeded()
  }

  func suspend() {
    cancelTimer()
    isPointerInside = false
    isExpanded = false
    isRotationPaused = false
    scrollAccumulator = 0
    didNavigateDuringScrollGesture = false
  }

  private var visibleItemID: UUID? {
    guard let visibleIndex, itemIDs.indices.contains(visibleIndex) else {
      return nil
    }
    return itemIDs[visibleIndex]
  }

  private func resetToCurrentFocus() {
    visibleIndex = currentFocusID.flatMap { itemIDs.firstIndex(of: $0) }
    emitPresentation()
  }

  private func emitPresentation() {
    onIntent(.focus(visibleItemID: visibleItemID, isExpanded: isExpanded))
  }

  private func scheduleExpansion() {
    timer = scheduler.schedule(after: Self.expansionDelay) { [weak self] in
      guard let self, self.isPointerInside else {
        return
      }
      self.timer = nil
      self.pauseRotationIfNeeded()
      self.isExpanded = true
      self.emitPresentation()
    }
  }

  private func pauseRotationIfNeeded() {
    guard !isRotationPaused else {
      return
    }
    isRotationPaused = true
    onPauseRotation()
  }

  private func resumeRotationIfNeeded() {
    guard isRotationPaused else {
      return
    }
    isRotationPaused = false
    onResumeRotation()
  }

  private func cancelTimer() {
    timer?.cancel()
    timer = nil
  }
}

@MainActor
final class TaskAppTimerScheduler: AppTimerScheduling {
  func schedule(
    after delay: TimeInterval,
    action: @escaping @MainActor () -> Void
  ) -> any AppTimerCancellation {
    let task = Task { @MainActor in
      do {
        try await Task.sleep(for: .seconds(delay))
      } catch {
        return
      }
      action()
    }
    return TaskAppTimerCancellation(task: task)
  }
}

@MainActor
private final class TaskAppTimerCancellation:
  AppTimerCancellation
{
  private let task: Task<Void, Never>

  init(task: Task<Void, Never>) {
    self.task = task
  }

  func cancel() {
    task.cancel()
  }
}
