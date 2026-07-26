import XCTest

@testable import Keep3

final class SignatureSurfaceTransitionTests: XCTestCase {
  func testNormalMotionUsesTriggerSpecificBoundedDurations() {
    let expectedDurations: [(SurfaceTransitionIntent, TimeInterval)] = [
      (.expansion, 0.27),
      (.collapse, 0.20),
      (.manualComponent(.next), 0.21),
      (.automaticComponent, 0.21),
      (.content, 0.15),
    ]

    for (intent, expectedDuration) in expectedDurations {
      let transition = resolve(intent: intent)

      XCTAssertEqual(
        transition.duration,
        expectedDuration,
        accuracy: 0.001,
        "\(intent)"
      )
    }
  }

  func testManualComponentDirectionsUseMirroredContentOffsets() {
    let previous = resolve(intent: .manualComponent(.previous))
    let next = resolve(intent: .manualComponent(.next))

    XCTAssertEqual(previous.directionalContentOffset, -next.directionalContentOffset)
    XCTAssertNotEqual(previous.directionalContentOffset, 0)
    XCTAssertEqual(previous.direction, .previous)
    XCTAssertEqual(next.direction, .next)
  }

  func testAutomaticAndContentChangesDoNotImplyManualDirection() {
    let automatic = resolve(intent: .automaticComponent)
    let content = resolve(intent: .content)

    XCTAssertEqual(automatic.direction, .neutral)
    XCTAssertEqual(automatic.directionalContentOffset, 0)
    XCTAssertEqual(content.direction, .neutral)
    XCTAssertEqual(content.directionalContentOffset, 0)
    XCTAssertFalse(content.animatesShape)
  }

  func testReduceMotionUses120MillisecondNonSpatialCrossfadeForEveryTrigger() {
    let intents: [SurfaceTransitionIntent] = [
      .expansion,
      .collapse,
      .manualComponent(.previous),
      .automaticComponent,
      .content,
    ]

    for intent in intents {
      let transition = SignatureSurfaceTransition.resolve(
        intent: intent,
        reduceMotion: true,
        reduceTransparency: true,
        increaseContrast: true,
        differentiateWithoutColor: true
      )

      XCTAssertEqual(transition.duration, 0.12, accuracy: 0.001)
      XCTAssertEqual(transition.motionPolicy, .crossfade)
      XCTAssertFalse(transition.animatesShape)
      XCTAssertFalse(transition.usesProgressiveTitleBlur)
      XCTAssertEqual(transition.outgoingTitleBlurRadius, 0)
      XCTAssertEqual(transition.directionalContentOffset, 0)
      XCTAssertEqual(transition.backgroundOpacity, 1)
      XCTAssertTrue(transition.usesHighContrastMarkers)
    }
  }

  func testAppearanceAndMarkerPolicyRemainCentralized() {
    let transition = SignatureSurfaceTransition.resolve(
      intent: .content,
      reduceMotion: false,
      reduceTransparency: false,
      increaseContrast: false,
      differentiateWithoutColor: false,
      backgroundOpacity: 0.82
    )

    XCTAssertEqual(transition.backgroundOpacity, 0.82)
    XCTAssertEqual(transition.markerStyle(isCurrentFocus: true), .filledLozenge)
    XCTAssertEqual(transition.markerStyle(isCurrentFocus: false), .outlinedOrdinal)
  }

  private func resolve(
    intent: SurfaceTransitionIntent
  ) -> SignatureSurfaceTransition {
    SignatureSurfaceTransition.resolve(
      intent: intent,
      reduceMotion: false,
      reduceTransparency: false,
      increaseContrast: false,
      differentiateWithoutColor: false
    )
  }
}

@MainActor
final class SurfaceTransitionCoordinatorTests: XCTestCase {
  func testLatestGenerationRejectsStaleCompletion() {
    let focus = focusPresentation(revision: 1)
    let media = mediaPresentation(revision: 1)
    let coordinator = SurfaceTransitionCoordinator(initialTarget: focus)

    let first = coordinator.transition(
      to: media,
      intent: .automaticComponent,
      reduceMotion: false
    )
    let second = coordinator.transition(
      to: focusPresentation(revision: 2),
      intent: .automaticComponent,
      reduceMotion: false
    )

    XCTAssertFalse(coordinator.complete(generation: first.generation))
    XCTAssertTrue(coordinator.complete(generation: second.generation))
    XCTAssertEqual(coordinator.context.phase, .settled)
    XCTAssertEqual(coordinator.context.target, focusPresentation(revision: 2))
  }

