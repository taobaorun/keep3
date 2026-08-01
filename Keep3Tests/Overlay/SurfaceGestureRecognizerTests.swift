import XCTest

@testable import Keep3

final class SurfaceGestureRecognizerTests: XCTestCase {
  func testFeedbackEmitsWhenThresholdIsCrossedBeforeGestureCommit() {
    var recognizer = SurfaceGestureRecognizer()
    recognizer.updateContext(
      .init(
        component: .media,
        level: .compact,
        generation: 1,
        mediaSessionID: "session-1"
      )
    )

    XCTAssertEqual(
      recognizer.recognize(event(x: 12, phase: .began)),
      .none
    )
    XCTAssertEqual(
      recognizer.recognize(event(x: 13, phase: .changed)),
      SurfaceGestureRecognition(
        feedbackIntent: .nextTrack,
        committedIntent: nil
      )
    )
    XCTAssertEqual(
      recognizer.recognize(event(x: 30, phase: .changed)),
      .none
    )
    XCTAssertEqual(
      recognizer.recognize(event(phase: .ended)),
      SurfaceGestureRecognition(
        feedbackIntent: nil,
        committedIntent: .nextTrack
      )
    )
  }

  func testNavigationFeedbackAlsoPrecedesGestureCommit() {
    var recognizer = SurfaceGestureRecognizer()
    recognizer.updateContext(
      .init(component: .priorities, level: .compact, generation: 1)
    )

    XCTAssertEqual(
      recognizer.recognize(event(y: -25, phase: .began)),
      SurfaceGestureRecognition(
        feedbackIntent: .retreatDepth,
        committedIntent: nil
      )
    )
    XCTAssertEqual(
      recognizer.recognize(event(phase: .ended)),
      SurfaceGestureRecognition(
        feedbackIntent: nil,
        committedIntent: .retreatDepth
      )
    )
  }

  func testExpandedMediaUpEmitsOneRetreatFeedbackThenCommitsRetreat() {
    var recognizer = SurfaceGestureRecognizer()
    recognizer.updateContext(
      .init(
        component: .media,
        level: .expanded,
        generation: 1,
        mediaSessionID: "session-1"
      )
    )

    XCTAssertEqual(
      recognizer.recognize(event(y: -12, phase: .began)),
      .none
    )
    XCTAssertEqual(
      recognizer.recognize(event(y: -13, phase: .changed)),
      SurfaceGestureRecognition(
        feedbackIntent: .retreatDepth,
        committedIntent: nil
      )
    )
    XCTAssertEqual(
      recognizer.recognize(event(y: -30, phase: .changed)),
      .none
    )
    XCTAssertEqual(
      recognizer.recognize(event(phase: .ended)),
      SurfaceGestureRecognition(
        feedbackIntent: nil,
        committedIntent: .retreatDepth
      )
    )
  }

  func testExpandedVerticalIntentMatrixOnlyChangesMediaUp() {
    let scenarios:
      [(
        component: SurfaceComponentID,
        deltaY: CGFloat,
        expected: SurfaceGestureIntent
      )] = [
        (.media, 30, .nextComponent),
        (.priorities, -30, .previousComponent),
        (.priorities, 30, .nextComponent),
        (.calendar, -30, .previousComponent),
        (.calendar, 30, .nextComponent),
      ]

    for (index, scenario) in scenarios.enumerated() {
      var recognizer = SurfaceGestureRecognizer()
      recognizer.updateContext(
        .init(
          component: scenario.component,
          level: .expanded,
          generation: UInt64(index + 1)
        )
      )

      XCTAssertNil(
        recognizer.handle(
          event(y: scenario.deltaY, phase: .began)
        )
      )
      XCTAssertEqual(
        recognizer.handle(event(phase: .ended)),
        scenario.expected,
        "Unexpected vertical intent for \(scenario.component), delta \(scenario.deltaY)"
      )
    }
  }

  func testVerticalIntentAdvancesDepthThenSelectsFromExpanded() {
    var recognizer = SurfaceGestureRecognizer()
    recognizer.updateContext(
      .init(component: .priorities, level: .hardware, generation: 1)
    )

    XCTAssertNil(recognizer.handle(event(y: 28, phase: .began)))
    XCTAssertEqual(
      recognizer.handle(event(phase: .ended)),
      .advanceDepth
    )
    XCTAssertNil(recognizer.handle(event(phase: .ended)))

    recognizer.updateContext(
      .init(component: .priorities, level: .expanded, generation: 2)
    )
    XCTAssertNil(recognizer.handle(event(y: 30, phase: .began)))
    XCTAssertEqual(
      recognizer.handle(event(phase: .ended)),
      .nextComponent
    )
  }

  func testKeyboardStyleVerticalGesturesCommitExactlyOnce() {
    let scenarios: [(deltaY: CGFloat, expected: SurfaceGestureIntent)] = [
      (-30, .retreatDepth),
      (30, .advanceDepth),
    ]

    for (index, scenario) in scenarios.enumerated() {
      var recognizer = SurfaceGestureRecognizer()
      recognizer.updateContext(
        .init(
          component: .priorities,
          level: .compact,
          generation: UInt64(index + 1)
        )
      )

      XCTAssertNil(
        recognizer.handle(
          event(y: scenario.deltaY, phase: .began)
        )
      )
      XCTAssertEqual(
        recognizer.handle(event(phase: .ended)),
        scenario.expected
      )
      XCTAssertNil(recognizer.handle(event(phase: .ended)))
    }
  }

