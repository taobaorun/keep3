import XCTest

@testable import Keep3

@MainActor
final class TopSurfaceInteractionTests: XCTestCase {
  func testFastPassOverDoesNotPauseOrResetRotation() {
    let currentID = UUID()
    let scheduler = ManualInteractionTimerScheduler()
    let recorder = InteractionRecorder()
    let coordinator = makeCoordinator(
      scheduler: scheduler,
      recorder: recorder
    )
    coordinator.update(itemIDs: [currentID], currentFocusID: currentID)

    coordinator.pointerEntered()
    XCTAssertEqual(recorder.pauseCount, 0)
    XCTAssertEqual(scheduler.activeDelays, [0.4])

    coordinator.pointerExited()

    XCTAssertEqual(scheduler.activeTimerCount, 0)
    XCTAssertEqual(recorder.resumeCount, 0)
    XCTAssertEqual(
      recorder.presentations.last,
      .init(visibleItemID: currentID, isExpanded: false)
    )
  }

  func testIntentionalHoverExpandsAndExitCollapsesAfterDelay() {
    let currentID = UUID()
    let scheduler = ManualInteractionTimerScheduler()
    let recorder = InteractionRecorder()
    let coordinator = makeCoordinator(
      scheduler: scheduler,
      recorder: recorder
    )
    coordinator.update(itemIDs: [currentID], currentFocusID: currentID)

    coordinator.pointerEntered()
    scheduler.fireNext()

    XCTAssertEqual(recorder.pauseCount, 1)
    XCTAssertEqual(
      recorder.presentations.last,
      .init(visibleItemID: currentID, isExpanded: true)
    )

    coordinator.pointerExited()
    XCTAssertEqual(scheduler.activeDelays, [0.2])
    scheduler.fireNext()

    XCTAssertEqual(recorder.resumeCount, 1)
    XCTAssertEqual(
      recorder.presentations.last,
      .init(visibleItemID: currentID, isExpanded: false)
    )
  }

  func testReenteringDuringCollapseDelayCancelsCollapse() {
    let currentID = UUID()
    let scheduler = ManualInteractionTimerScheduler()
    let recorder = InteractionRecorder()
    let coordinator = makeCoordinator(
      scheduler: scheduler,
      recorder: recorder
    )
    coordinator.update(itemIDs: [currentID], currentFocusID: currentID)
    coordinator.pointerEntered()
    scheduler.fireNext()
    coordinator.pointerExited()

    coordinator.pointerEntered()

    XCTAssertEqual(scheduler.activeTimerCount, 0)
    XCTAssertEqual(
      recorder.presentations.last,
      .init(visibleItemID: currentID, isExpanded: true)
    )
  }

  func testManualBrowsingWrapsWithoutChangingDesignatedCurrentFocus() {
    let firstID = UUID()
    let currentID = UUID()
    let thirdID = UUID()
    let scheduler = ManualInteractionTimerScheduler()
    let recorder = InteractionRecorder()
    let coordinator = makeCoordinator(
      scheduler: scheduler,
      recorder: recorder
    )
    coordinator.update(
      itemIDs: [firstID, currentID, thirdID],
      currentFocusID: currentID
    )
    coordinator.pointerEntered()
    scheduler.fireNext()

    coordinator.browse(.next)
    XCTAssertEqual(recorder.presentations.last?.visibleItemID, thirdID)
    coordinator.browse(.next)
    XCTAssertEqual(recorder.presentations.last?.visibleItemID, firstID)
    coordinator.browse(.previous)
    XCTAssertEqual(recorder.presentations.last?.visibleItemID, thirdID)

    coordinator.pointerExited()
    scheduler.fireNext()
    XCTAssertEqual(recorder.presentations.last?.visibleItemID, currentID)
  }

