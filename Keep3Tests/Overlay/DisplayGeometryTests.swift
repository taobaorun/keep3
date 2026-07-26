import CoreGraphics
import XCTest

@testable import Keep3

final class DisplayGeometryTests: XCTestCase {
  func testValidAuxiliaryAreasClassifyNotchedDisplay() {
    let descriptor = DisplayDescriptor(
      frame: CGRect(x: 0, y: 0, width: 1_512, height: 982),
      visibleFrame: CGRect(x: 0, y: 0, width: 1_512, height: 944),
      safeAreaInsets: DisplayInsets(top: 32, left: 0, bottom: 0, right: 0),
      auxiliaryTopLeftArea: CGRect(x: 0, y: 950, width: 672, height: 32),
      auxiliaryTopRightArea: CGRect(x: 840, y: 950, width: 672, height: 32)
    )

    let geometry = DisplayGeometry(descriptor: descriptor)

    XCTAssertEqual(
      geometry.placement,
      .notched(obstructionFrame: CGRect(x: 672, y: 950, width: 168, height: 32))
    )
  }

  func testNotchedSurfaceStartsAtScreenTopAndMatchesCameraHousingHeight() {
    let descriptor = DisplayDescriptor(
      frame: CGRect(x: 0, y: 0, width: 1_728, height: 1_117),
      visibleFrame: CGRect(x: 0, y: 0, width: 1_728, height: 1_079),
      safeAreaInsets: DisplayInsets(top: 32, left: 0, bottom: 0, right: 0),
      auxiliaryTopLeftArea: CGRect(x: 0, y: 1_085, width: 771, height: 32),
      auxiliaryTopRightArea: CGRect(x: 956, y: 1_085, width: 772, height: 32)
    )

    let geometry = DisplayGeometry(descriptor: descriptor)

    XCTAssertEqual(geometry.compactFrame.maxY, 1_117, accuracy: 0.001)
    XCTAssertEqual(geometry.compactFrame.height, 32, accuracy: 0.001)
    XCTAssertEqual(geometry.expandedFrame.maxY, 1_117, accuracy: 0.001)
  }

  func testMissingAuxiliaryAreaFallsBackToFloatingPlacement() {
    let descriptor = DisplayDescriptor(
      frame: CGRect(x: 0, y: 0, width: 1_512, height: 982),
      visibleFrame: CGRect(x: 0, y: 0, width: 1_512, height: 944),
      safeAreaInsets: DisplayInsets(top: 32, left: 0, bottom: 0, right: 0),
      auxiliaryTopLeftArea: CGRect(x: 0, y: 950, width: 672, height: 32),
      auxiliaryTopRightArea: nil
    )

    XCTAssertEqual(DisplayGeometry(descriptor: descriptor).placement, .floating)
  }

  func testNotchedLayoutRightSizesPanelForEverySurfaceLevel() {
    let descriptor = DisplayDescriptor(
      frame: CGRect(x: 0, y: 0, width: 1_728, height: 1_117),
      visibleFrame: CGRect(x: 0, y: 0, width: 1_728, height: 1_079),
      safeAreaInsets: DisplayInsets(top: 32, left: 0, bottom: 0, right: 0),
      auxiliaryTopLeftArea: CGRect(x: 0, y: 1_085, width: 771, height: 32),
      auxiliaryTopRightArea: CGRect(x: 956, y: 1_085, width: 772, height: 32)
    )
    let geometry = DisplayGeometry(descriptor: descriptor)

    let hardware = geometry.layout(level: .hardware)
    let compact = geometry.layout(level: .compact)
    let expanded = geometry.layout(level: .expanded)

    XCTAssertEqual(
      hardware.panelFrame,
      CGRect(x: 771, y: 1_085, width: 185, height: 32)
    )
    XCTAssertEqual(compact.panelFrame.maxY, descriptor.frame.maxY, accuracy: 0.001)
    XCTAssertEqual(compact.panelFrame.height, 32, accuracy: 0.001)
    XCTAssertNotEqual(compact.panelFrame, expanded.panelFrame)
    XCTAssertEqual(compact.surfaceFrameInPanel.height, 32, accuracy: 0.001)
    XCTAssertGreaterThanOrEqual(
      compact.surfaceFrameInPanel.width,
      185 + (2 * 96)
    )
    XCTAssertEqual(
      compact.surfaceFrameInPanel,
      CGRect(origin: .zero, size: compact.panelFrame.size)
    )
    XCTAssertEqual(
      expanded.surfaceFrameInPanel,
      CGRect(origin: .zero, size: expanded.panelFrame.size)
    )
    XCTAssertEqual(compact.obstructionSize, CGSize(width: 185, height: 32))
  }

