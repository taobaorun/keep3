import XCTest

@testable import Keep3

@MainActor
final class RotationScheduleTests: XCTestCase {
  func testThreeItemScheduleAlternatesCurrentBetweenSecondaries() {
    let currentID = UUID()
    let secondaryA = UUID()
    let secondaryB = UUID()
    var schedule = RotationSchedule(
      itemIDs: [secondaryA, currentID, secondaryB],
      currentFocusID: currentID
    )

    var entries: [RotationSchedule.Entry] = [schedule.currentEntry!]
    entries.append(schedule.advance()!)
    entries.append(schedule.advance()!)
    entries.append(schedule.advance()!)

    XCTAssertEqual(
      entries,
      [
        .init(itemID: currentID, duration: 30),
        .init(itemID: secondaryA, duration: 8),
        .init(itemID: currentID, duration: 30),
        .init(itemID: secondaryB, duration: 8),
      ]
    )
    XCTAssertEqual(schedule.advance(), entries[0])
  }

  func testTwoItemScheduleAlternatesCurrentAndSecondary() {
    let currentID = UUID()
    let secondaryID = UUID()
    var schedule = RotationSchedule(
      itemIDs: [currentID, secondaryID],
      currentFocusID: currentID
    )

    XCTAssertEqual(
      schedule.currentEntry,
      .init(itemID: currentID, duration: 30)
    )
    XCTAssertEqual(
      schedule.advance(),
      .init(itemID: secondaryID, duration: 8)
    )
    XCTAssertEqual(
      schedule.advance(),
      .init(itemID: currentID, duration: 30)
    )
  }

  func testDurationsAreClampedToDocumentedBounds() {
    XCTAssertEqual(
      RotationDurations(currentFocus: 1, secondary: 100),
      RotationDurations(currentFocus: 30, secondary: 30)
    )
    XCTAssertEqual(
      RotationDurations(currentFocus: 1_000, secondary: 1),
      RotationDurations(currentFocus: 600, secondary: 4)
    )
  }

  func testCoordinatorDoesNotScheduleForZeroOrOneItem() {
    let scheduler = ManualRotationTimerScheduler()
    let coordinator = RotationCoordinator(scheduler: scheduler) { _ in }

    coordinator.update(itemIDs: [], currentFocusID: nil)
    XCTAssertEqual(scheduler.activeTimerCount, 0)

    let onlyID = UUID()
    coordinator.update(itemIDs: [onlyID], currentFocusID: onlyID)
    XCTAssertEqual(scheduler.activeTimerCount, 0)
  }

  func testCoordinatorSchedulesOneDeadlineAtATimeAndAdvances() {
    let currentID = UUID()
    let secondaryID = UUID()
    let scheduler = ManualRotationTimerScheduler()
    var visibleIDs: [UUID?] = []
    let coordinator = RotationCoordinator(scheduler: scheduler) {
      visibleIDs.append($0)
    }

    coordinator.update(
      itemIDs: [currentID, secondaryID],
      currentFocusID: currentID
    )

    XCTAssertEqual(visibleIDs, [currentID])
    XCTAssertEqual(scheduler.activeDelays, [30])

    scheduler.fireNext()

    XCTAssertEqual(visibleIDs, [currentID, secondaryID])
    XCTAssertEqual(scheduler.activeDelays, [8])
  }

  func testPauseCancelsDeadlineAndResumeResetsToCurrentFocus() {
    let currentID = UUID()
    let secondaryID = UUID()
    let scheduler = ManualRotationTimerScheduler()
    var visibleIDs: [UUID?] = []
    let coordinator = RotationCoordinator(scheduler: scheduler) {
      visibleIDs.append($0)
    }
    coordinator.update(
      itemIDs: [currentID, secondaryID],
      currentFocusID: currentID
    )
    scheduler.fireNext()

    coordinator.pause()

    XCTAssertEqual(scheduler.activeTimerCount, 0)

    coordinator.resumeResettingToCurrentFocus()

    XCTAssertEqual(visibleIDs.last!, currentID)
    XCTAssertEqual(scheduler.activeDelays, [30])
  }

  func testMediaResumeRestartsFullCurrentFocusDeadlineWithoutRepublishing() {
    let currentID = UUID()
    let secondaryID = UUID()
    let scheduler = ManualRotationTimerScheduler()
    var visibleIDs: [UUID?] = []
    let coordinator = RotationCoordinator(scheduler: scheduler) {
      visibleIDs.append($0)
    }
    coordinator.update(
      itemIDs: [currentID, secondaryID],
      currentFocusID: currentID
    )
    scheduler.fireNext()
    coordinator.pause()
    let publicationCountBeforeResume = visibleIDs.count

    coordinator.resumeAfterCurrentFocusWasPresented()

    XCTAssertEqual(visibleIDs.count, publicationCountBeforeResume)
    XCTAssertEqual(scheduler.activeDelays, [30])

    scheduler.fireNext()
    XCTAssertEqual(visibleIDs.last!, secondaryID)
  }

  func testDisablingRotationLeavesCurrentFocusVisibleWithoutTimer() {
    let currentID = UUID()
    let secondaryID = UUID()
    let scheduler = ManualRotationTimerScheduler()
    var visibleIDs: [UUID?] = []
    let coordinator = RotationCoordinator(scheduler: scheduler) {
      visibleIDs.append($0)
    }
    coordinator.update(
      itemIDs: [currentID, secondaryID],
      currentFocusID: currentID
    )

    coordinator.setRotationEnabled(false)

    XCTAssertEqual(visibleIDs.last!, currentID)
    XCTAssertEqual(scheduler.activeTimerCount, 0)
  }
}

@MainActor
private final class ManualRotationTimerScheduler: RotationTimerScheduling {
  private final class Timer: RotationTimerCancellation {
    let delay: TimeInterval
    let action: () -> Void
    var isCancelled = false

    init(delay: TimeInterval, action: @escaping () -> Void) {
      self.delay = delay
      self.action = action
    }

    func cancel() {
      isCancelled = true
    }
  }

  private var timers: [Timer] = []

  var activeDelays: [TimeInterval] {
    timers.filter { !$0.isCancelled }.map(\.delay)
  }

  var activeTimerCount: Int {
    activeDelays.count
  }

  func schedule(
    after delay: TimeInterval,
    action: @escaping @MainActor () -> Void
  ) -> any RotationTimerCancellation {
    let timer = Timer(delay: delay, action: action)
    timers.append(timer)
    return timer
  }

  func fireNext() {
    guard let timer = timers.first(where: { !$0.isCancelled }) else {
      return
    }
    timer.isCancelled = true
    timer.action()
  }
}
