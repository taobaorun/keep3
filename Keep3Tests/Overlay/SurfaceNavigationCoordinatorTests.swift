import XCTest

@testable import Keep3

@MainActor
final class SurfaceNavigationCoordinatorTests: XCTestCase {
  func testNewMediaSessionAutoSelectsOnceAndManualSelectionWinsWithinSession() {
    var states: [SurfaceNavigationState] = []
    let coordinator = SurfaceNavigationCoordinator(
      onStateChange: { states.append($0) }
    )

    coordinator.setAvailability(true, for: .priorities)
    coordinator.setAvailability(true, for: .media)
    coordinator.beginMediaSession("session-1")

    XCTAssertEqual(states.last?.selectedComponent, .media)
    XCTAssertEqual(states.last?.selectionSource, .automaticMedia)

    coordinator.select(.priorities)
    coordinator.refreshMediaSession("session-1")

    XCTAssertEqual(states.last?.selectedComponent, .priorities)
    XCTAssertEqual(states.last?.selectionSource, .manual)

    coordinator.beginMediaSession("session-2")

    XCTAssertEqual(states.last?.selectedComponent, .media)
    XCTAssertEqual(states.last?.selectionSource, .automaticMedia)
  }

  func testNavigationWrapsAndSkipsUnavailableComponents() {
    let coordinator = SurfaceNavigationCoordinator()
    coordinator.setAvailability(true, for: .priorities)
    coordinator.setAvailability(true, for: .calendar)

    coordinator.navigate(.next)

    XCTAssertEqual(coordinator.state.selectedComponent, .calendar)

    coordinator.navigate(.next)

    XCTAssertEqual(coordinator.state.selectedComponent, .priorities)
  }

  func testManualNavigationPublishesMirroredTransitionDirections() {
    let coordinator = SurfaceNavigationCoordinator()
    coordinator.setAvailability(true, for: .priorities)
    coordinator.setAvailability(true, for: .media)
    coordinator.setAvailability(true, for: .calendar)

    coordinator.navigate(.next)

    XCTAssertEqual(coordinator.state.transitionIntent, .manualComponent(.next))

    coordinator.navigate(.previous)

    XCTAssertEqual(
      coordinator.state.transitionIntent,
      .manualComponent(.previous)
    )
  }

  func testDepthChangesPublishExpansionAndCollapseIntents() {
    let coordinator = SurfaceNavigationCoordinator()

    coordinator.setLevel(.compact)
    XCTAssertEqual(coordinator.state.transitionIntent, .expansion)

    coordinator.setLevel(.hardware)
    XCTAssertEqual(coordinator.state.transitionIntent, .collapse)
  }

  func testAutomaticAndLifecycleChangesPublishNeutralIntents() {
    let coordinator = SurfaceNavigationCoordinator()
    coordinator.setAvailability(true, for: .priorities)

    coordinator.beginMediaSession("session-1")
    XCTAssertEqual(coordinator.state.transitionIntent, .automaticComponent)

    coordinator.setSurfaceAvailable(false)
    XCTAssertEqual(coordinator.state.transitionIntent, .lifecycleHide)

    coordinator.setSurfaceAvailable(true)
    coordinator.reconcileAfterAvailability()

    XCTAssertEqual(coordinator.state.transitionIntent, .lifecycleRestore)
  }

  func testSelectedUnavailableFallsForwardThenUltimatelyReturnsPriorities() {
    let coordinator = SurfaceNavigationCoordinator()
    coordinator.setAvailability(true, for: .priorities)
    coordinator.setAvailability(true, for: .media)
    coordinator.setAvailability(true, for: .calendar)
    coordinator.select(.media)

    coordinator.setAvailability(false, for: .media)

    XCTAssertEqual(coordinator.state.selectedComponent, .calendar)
    XCTAssertEqual(coordinator.state.selectionSource, .fallback)

    coordinator.setAvailability(false, for: .calendar)

    XCTAssertEqual(coordinator.state.selectedComponent, .priorities)
  }