  func testFloatingLayoutKeepsPanelAndSurfaceFramesIdentical() {
    let descriptor = DisplayDescriptor(
      frame: CGRect(x: 1_512, y: 0, width: 1_920, height: 1_080),
      visibleFrame: CGRect(x: 1_512, y: 0, width: 1_920, height: 1_055),
      safeAreaInsets: .zero,
      auxiliaryTopLeftArea: nil,
      auxiliaryTopRightArea: nil
    )
    let geometry = DisplayGeometry(descriptor: descriptor)

    for isExpanded in [false, true] {
      let layout = geometry.layout(isExpanded: isExpanded)
      XCTAssertEqual(
        layout.surfaceFrameInPanel,
        CGRect(origin: .zero, size: layout.panelFrame.size)
      )
      XCTAssertNil(layout.obstructionSize)
    }
  }

  func testContradictorySafeAreaDataFallsBackToFloatingPlacement() {
    let descriptors = [
      DisplayDescriptor(
        frame: CGRect(x: 0, y: 0, width: 1_512, height: 982),
        visibleFrame: CGRect(x: 0, y: 0, width: 1_512, height: 944),
        safeAreaInsets: .zero,
        auxiliaryTopLeftArea: CGRect(x: 0, y: 950, width: 672, height: 32),
        auxiliaryTopRightArea: CGRect(x: 840, y: 950, width: 672, height: 32)
      ),
      DisplayDescriptor(
        frame: CGRect(x: 0, y: 0, width: 1_512, height: 982),
        visibleFrame: CGRect(x: 0, y: 0, width: 1_512, height: 944),
        safeAreaInsets: DisplayInsets(top: 32, left: 0, bottom: 0, right: 0),
        auxiliaryTopLeftArea: CGRect(x: 0, y: 930, width: 672, height: 32),
        auxiliaryTopRightArea: CGRect(x: 840, y: 950, width: 672, height: 32)
      ),
    ]

    for descriptor in descriptors {
      XCTAssertEqual(DisplayGeometry(descriptor: descriptor).placement, .floating)
    }
  }

  func testSurfaceFramesStayInsideDrawableBounds() {
    let fixtures = [
      DisplayDescriptor(
        frame: CGRect(x: 0, y: 0, width: 1_512, height: 982),
        visibleFrame: CGRect(x: 0, y: 0, width: 1_512, height: 944),
        safeAreaInsets: DisplayInsets(top: 32, left: 0, bottom: 0, right: 0),
        auxiliaryTopLeftArea: CGRect(x: 0, y: 950, width: 672, height: 32),
        auxiliaryTopRightArea: CGRect(x: 840, y: 950, width: 672, height: 32)
      ),
      DisplayDescriptor(
        frame: CGRect(x: 1_512, y: 0, width: 1_920, height: 1_080),
        visibleFrame: CGRect(x: 1_512, y: 0, width: 1_920, height: 1_055),
        safeAreaInsets: .zero,
        auxiliaryTopLeftArea: nil,
        auxiliaryTopRightArea: nil
      ),
      DisplayDescriptor(
        frame: CGRect(x: -320, y: 0, width: 320, height: 180),
        visibleFrame: CGRect(x: -320, y: 20, width: 320, height: 160),
        safeAreaInsets: .zero,
        auxiliaryTopLeftArea: nil,
        auxiliaryTopRightArea: nil
      ),
    ]

    for descriptor in fixtures {
      let geometry = DisplayGeometry(descriptor: descriptor)
      let frames = [geometry.compactFrame, geometry.expandedFrame]

      switch geometry.placement {
      case .notched(let obstructionFrame):
        for frame in frames {
          XCTAssertTrue(
            descriptor.frame.contains(frame),
            "\(frame) escaped \(descriptor.frame)"
          )
          XCTAssertEqual(frame.maxY, descriptor.frame.maxY, accuracy: 0.001)
        }
        XCTAssertEqual(
          geometry.compactFrame.height,
          obstructionFrame.height,
          accuracy: 0.001
        )
      case .floating:
        for frame in frames {
          XCTAssertTrue(
            descriptor.visibleFrame.contains(frame),
            "\(frame) escaped \(descriptor.visibleFrame)"
          )
        }
      }
    }
  }

