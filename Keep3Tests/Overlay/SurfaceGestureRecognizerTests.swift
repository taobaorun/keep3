import XCTest

@testable import Keep3

final class SurfaceGestureRecognizerTests: XCTestCase {
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

  private func event(
    x: CGFloat = 0,
    y: CGFloat = 0,
    precise: Bool = true,
    phase: TopSurfaceGesturePhase,
    momentum: SurfaceScrollMomentumPhase = .none
  ) -> SurfaceScrollEvent {
    SurfaceScrollEvent(
      deltaX: x,
      deltaY: y,
      isPrecise: precise,
      physicalPhase: phase,
      momentumPhase: momentum
    )
  }
}