  func testMediaExitReturnsPrioritiesAndReleasesManualPin() {
    let coordinator = SurfaceNavigationCoordinator()
    coordinator.setAvailability(true, for: .priorities)
    coordinator.setAvailability(true, for: .media)
    coordinator.setAvailability(true, for: .calendar)
    coordinator.beginMediaSession("session-1")
    coordinator.select(.calendar)

    coordinator.endMediaSession("session-1")

    XCTAssertEqual(coordinator.state.selectedComponent, .priorities)
    XCTAssertEqual(coordinator.state.selectionSource, .mediaExit)
    XCTAssertFalse(coordinator.isAvailable(.media))
  }

  func testSameMediaSessionRecoveryPreservesManualPrioritiesSelection() {
    let coordinator = SurfaceNavigationCoordinator()
    coordinator.setAvailability(true, for: .priorities)
    coordinator.beginMediaSession("session-1")
    coordinator.select(.priorities)

    coordinator.endMediaSession("session-1")
    coordinator.beginMediaSession("session-1")

    XCTAssertEqual(coordinator.state.selectedComponent, .priorities)
    XCTAssertEqual(coordinator.state.selectionSource, .manual)
    XCTAssertTrue(coordinator.isAvailable(.media))
  }

  func testExpandedMediaExitReturnsPrioritiesAtCompactLevel() {
    let coordinator = SurfaceNavigationCoordinator()
    coordinator.setAvailability(true, for: .priorities)
    coordinator.beginMediaSession("session-1")
    coordinator.setLevel(.expanded)

    coordinator.endMediaSession("session-1")

    XCTAssertEqual(coordinator.state.selectedComponent, .priorities)
    XCTAssertEqual(coordinator.state.level, .compact)
  }

  func testDisplayRecoveryRequiresFreshReconciliation() {
    var states: [SurfaceNavigationState] = []
    let coordinator = SurfaceNavigationCoordinator(
      onStateChange: { states.append($0) }
    )

    coordinator.setSurfaceAvailable(false)
    coordinator.setSurfaceAvailable(true)

    XCTAssertFalse(states.last?.isPresented ?? true)

    coordinator.reconcileAfterAvailability()

    XCTAssertTrue(states.last?.isPresented ?? false)
    XCTAssertEqual(states.last?.selectedComponent, .priorities)
  }

  func testHoverPreviewDoesNotPinCompactAndDirectDepthDoes() {
    let coordinator = SurfaceNavigationCoordinator()

    coordinator.setHovering(true)

    XCTAssertEqual(coordinator.state.level, .hardware)
    XCTAssertEqual(coordinator.state.effectiveLevel, .compact)

    coordinator.setHovering(false)
    XCTAssertEqual(coordinator.state.effectiveLevel, .hardware)

    coordinator.apply(.advanceDepth)
    coordinator.setHovering(false)

    XCTAssertEqual(coordinator.state.level, .compact)
    XCTAssertEqual(coordinator.state.effectiveLevel, .compact)
  }

  func testHoverStateTracksPointerAtCompactLevel() {
    let coordinator = SurfaceNavigationCoordinator()
    coordinator.setLevel(.compact)

    coordinator.setHovering(true)
    XCTAssertTrue(coordinator.state.isHovering)

    coordinator.setHovering(false)
    XCTAssertFalse(coordinator.state.isHovering)
  }

  func testDepthAndExpandedComponentIntentsFollowThreeLevelContract() {
    let coordinator = SurfaceNavigationCoordinator()
    coordinator.setAvailability(true, for: .media)

    coordinator.apply(.advanceDepth)
    coordinator.apply(.advanceDepth)

    XCTAssertEqual(coordinator.state.level, .expanded)

    coordinator.apply(.nextComponent)

    XCTAssertEqual(coordinator.state.selectedComponent, .media)
    XCTAssertEqual(coordinator.state.level, .compact)

    coordinator.apply(.retreatDepth)

    XCTAssertEqual(coordinator.state.level, .hardware)
  }

