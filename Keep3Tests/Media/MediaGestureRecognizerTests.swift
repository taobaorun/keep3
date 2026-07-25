import XCTest

@testable import Keep3

final class MediaGestureRecognizerTests: XCTestCase {
  func testUpwardPreciseGestureDispatchesNextOnlyOnPhysicalEnd() {
    var recognizer = MediaGestureRecognizer()
    recognizer.updateSession("session-1")

    XCTAssertNil(recognizer.handle(event(y: 10, phase: .began)))
    XCTAssertNil(recognizer.handle(event(y: 18, phase: .changed)))
    XCTAssertEqual(
      recognizer.handle(event(y: 0, phase: .ended)),
      .next
    )
    XCTAssertNil(
      recognizer.handle(
        event(y: 40, phase: .changed, momentum: .changed)
      )
    )
  }

  func testHorizontalCancelledLegacyAndMomentumEventsNeverSwitchTracks() {
    var recognizer = MediaGestureRecognizer()
    recognizer.updateSession("session-1")

    XCTAssertNil(recognizer.handle(event(x: 40, y: 20, phase: .began)))
    XCTAssertNil(recognizer.handle(event(phase: .ended)))
    XCTAssertNil(
      recognizer.handle(
        event(y: -40, precise: false, phase: .none)
      )
    )
    XCTAssertNil(
      recognizer.handle(
        event(y: -40, phase: .changed, momentum: .changed)
      )
    )
    XCTAssertNil(recognizer.handle(event(y: -40, phase: .cancelled)))
  }

  func testSessionChangeMidGestureCancelsArmedDirection() {
    var recognizer = MediaGestureRecognizer()
    recognizer.updateSession("session-1")
    XCTAssertNil(recognizer.handle(event(y: -30, phase: .began)))

    recognizer.updateSession("session-2")

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