  func testHorizontalIntentRoutesOnlyForSelectedMedia() {
    var recognizer = SurfaceGestureRecognizer()
    recognizer.updateContext(
      .init(component: .priorities, level: .compact, generation: 1)
    )

    XCTAssertNil(recognizer.handle(event(x: -30, phase: .began)))
    XCTAssertNil(recognizer.handle(event(phase: .ended)))

    recognizer.updateContext(
      .init(
        component: .media,
        level: .compact,
        generation: 2,
        mediaSessionID: "session-1"
      )
    )
    XCTAssertNil(recognizer.handle(event(x: -30, phase: .began)))
    XCTAssertEqual(
      recognizer.handle(event(phase: .ended)),
      .previousTrack
    )
    XCTAssertNil(recognizer.handle(event(x: 30, phase: .began)))
    XCTAssertEqual(
      recognizer.handle(event(phase: .ended)),
      .nextTrack
    )
  }

  func testExpandedPrioritiesHorizontalIntentBrowsesVisibleItems() {
    var recognizer = SurfaceGestureRecognizer()
    recognizer.updateContext(
      .init(component: .priorities, level: .expanded, generation: 1)
    )

    XCTAssertNil(recognizer.handle(event(x: -30, phase: .began)))
    XCTAssertEqual(
      recognizer.handle(event(phase: .ended)),
      .previousItem
    )
    XCTAssertNil(recognizer.handle(event(x: 30, phase: .began)))
    XCTAssertEqual(
      recognizer.handle(event(phase: .ended)),
      .nextItem
    )
  }

  func testDominantAxisLocksAndContextChangeCancelsGesture() {
    var recognizer = SurfaceGestureRecognizer()
    recognizer.updateContext(
      .init(
        component: .media,
        level: .compact,
        generation: 1,
        mediaSessionID: "session-1"
      )
    )

    XCTAssertNil(recognizer.handle(event(x: 28, y: 12, phase: .began)))
    XCTAssertNil(recognizer.handle(event(x: 0, y: 40, phase: .changed)))
    XCTAssertEqual(
      recognizer.handle(event(phase: .ended)),
      .nextTrack
    )

    XCTAssertNil(recognizer.handle(event(y: 28, phase: .began)))
    recognizer.updateContext(
      .init(component: .media, level: .expanded, generation: 2)
    )
    XCTAssertNil(recognizer.handle(event(phase: .ended)))
  }

  func testMomentumNonPreciseAndCancellationNeverEmit() {
    var recognizer = SurfaceGestureRecognizer()
    recognizer.updateContext(
      .init(component: .media, level: .compact, generation: 1)
    )

    XCTAssertNil(
      recognizer.handle(
        event(x: 40, phase: .began, momentum: .changed)
      )
    )
    XCTAssertNil(
      recognizer.handle(event(x: 40, precise: false, phase: .began))
    )
    XCTAssertNil(recognizer.handle(event(x: 40, phase: .began)))
    XCTAssertNil(recognizer.handle(event(phase: .cancelled)))
    XCTAssertNil(recognizer.handle(event(phase: .ended)))
  }

  func testGestureRequiresBeginInsideCapturedFrameAndCancelsOnResizeOrExit() {
    var recognizer = SurfaceGestureRecognizer()
    let frame = CGRect(x: 100, y: 100, width: 200, height: 44)
    recognizer.updateContext(
      .init(
        component: .media,
        level: .compact,
        generation: 1,
        mediaSessionID: "session-1",
        interactionFrameInScreen: frame
      )
    )

    XCTAssertNil(
      recognizer.handle(
        event(x: 30, phase: .began, location: CGPoint(x: 50, y: 120))
      )
    )
    XCTAssertNil(
      recognizer.handle(
        event(phase: .ended, location: CGPoint(x: 150, y: 120))
      )
    )

    XCTAssertNil(
      recognizer.handle(
        event(x: 30, phase: .began, location: CGPoint(x: 150, y: 120))
      )
    )
    recognizer.updateContext(
      .init(
        component: .media,
        level: .compact,
        generation: 1,
        mediaSessionID: "session-1",
        interactionFrameInScreen:
          CGRect(x: 100, y: 100, width: 240, height: 80)
      )
    )
    XCTAssertNil(
      recognizer.handle(
        event(phase: .ended, location: CGPoint(x: 150, y: 120))
      )
    )

    XCTAssertNil(
      recognizer.handle(
        event(x: 30, phase: .began, location: CGPoint(x: 150, y: 120))
      )
    )
    XCTAssertNil(
      recognizer.handle(
        event(phase: .changed, location: CGPoint(x: 400, y: 120))
      )
    )
    XCTAssertNil(recognizer.handle(event(phase: .ended)))
  }

  private func event(
    x: CGFloat = 0,
    y: CGFloat = 0,
    precise: Bool = true,
    phase: TopSurfaceGesturePhase,
    momentum: SurfaceScrollMomentumPhase = .none,
    location: CGPoint? = nil
  ) -> SurfaceScrollEvent {
    SurfaceScrollEvent(
      deltaX: x,
      deltaY: y,
      isPrecise: precise,
      physicalPhase: phase,
      momentumPhase: momentum,
      locationInScreen: location
    )
  }
}