  func testFloatingCapsuleIsCenteredBelowMenuBar() {
    let descriptor = DisplayDescriptor(
      frame: CGRect(x: 1_512, y: 0, width: 1_920, height: 1_080),
      visibleFrame: CGRect(x: 1_512, y: 0, width: 1_920, height: 1_055),
      safeAreaInsets: .zero,
      auxiliaryTopLeftArea: nil,
      auxiliaryTopRightArea: nil
    )

    let frame = DisplayGeometry(descriptor: descriptor).compactFrame

    XCTAssertEqual(frame.midX, descriptor.frame.midX, accuracy: 0.001)
    XCTAssertEqual(frame.maxY, descriptor.visibleFrame.maxY - 8, accuracy: 0.001)
  }

  func testMediaMetricsStayTopAnchoredAcrossCompactAndExpandedStates() {
    let descriptor = DisplayDescriptor(
      frame: CGRect(x: 0, y: 0, width: 1_920, height: 1_080),
      visibleFrame: CGRect(x: 0, y: 0, width: 1_920, height: 1_055),
      safeAreaInsets: .zero,
      auxiliaryTopLeftArea: nil,
      auxiliaryTopRightArea: nil
    )
    let geometry = DisplayGeometry(
      descriptor: descriptor,
      metrics: .media
    )

    XCTAssertEqual(
      geometry.compactFrame.maxY,
      geometry.expandedFrame.maxY,
      accuracy: 0.001
    )
    XCTAssertEqual(geometry.compactFrame.size, CGSize(width: 310, height: 44))
    XCTAssertEqual(geometry.expandedFrame.size, CGSize(width: 344, height: 170))
  }

  func testNotchedMediaUsesArtworkAndWaveformSizedWings() {
    let descriptor = DisplayDescriptor(
      frame: CGRect(x: 0, y: 0, width: 1_728, height: 1_117),
      visibleFrame: CGRect(x: 0, y: 0, width: 1_728, height: 1_079),
      safeAreaInsets: DisplayInsets(top: 32, left: 0, bottom: 0, right: 0),
      auxiliaryTopLeftArea: CGRect(x: 0, y: 1_085, width: 771, height: 32),
      auxiliaryTopRightArea: CGRect(x: 956, y: 1_085, width: 772, height: 32)
    )
    let geometry = DisplayGeometry(descriptor: descriptor, metrics: .media)

    let compact = geometry.layout(isExpanded: false)
    let expanded = geometry.layout(isExpanded: true)

    XCTAssertEqual(compact.panelFrame.size, CGSize(width: 273, height: 32))
    XCTAssertEqual(
      compact.surfaceFrameInPanel.size,
      CGSize(width: 273, height: 32)
    )
    XCTAssertEqual(compact.surfaceFrameInPanel.origin, .zero)
    XCTAssertEqual(expanded.panelFrame.size, CGSize(width: 344, height: 170))
    XCTAssertEqual(
      expanded.surfaceFrameInPanel,
      CGRect(origin: .zero, size: CGSize(width: 344, height: 170))
    )
  }