  func testScrollThresholdAcceptsOnlyOneStepPerGesture() {
    let firstID = UUID()
    let secondID = UUID()
    let thirdID = UUID()
    let scheduler = ManualInteractionTimerScheduler()
    let recorder = InteractionRecorder()
    let coordinator = makeCoordinator(
      scheduler: scheduler,
      recorder: recorder
    )
    coordinator.update(
      itemIDs: [firstID, secondID, thirdID],
      currentFocusID: firstID
    )
    coordinator.pointerEntered()
    scheduler.fireNext()

    coordinator.scroll(delta: 8, phase: .began)
    coordinator.scroll(delta: 14, phase: .changed)
    coordinator.scroll(delta: 50, phase: .changed)

    XCTAssertEqual(recorder.presentations.last?.visibleItemID, secondID)

    coordinator.scroll(delta: 0, phase: .ended)
    coordinator.scroll(delta: -25, phase: .began)

    XCTAssertEqual(recorder.presentations.last?.visibleItemID, firstID)
  }

  func testActivatingVisibleTitleRoutesOnlyThatItem() {
    let currentID = UUID()
    let secondaryID = UUID()
    let scheduler = ManualInteractionTimerScheduler()
    var openedIDs: [UUID] = []
    let coordinator = TopSurfaceInteractionModel(
      scheduler: scheduler,
      onIntent: { _ in },
      onPauseRotation: {},
      onResumeRotation: {},
      onOpenItem: { openedIDs.append($0) }
    )
    coordinator.update(
      itemIDs: [currentID, secondaryID],
      currentFocusID: currentID
    )
    coordinator.pointerEntered()
    scheduler.fireNext()
    coordinator.browse(.next)

    coordinator.activateVisibleItem()

    XCTAssertEqual(openedIDs, [secondaryID])
  }

  func testAutomaticRotationContinuesDuringHoverDelayAndPausesAfterExpansion() {
    let currentID = UUID()
    let secondaryID = UUID()
    let scheduler = ManualInteractionTimerScheduler()
    let recorder = InteractionRecorder()
    let coordinator = makeCoordinator(
      scheduler: scheduler,
      recorder: recorder
    )
    coordinator.update(
      itemIDs: [currentID, secondaryID],
      currentFocusID: currentID
    )

    coordinator.showRotatedItem(secondaryID)
    XCTAssertEqual(recorder.presentations.last?.visibleItemID, secondaryID)

    coordinator.pointerEntered()
    coordinator.showRotatedItem(currentID)
    XCTAssertEqual(recorder.presentations.last?.visibleItemID, currentID)

    scheduler.fireNext()
    coordinator.showRotatedItem(secondaryID)
    XCTAssertEqual(recorder.presentations.last?.visibleItemID, currentID)

    coordinator.pointerExited()
    scheduler.fireNext()
    XCTAssertEqual(recorder.presentations.last?.visibleItemID, currentID)
  }

  func testSynchronizingMediaExitResetsVisibleFocusWithoutEmitting() {
    let currentID = UUID()
    let secondaryID = UUID()
    let recorder = InteractionRecorder()
    let coordinator = makeCoordinator(
      scheduler: ManualInteractionTimerScheduler(),
      recorder: recorder
    )
    coordinator.update(
      itemIDs: [currentID, secondaryID],
      currentFocusID: currentID
    )
    coordinator.showRotatedItem(secondaryID)
    let publicationCountBeforeSync = recorder.presentations.count

    coordinator.synchronizeToCurrentFocusWithoutPresentation()

    XCTAssertEqual(recorder.presentations.count, publicationCountBeforeSync)
    coordinator.activateVisibleItem()
    XCTAssertEqual(recorder.openedIDs, [currentID])
  }

