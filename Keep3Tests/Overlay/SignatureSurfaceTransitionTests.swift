import XCTest

@testable import Keep3

final class SignatureSurfaceTransitionTests: XCTestCase {
  func testStandardTransitionUsesOne760MillisecondHandoff() {
    let transition = SignatureSurfaceTransition.resolve(
      reduceMotion: false,
      reduceTransparency: false,
      increaseContrast: false,
      differentiateWithoutColor: false,
      backgroundOpacity: 0.82
    )

    XCTAssertEqual(transition.duration, 0.76, accuracy: 0.001)
    XCTAssertTrue(transition.animatesShape)
    XCTAssertTrue(transition.usesProgressiveTitleBlur)
    XCTAssertEqual(transition.outgoingTitleBlurRadius, 7)
    XCTAssertEqual(transition.backgroundOpacity, 0.82)
    XCTAssertEqual(transition.markerStyle(isCurrentFocus: true), .filledLozenge)
    XCTAssertEqual(transition.markerStyle(isCurrentFocus: false), .outlinedOrdinal)
  }

  func testReduceMotionUses120MillisecondCrossfadeWithoutSpatialMovement() {
    let transition = SignatureSurfaceTransition.resolve(
      reduceMotion: true,
      reduceTransparency: true,
      increaseContrast: true,
      differentiateWithoutColor: true
    )

    XCTAssertEqual(transition.duration, 0.12, accuracy: 0.001)
    XCTAssertFalse(transition.animatesShape)
    XCTAssertFalse(transition.usesProgressiveTitleBlur)
    XCTAssertEqual(transition.outgoingTitleBlurRadius, 0)
    XCTAssertEqual(transition.backgroundOpacity, 1)
    XCTAssertTrue(transition.usesHighContrastMarkers)
  }
}