  func testMediaTrackFeedbackKeepsStableEdgeThenReturnsToCompactWidth() {
    let descriptor = DisplayDescriptor(
      frame: CGRect(x: 0, y: 0, width: 1_728, height: 1_117),
      visibleFrame: CGRect(x: 0, y: 0, width: 1_728, height: 1_079),
      safeAreaInsets: DisplayInsets(top: 32, left: 0, bottom: 0, right: 0),
      auxiliaryTopLeftArea: CGRect(x: 0, y: 1_085, width: 771, height: 32),
      auxiliaryTopRightArea: CGRect(x: 956, y: 1_085, width: 772, height: 32)
    )
    let geometry = DisplayGeometry(descriptor: descriptor, metrics: .media)

    let previous = geometry.mediaLayout(
      level: .hardware,
      trackChangeDirection: .previous,
      showsTrackPeek: false
    )
    let next = geometry.mediaLayout(
      level: .hardware,
      trackChangeDirection: .next,
      showsTrackPeek: false
    )
    let previousCompact = geometry.mediaLayout(
      level: .compact,
      trackChangeDirection: .previous,
      showsTrackPeek: false
    )
    let nextCompact = geometry.mediaLayout(
      level: .compact,
      trackChangeDirection: .next,
      showsTrackPeek: false
    )
    let previousPeek = geometry.mediaLayout(
      level: .compact,
      trackChangeDirection: .previous,
      showsTrackPeek: true
    )
    let nextPeek = geometry.mediaLayout(
      level: .compact,
      trackChangeDirection: .next,
      showsTrackPeek: true
    )
    let settled = geometry.mediaLayout(
      level: .compact,
      trackChangeDirection: nil,
      showsTrackPeek: false
    )

    let panelEnvelope = CGRect(x: 691.5, y: 947, width: 344, height: 170)
    for layout in [
      previous,
      next,
      previousCompact,
      nextCompact,
      previousPeek,
      nextPeek,
      settled,
    ] {
      XCTAssertEqual(layout.panelFrame, panelEnvelope)
      XCTAssertEqual(layout.surfaceFrameInScreen.maxY, descriptor.frame.maxY)
    }

    XCTAssertEqual(
      previous.surfaceFrameInScreen,
      CGRect(x: 743, y: 1_085, width: 213, height: 32)
    )
    XCTAssertEqual(
      next.surfaceFrameInScreen,
      CGRect(x: 771, y: 1_085, width: 213, height: 32)
    )
    XCTAssertEqual(
      previousPeek.surfaceFrameInScreen,
      CGRect(x: 727, y: 1_053, width: 273, height: 64)
    )
    XCTAssertEqual(
      nextPeek.surfaceFrameInScreen,
      CGRect(x: 727, y: 1_053, width: 273, height: 64)
    )
    XCTAssertEqual(
      settled.surfaceFrameInScreen,
      CGRect(x: 727, y: 1_085, width: 273, height: 32)
    )
    XCTAssertEqual(
      nextPeek.surfaceFrameInPanel,
      CGRect(x: 35.5, y: 106, width: 273, height: 64)
    )
  }

  func testSharedEnvelopeStaysFixedAcrossMediaPauseHandoff() {
    let descriptor = DisplayDescriptor(
      frame: CGRect(x: 0, y: 0, width: 1_728, height: 1_117),
      visibleFrame: CGRect(x: 0, y: 0, width: 1_728, height: 1_079),
      safeAreaInsets: DisplayInsets(top: 32, left: 0, bottom: 0, right: 0),
      auxiliaryTopLeftArea: CGRect(x: 0, y: 1_085, width: 771, height: 32),
      auxiliaryTopRightArea: CGRect(x: 956, y: 1_085, width: 772, height: 32)
    )
    let focusGeometry = DisplayGeometry(descriptor: descriptor)
    let mediaGeometry = DisplayGeometry(
      descriptor: descriptor,
      metrics: .media
    )
    let media = mediaGeometry.sharedEnvelopeLayout(
      containing: mediaGeometry.mediaLayout(
        level: .compact,
        trackChangeDirection: nil,
        showsTrackPeek: false
      ),
      companionMetrics: .standard
    )
    let focus = focusGeometry.sharedEnvelopeLayout(
      containing: focusGeometry.layout(level: .compact),
      companionMetrics: .media
    )

    XCTAssertEqual(
      media.panelFrame,
      CGRect(x: 675, y: 901, width: 377, height: 216)
    )
    XCTAssertEqual(focus.panelFrame, media.panelFrame)
    XCTAssertEqual(
      media.surfaceFrameInScreen,
      CGRect(x: 727, y: 1_085, width: 273, height: 32)
    )
    XCTAssertEqual(
      focus.surfaceFrameInScreen,
      CGRect(x: 675, y: 1_085, width: 377, height: 32)
    )
  }