  func testExpandedComponentSelectionPublishesOneAtomicCompactState() {
    var states: [SurfaceNavigationState] = []
    let coordinator = SurfaceNavigationCoordinator(
      onStateChange: { states.append($0) }
    )
    coordinator.setAvailability(true, for: .priorities)
    coordinator.setAvailability(true, for: .media)
    coordinator.apply(.advanceDepth)
    coordinator.apply(.advanceDepth)
    let publicationCount = states.count

    coordinator.apply(.nextComponent)

    XCTAssertEqual(states.count, publicationCount + 1)
    XCTAssertEqual(states.last?.selectedComponent, .media)
    XCTAssertEqual(states.last?.level, .compact)
  }

  func testExpandedMediaRetreatPublishesOneSameComponentCompactState() {
    var states: [SurfaceNavigationState] = []
    let coordinator = SurfaceNavigationCoordinator(
      onStateChange: { states.append($0) }
    )
    coordinator.setAvailability(true, for: .priorities)
    coordinator.beginMediaSession("session-1")
    coordinator.setLevel(.expanded)
    let originalSelectionSource = coordinator.state.selectionSource
    let publicationCount = states.count

    coordinator.apply(.retreatDepth)

    XCTAssertEqual(states.count, publicationCount + 1)
    XCTAssertEqual(states.last?.selectedComponent, .media)
    XCTAssertEqual(states.last?.selectionSource, originalSelectionSource)
    XCTAssertEqual(states.last?.level, .compact)
    XCTAssertTrue(coordinator.isAvailable(.media))
  }

  func testPointerExitReturnsExpandedMediaToCompact() {
    let coordinator = SurfaceNavigationCoordinator()
    coordinator.beginMediaSession("session-1")
    coordinator.setLevel(.expanded)

    coordinator.setHovering(false)

    XCTAssertEqual(coordinator.state.selectedComponent, .media)
    XCTAssertEqual(coordinator.state.level, .compact)
  }

  func testPointerExitDoesNotCollapseAnotherExpandedComponent() {
    let coordinator = SurfaceNavigationCoordinator()
    coordinator.setAvailability(true, for: .priorities)
    coordinator.select(.priorities)
    coordinator.setLevel(.expanded)

    coordinator.setHovering(false)

    XCTAssertEqual(coordinator.state.selectedComponent, .priorities)
    XCTAssertEqual(coordinator.state.level, .expanded)
  }

  func testExpandedMediaNextComponentBehaviorRemainsUnchanged() {
    let coordinator = SurfaceNavigationCoordinator()
    coordinator.setAvailability(true, for: .priorities)
    coordinator.beginMediaSession("session-1")
    coordinator.setLevel(.expanded)

    coordinator.apply(.nextComponent)

    XCTAssertEqual(coordinator.state.selectedComponent, .priorities)
    XCTAssertEqual(coordinator.state.selectionSource, .manual)
    XCTAssertEqual(coordinator.state.level, .compact)
  }

  func testCalendarBecomesFallbackWhenPrioritiesAreEmpty() {
    let coordinator = SurfaceNavigationCoordinator()
    coordinator.setAvailability(true, for: .priorities)
    coordinator.setAvailability(true, for: .calendar)

    coordinator.setAvailability(false, for: .priorities)

    XCTAssertEqual(coordinator.state.selectedComponent, .calendar)
    XCTAssertEqual(coordinator.state.selectionSource, .fallback)
  }

  func testMediaExitFallsBackToCalendarWhenPrioritiesAreEmpty() {
    let coordinator = SurfaceNavigationCoordinator()
    coordinator.setAvailability(true, for: .calendar)
    coordinator.beginMediaSession("session-1")

    coordinator.endMediaSession("session-1")

    XCTAssertEqual(coordinator.state.selectedComponent, .calendar)
    XCTAssertEqual(coordinator.state.selectionSource, .mediaExit)
  }