  func testSameComponentRevisionsCoalesceIntoNewestTarget() {
    let initial = focusPresentation(revision: 1)
    let coordinator = SurfaceTransitionCoordinator(initialTarget: initial)

    let first = coordinator.transition(
      to: focusPresentation(revision: 2),
      intent: .content,
      reduceMotion: false
    )
    let second = coordinator.transition(
      to: focusPresentation(revision: 3),
      intent: .content,
      reduceMotion: false
    )

    XCTAssertEqual(second.source, initial)
    XCTAssertEqual(second.target, focusPresentation(revision: 3))
    XCTAssertEqual(second.trigger, .content)
    XCTAssertEqual(second.phase, .transitioning)
    XCTAssertGreaterThan(second.generation, first.generation)
    XCTAssertFalse(coordinator.complete(generation: first.generation))
  }

  func testContentRefreshDoesNotRestartComponentTransition() {
    let focus = focusPresentation(revision: 1)
    let coordinator = SurfaceTransitionCoordinator(initialTarget: focus)
    let initialMedia = mediaPresentation(revision: 1)

    let componentTransition = coordinator.transition(
      to: initialMedia,
      intent: .manualComponent(.next),
      reduceMotion: false
    )
    let coalesced = coordinator.transition(
      to: mediaPresentation(revision: 2),
      intent: .content,
      reduceMotion: false
    )

    XCTAssertEqual(coalesced.source, focus)
    XCTAssertEqual(coalesced.target, mediaPresentation(revision: 2))
    XCTAssertEqual(coalesced.trigger, .manualComponent)
    XCTAssertEqual(coalesced.direction, .next)
    XCTAssertEqual(coalesced.motion, componentTransition.motion)
  }

  func testLifecycleHideCancelsAndRestorationSettlesCanonicalTarget() {
    let initial = focusPresentation(revision: 1)
    let coordinator = SurfaceTransitionCoordinator(initialTarget: initial)
    let inFlight = coordinator.transition(
      to: mediaPresentation(revision: 1),
      intent: .automaticComponent,
      reduceMotion: false
    )

    let hidden = coordinator.cancelForLifecycle()

    XCTAssertEqual(hidden.phase, .hidden)
    XCTAssertEqual(hidden.target, .hidden)
    XCTAssertFalse(coordinator.complete(generation: inFlight.generation))

    let restoredTarget = focusPresentation(revision: 2)
    let restored = coordinator.reconcile(
      to: restoredTarget,
      reduceMotion: false
    )

    XCTAssertEqual(restored.source, restoredTarget)
    XCTAssertEqual(restored.target, restoredTarget)
    XCTAssertEqual(restored.trigger, .lifecycleRestore)
    XCTAssertEqual(restored.phase, .settled)
  }

  func testReducedMotionPolicyIsCarriedByTransitionContext() {
    let coordinator = SurfaceTransitionCoordinator(
      initialTarget: focusPresentation(revision: 1)
    )

    let context = coordinator.transition(
      to: mediaPresentation(revision: 1),
      intent: .manualComponent(.previous),
      reduceMotion: true
    )

    XCTAssertEqual(context.motion.motionPolicy, .crossfade)
    XCTAssertLessThanOrEqual(context.motion.duration, 0.15)
    XCTAssertEqual(context.motion.directionalContentOffset, 0)
  }

  private func focusPresentation(revision: UInt64) -> TopSurfacePresentation {
    .focus(
      FocusSurfacePayload(
        visibleItemID: UUID(uuidString: "79AB732D-3D88-42AD-80D0-44BB03E4AFCA"),
        isExpanded: false,
        revision: revision,
        expansionReason: .none
      )
    )
  }

  private func mediaPresentation(revision: UInt64) -> TopSurfacePresentation {
    .media(
      MediaSurfacePayload(
        sessionID: "session-1",
        contentRevision: revision,
        isExpanded: false,
        areControlsEnabled: true
      )
    )
  }
}