  func testSharedEnvelopeContainsEveryExistingSurfaceGeometry() {
    let descriptors = [
      DisplayDescriptor(
        frame: CGRect(x: 0, y: 0, width: 1_728, height: 1_117),
        visibleFrame: CGRect(x: 0, y: 0, width: 1_728, height: 1_079),
        safeAreaInsets: DisplayInsets(top: 32, left: 0, bottom: 0, right: 0),
        auxiliaryTopLeftArea: CGRect(x: 0, y: 1_085, width: 771, height: 32),
        auxiliaryTopRightArea: CGRect(x: 956, y: 1_085, width: 772, height: 32)
      ),
      DisplayDescriptor(
        frame: CGRect(x: 1_512, y: 0, width: 1_920, height: 1_080),
        visibleFrame: CGRect(x: 1_512, y: 0, width: 1_920, height: 1_055),
        safeAreaInsets: .zero,
        auxiliaryTopLeftArea: nil,
        auxiliaryTopRightArea: nil
      ),
      DisplayDescriptor(
        frame: CGRect(x: -320, y: 0, width: 320, height: 180),
        visibleFrame: CGRect(x: -320, y: 20, width: 320, height: 160),
        safeAreaInsets: .zero,
        auxiliaryTopLeftArea: nil,
        auxiliaryTopRightArea: nil
      ),
    ]

    for descriptor in descriptors {
      let standardGeometry = DisplayGeometry(descriptor: descriptor)
      for component in [SurfaceComponentID.priorities, .calendar] {
        for level in SurfaceLevel.allCases {
          let active = standardGeometry.layout(level: level)
          let envelope = standardGeometry.sharedEnvelopeLayout(
            containing: active,
            companionMetrics: .media
          )
          assertEnvelope(
            envelope,
            contains: active,
            label: "\(component.rawValue)-\(level.rawValue)"
          )
        }
      }

      let mediaGeometry = DisplayGeometry(
        descriptor: descriptor,
        metrics: .media
      )
      for level in SurfaceLevel.allCases {
        let variants: [(MediaTrackDirection?, Bool)] = [
          (nil, false),
          (.previous, false),
          (.next, false),
          (.previous, true),
          (.next, true),
        ]
        for (direction, showsTrackPeek) in variants {
          let active = mediaGeometry.mediaLayout(
            level: level,
            trackChangeDirection: direction,
            showsTrackPeek: showsTrackPeek
          )
          let envelope = mediaGeometry.sharedEnvelopeLayout(
            containing: active,
            companionMetrics: .standard
          )
          assertEnvelope(
            envelope,
            contains: active,
            label:
              "media-\(level.rawValue)-\(String(describing: direction))-peek:\(showsTrackPeek)"
          )
        }
      }
    }
  }

  func testConstrainedMediaPeekShrinksChangingSideWithoutMovingStableEdge() {
    let descriptor = DisplayDescriptor(
      frame: CGRect(x: -320, y: 0, width: 320, height: 180),
      visibleFrame: CGRect(x: -320, y: 20, width: 320, height: 160),
      safeAreaInsets: .zero,
      auxiliaryTopLeftArea: nil,
      auxiliaryTopRightArea: nil
    )
    let geometry = DisplayGeometry(descriptor: descriptor, metrics: .media)
    let compact = geometry.layout(level: .compact)

    let next = geometry.mediaLayout(
      level: .compact,
      trackChangeDirection: .next,
      showsTrackPeek: true
    )
    let previous = geometry.mediaLayout(
      level: .compact,
      trackChangeDirection: .previous,
      showsTrackPeek: true
    )

    XCTAssertEqual(next.panelFrame, previous.panelFrame)
    XCTAssertEqual(next.panelFrame.size, CGSize(width: 320, height: 152))
    XCTAssertEqual(
      next.surfaceFrameInScreen.minX,
      compact.panelFrame.minX,
      accuracy: 0.001
    )
    XCTAssertEqual(
      previous.surfaceFrameInScreen.maxX,
      compact.panelFrame.maxX,
      accuracy: 0.001
    )
    XCTAssertLessThan(
      next.surfaceFrameInScreen.width,
      SurfaceMetrics.media.expandedSize.width
    )
    XCTAssertTrue(descriptor.visibleFrame.contains(next.panelFrame))
    XCTAssertTrue(descriptor.visibleFrame.contains(previous.panelFrame))
  }

  private func assertEnvelope(
    _ envelope: SurfaceLayout,
    contains active: SurfaceLayout,
    label: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertTrue(
      envelope.panelFrame.contains(active.surfaceFrameInScreen),
      "\(label): \(active.surfaceFrameInScreen) escaped \(envelope.panelFrame)",
      file: file,
      line: line
    )
    XCTAssertEqual(
      envelope.surfaceFrameInScreen,
      active.surfaceFrameInScreen,
      "\(label): active frame changed inside the envelope",
      file: file,
      line: line
    )
  }
}