  func testAutomaticMediaSelectionWaitsForAllPinsAndUsesLatestOutcome() {
    var states: [SurfaceNavigationState] = []
    let coordinator = SurfaceNavigationCoordinator(
      onStateChange: { states.append($0) }
    )
    coordinator.setAvailability(true, for: .priorities)
    let publicationCount = states.count

    coordinator.setAutomaticTransitionDeferred(
      true,
      reason: .pointerDown
    )
    coordinator.setAutomaticTransitionDeferred(
      true,
      reason: .keyboardNavigation
    )
    coordinator.beginMediaSession("session-1")
    coordinator.endMediaSession("session-1")
    coordinator.beginMediaSession("session-2")

    XCTAssertEqual(coordinator.state.selectedComponent, .priorities)
    XCTAssertEqual(states.count, publicationCount)

    coordinator.setAutomaticTransitionDeferred(
      false,
      reason: .pointerDown
    )
    XCTAssertEqual(coordinator.state.selectedComponent, .priorities)

    coordinator.setAutomaticTransitionDeferred(
      false,
      reason: .keyboardNavigation
    )
    XCTAssertEqual(coordinator.state.selectedComponent, .media)
    XCTAssertEqual(coordinator.state.selectionSource, .automaticMedia)
    XCTAssertEqual(states.count, publicationCount + 1)
  }

  func testManualSelectionCancelsDeferredAutomaticTakeover() {
    let coordinator = SurfaceNavigationCoordinator()
    coordinator.setAvailability(true, for: .priorities)
    coordinator.setAutomaticTransitionDeferred(
      true,
      reason: .componentCommand
    )
    coordinator.beginMediaSession("session-1")

    coordinator.select(.priorities)
    coordinator.setAutomaticTransitionDeferred(
      false,
      reason: .componentCommand
    )

    XCTAssertEqual(coordinator.state.selectedComponent, .priorities)
    XCTAssertEqual(coordinator.state.selectionSource, .manual)
  }

  func testDeferredMediaExitWithoutAnyAvailableComponentSettlesOnPriorities() {
    let coordinator = SurfaceNavigationCoordinator()
    coordinator.beginMediaSession("session-1")
    coordinator.setAutomaticTransitionDeferred(
      true,
      reason: .voiceOver
    )

    coordinator.endMediaSession("session-1")
    coordinator.setAutomaticTransitionDeferred(
      false,
      reason: .voiceOver
    )

    XCTAssertEqual(coordinator.state.selectedComponent, .priorities)
    XCTAssertEqual(coordinator.state.selectionSource, .mediaExit)
    XCTAssertEqual(coordinator.state.level, .compact)
  }

  func testRecoveredSelectionCancelsStaleDeferredFallback() {
    let coordinator = SurfaceNavigationCoordinator()
    coordinator.setAvailability(true, for: .priorities)
    coordinator.setAvailability(true, for: .calendar)
    coordinator.select(.calendar)
    coordinator.setAutomaticTransitionDeferred(
      true,
      reason: .pointerDown
    )

    coordinator.setAvailability(false, for: .calendar)
    coordinator.setAvailability(true, for: .calendar)
    coordinator.setAutomaticTransitionDeferred(
      false,
      reason: .pointerDown
    )

    XCTAssertEqual(coordinator.state.selectedComponent, .calendar)
    XCTAssertEqual(coordinator.state.selectionSource, .manual)
  }

  func testDeferredMediaExitRecomputesLatestPreferredFallback() {
    let coordinator = SurfaceNavigationCoordinator()
    coordinator.setAvailability(true, for: .calendar)
    coordinator.beginMediaSession("session-1")
    coordinator.setAutomaticTransitionDeferred(
      true,
      reason: .keyboardNavigation
    )

    coordinator.endMediaSession("session-1")
    coordinator.setAvailability(true, for: .priorities)
    coordinator.setAutomaticTransitionDeferred(
      false,
      reason: .keyboardNavigation
    )

    XCTAssertEqual(coordinator.state.selectedComponent, .priorities)
    XCTAssertEqual(coordinator.state.selectionSource, .mediaExit)
  }
}