  func testUnifiedExpansionEnablesBrowsingAndCollapseResetsFocus() {
    let currentID = UUID()
    let secondaryID = UUID()
    let recorder = InteractionRecorder()
    let coordinator = makeCoordinator(
      scheduler: ManualInteractionTimerScheduler(),
      recorder: recorder
    )
    coordinator.update(
      itemIDs: [currentID, secondaryID],
      currentFocusID: currentID
    )

    coordinator.synchronizeUnifiedExpansion(true)
    coordinator.browse(.next)

    XCTAssertEqual(recorder.pauseCount, 1)
    XCTAssertEqual(recorder.presentations.last?.visibleItemID, secondaryID)
    XCTAssertEqual(recorder.presentations.last?.isExpanded, true)

    coordinator.synchronizeUnifiedExpansion(false)

    XCTAssertEqual(recorder.resumeCount, 1)
    XCTAssertEqual(recorder.presentations.last?.visibleItemID, currentID)
    XCTAssertEqual(recorder.presentations.last?.isExpanded, false)
  }

  func testSuspendingCancelsPendingInteractionAndAllowsFreshHover() {
    let currentID = UUID()
    let scheduler = ManualInteractionTimerScheduler()
    let recorder = InteractionRecorder()
    let coordinator = makeCoordinator(
      scheduler: scheduler,
      recorder: recorder
    )
    coordinator.update(itemIDs: [currentID], currentFocusID: currentID)
    coordinator.pointerEntered()

    coordinator.suspend()

    XCTAssertEqual(scheduler.activeTimerCount, 0)
    coordinator.pointerEntered()
    XCTAssertEqual(recorder.pauseCount, 0)
    XCTAssertEqual(scheduler.activeDelays, [0.4])
  }

  func testClickTriggerDoesNotExpandOnHoverAndExpandsOnActivation() {
    let currentID = UUID()
    let scheduler = ManualInteractionTimerScheduler()
    let recorder = InteractionRecorder()
    let coordinator = makeCoordinator(
      scheduler: scheduler,
      recorder: recorder
    )
    coordinator.update(itemIDs: [currentID], currentFocusID: currentID)
    coordinator.setExpansionTrigger(.click)

    coordinator.pointerEntered()
    XCTAssertEqual(scheduler.activeTimerCount, 0)
    XCTAssertFalse(recorder.presentations.last?.isExpanded ?? true)

    coordinator.activateSurface()
    XCTAssertTrue(recorder.presentations.last?.isExpanded ?? false)
    XCTAssertEqual(recorder.pauseCount, 1)
  }

  func testExplicitDismissalCollapsesToCurrentAndResumesRotation() {
    let currentID = UUID()
    let secondaryID = UUID()
    let scheduler = ManualInteractionTimerScheduler()
    let recorder = InteractionRecorder()
    let coordinator = makeCoordinator(
      scheduler: scheduler,
      recorder: recorder
    )
    coordinator.update(
      itemIDs: [currentID, secondaryID],
      currentFocusID: currentID
    )
    coordinator.pointerEntered()
    scheduler.fireNext()
    coordinator.browse(.next)

    coordinator.dismissExpandedSurface()

    XCTAssertEqual(
      recorder.presentations.last,
      .init(visibleItemID: currentID, isExpanded: false)
    )
    XCTAssertEqual(recorder.resumeCount, 1)
  }

  private func makeCoordinator(
    scheduler: ManualInteractionTimerScheduler,
    recorder: InteractionRecorder
  ) -> TopSurfaceInteractionModel {
    TopSurfaceInteractionModel(
      scheduler: scheduler,
      onIntent: { intent in
        guard case .focus(let visibleItemID, let isExpanded) = intent else {
          return
        }
        recorder.presentations.append(
          .init(visibleItemID: visibleItemID, isExpanded: isExpanded)
        )
      },
      onPauseRotation: {
        recorder.pauseCount += 1
      },
      onResumeRotation: {
        recorder.resumeCount += 1
      },
      onOpenItem: { recorder.openedIDs.append($0) }
    )
  }
}

@MainActor
private final class InteractionRecorder {
  var presentations: [TopSurfacePresentationState] = []
  var openedIDs: [UUID] = []
  var pauseCount = 0
  var resumeCount = 0
}

@MainActor
private final class ManualInteractionTimerScheduler:
  AppTimerScheduling
{
  private final class Timer: AppTimerCancellation {
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
  ) -> any AppTimerCancellation {
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
