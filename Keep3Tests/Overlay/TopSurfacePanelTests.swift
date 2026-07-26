import AppKit
import SwiftUI
import XCTest

@testable import Keep3

@MainActor
final class TopSurfacePanelTests: XCTestCase {
  func testPanelCannotTakeKeyboardFocus() throws {
    let panel = TopSurfacePanel(
      contentRect: CGRect(x: 100, y: 100, width: 280, height: 44),
      content: try makeContent(title: "当前重点")
    )

    XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
    XCTAssertFalse(panel.canBecomeKey)
    XCTAssertFalse(panel.canBecomeMain)
    XCTAssertTrue(panel.becomesKeyOnlyIfNeeded)
  }

  func testPanelAllowsFocusOnlyDuringExplicitKeyboardNavigation() throws {
    let panel = TopSurfacePanel(
      contentRect: CGRect(x: 100, y: 100, width: 360, height: 216),
      content: try makeContent(title: "当前重点", isExpanded: true)
    )

    panel.setKeyboardNavigationEnabled(true, activateApplication: false)
    XCTAssertTrue(panel.canBecomeKey)

    panel.setKeyboardNavigationEnabled(false, activateApplication: false)
    XCTAssertFalse(panel.canBecomeKey)
  }

  func testMediaTakeoverPreservesExplicitKeyboardNavigation() throws {
    let frame = CGRect(x: 100, y: 100, width: 360, height: 216)
    let panel = TopSurfacePanel(
      contentRect: frame,
      content: try makeContent(title: "当前重点", isExpanded: true)
    )
    panel.setKeyboardNavigationEnabled(true, activateApplication: false)
    XCTAssertTrue(panel.canBecomeKey)

    panel.update(
      mediaPayload: MediaSurfacePayload(
        sessionID: "session-1",
        contentRevision: 1,
        isExpanded: true,
        areControlsEnabled: true
      ),
      presentationStyle: .floatingCapsule,
      surfaceFrameInPanel: CGRect(origin: .zero, size: frame.size),
      onHoverChanged: { _ in },
      onScroll: { _ in },
      onActivateSurface: {},
      onMediaAction: { _ in }
    )

    XCTAssertTrue(panel.canBecomeKey)
  }

  func testControllerReportsKeyboardDeferralLifecycle() {
    let controller = TopSurfaceController()
    var changes: [(SurfaceAutomaticDeferralReason, Bool)] = []
    controller.onAutomaticTransitionDeferralChange = {
      changes.append(($0, $1))
    }

    controller.beginKeyboardNavigation()
    controller.endKeyboardNavigation()

    XCTAssertEqual(changes.map(\.0), [.keyboardNavigation, .keyboardNavigation])
    XCTAssertEqual(changes.map(\.1), [true, false])
  }

  func testPanelReportsPointerDownAndUpDeferralLifecycle() throws {
    let panel = TopSurfacePanel(
      contentRect: CGRect(x: 100, y: 100, width: 280, height: 44),
      content: try makeContent(title: "当前重点")
    )
    var changes: [Bool] = []
    panel.onPointerInteractionChanged = {
      changes.append($0)
    }
    let down = try XCTUnwrap(
      NSEvent.mouseEvent(
        with: .leftMouseDown,
        location: CGPoint(x: 140, y: 22),
        modifierFlags: [],
        timestamp: 1,
        windowNumber: panel.windowNumber,
        context: nil,
        eventNumber: 1,
        clickCount: 1,
        pressure: 1
      )
    )
    let up = try XCTUnwrap(
      NSEvent.mouseEvent(
        with: .leftMouseUp,
        location: CGPoint(x: 140, y: 22),
        modifierFlags: [],
        timestamp: 2,
        windowNumber: panel.windowNumber,
        context: nil,
        eventNumber: 2,
        clickCount: 1,
        pressure: 0
      )
    )

    panel.sendEvent(down)
    panel.sendEvent(up)

    XCTAssertEqual(changes, [true, false])
  }

  func testKeyboardCommandsAcceptOnlyUnmodifiedNavigationKeys() {
    XCTAssertEqual(
      TopSurfaceKeyboardCommand(keyCode: 123, modifiers: []),
      .previous
    )
    XCTAssertEqual(
      TopSurfaceKeyboardCommand(keyCode: 124, modifiers: []),
      .next
    )
    XCTAssertEqual(
      TopSurfaceKeyboardCommand(keyCode: 126, modifiers: []),
      .surfaceUp
    )
    XCTAssertEqual(
      TopSurfaceKeyboardCommand(keyCode: 125, modifiers: []),
      .surfaceDown
    )
    XCTAssertEqual(
      TopSurfaceKeyboardCommand(
        keyCode: 124,
        modifiers: [.numericPad, .function]
      ),
      .next
    )
    XCTAssertEqual(
      TopSurfaceKeyboardCommand(keyCode: 53, modifiers: []),
      .dismiss
    )
    XCTAssertEqual(
      TopSurfaceKeyboardCommand(keyCode: 36, modifiers: []),
      .openItem
    )
    XCTAssertNil(
      TopSurfaceKeyboardCommand(keyCode: 123, modifiers: [.command])
    )
    XCTAssertNil(TopSurfaceKeyboardCommand(keyCode: 0, modifiers: []))
  }

  func testPanelUsesStatusLevelAndJoinsSpaces() throws {
    let panel = TopSurfacePanel(
      contentRect: CGRect(x: 100, y: 100, width: 280, height: 44),
      content: try makeContent(title: "当前重点")
    )

    XCTAssertEqual(panel.level, .mainMenu + 3)
    XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces))
    XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenAuxiliary))
    XCTAssertTrue(panel.collectionBehavior.contains(.ignoresCycle))
    XCTAssertFalse(panel.hidesOnDeactivate)
    XCTAssertEqual(panel.sharingType, .readOnly)
  }

  func testNotchAttachedPanelDoesNotRenderAsDetachedCapsule() throws {
    let presentationStyle = TopSurfacePresentationStyle.notchAttached(
      notchSize: CGSize(width: 185, height: 32)
    )
    let panel = TopSurfacePanel(
      contentRect: CGRect(x: 100, y: 100, width: 377, height: 216),
      surfaceFrameInPanel: CGRect(x: 0, y: 184, width: 377, height: 32),
      content: try makeContent(title: "当前重点"),
      presentationStyle: presentationStyle
    )

    XCTAssertEqual(panel.renderedPresentationStyle, presentationStyle)
    XCTAssertEqual(
      panel.renderedSurfaceFrameInPanel,
      CGRect(x: 0, y: 184, width: 377, height: 32)
    )
    XCTAssertFalse(panel.hasShadow)

    let path = TopSurfaceShape(
      presentationStyle: presentationStyle,
      isExpanded: false
    ).path(in: CGRect(x: 0, y: 0, width: 377, height: 32))

    XCTAssertTrue(path.contains(CGPoint(x: 188.5, y: 1)))
    XCTAssertTrue(path.contains(CGPoint(x: 10, y: 1)))
    XCTAssertTrue(path.contains(CGPoint(x: 10, y: 16)))
  }

  func testHostedMediaSurfaceConvertsTopAnchoredPanelCoordinatesToSwiftUI() {
    let layout = TopSurfaceHostedLayout(
      panelSize: CGSize(width: 344, height: 170),
      surfaceFrameInPanel: CGRect(x: 35.5, y: 106, width: 273, height: 64)
    )

    XCTAssertEqual(
      layout.centerInSwiftUICoordinates,
      CGPoint(x: 172, y: 32)
    )
  }

  func testHoverEffectSlightlyEnlargesTheCapsule() {
    let resting = TopSurfaceHoverEffect(isActive: false)
    let hovered = TopSurfaceHoverEffect(isActive: true)

    XCTAssertEqual(resting.scaleX, 1)
    XCTAssertEqual(resting.scaleY, 1)
    XCTAssertGreaterThan(hovered.scaleX, resting.scaleX)
    XCTAssertGreaterThan(hovered.scaleY, resting.scaleY)
    XCTAssertLessThanOrEqual(hovered.scaleX, 1.03)
    XCTAssertLessThanOrEqual(hovered.scaleY, 1.06)
  }

  func testHoverRegionStaysEnteredWhenTheSurfaceExpandsUnderThePointer() {
    var region = TopSurfaceHoverRegion(
      activeFrame: CGRect(x: 79.5, y: 184, width: 185, height: 32)
    )
    let pointer = CGPoint(x: 172, y: 200)

    XCTAssertEqual(region.reconcile(pointerLocation: pointer), true)
    XCTAssertNil(
      region.updateActiveFrame(
        CGRect(x: 35.5, y: 184, width: 273, height: 32),
        pointerLocation: pointer
      )
    )
    XCTAssertTrue(region.isPointerInside)
    XCTAssertEqual(
      region.reconcile(pointerLocation: CGPoint(x: 20, y: 200)),
      false
    )
  }

  func testCompactNotchContentReservesThePhysicalCameraHousing() {
    let layout = NotchCompactContentLayout(
      surfaceSize: CGSize(width: 377, height: 32),
      obstructionSize: CGSize(width: 185, height: 32)
    )

    XCTAssertEqual(layout.leftWingFrame.width, 96, accuracy: 0.001)
    XCTAssertEqual(layout.rightWingFrame.width, 96, accuracy: 0.001)
    XCTAssertEqual(layout.obstructionFrame.width, 185, accuracy: 0.001)
    XCTAssertEqual(layout.leftWingFrame.maxX, layout.obstructionFrame.minX)
    XCTAssertEqual(layout.obstructionFrame.maxX, layout.rightWingFrame.minX)
    XCTAssertFalse(layout.leftWingFrame.intersects(layout.obstructionFrame))
    XCTAssertFalse(layout.rightWingFrame.intersects(layout.obstructionFrame))
  }

  func testControllerShowsRepositionsAndRemovesOnePanel() throws {
    let controller = TopSurfaceController()
    let initialFrame = CGRect(x: 100, y: 500, width: 280, height: 44)
    let movedFrame = CGRect(x: 400, y: 520, width: 360, height: 216)
    defer { controller.remove() }

    controller.show(
      frame: initialFrame,
      content: try makeContent(title: "写 Keep3")
    )

    let originalPanel = try XCTUnwrap(controller.panel)
    XCTAssertEqual(originalPanel.frame, initialFrame)
    XCTAssertTrue(originalPanel.isVisible)
    XCTAssertEqual(originalPanel.renderedContent.item.title, "写 Keep3")

    controller.show(
      frame: movedFrame,
      content: try makeContent(
        title: "发布 Keep3",
        isExpanded: true
      )
    )

    XCTAssertTrue(controller.panel === originalPanel)
    XCTAssertEqual(controller.panel?.frame, movedFrame)
    XCTAssertEqual(originalPanel.renderedContent.item.title, "发布 Keep3")
    XCTAssertTrue(originalPanel.renderedContent.isExpanded)

    controller.remove()

    XCTAssertNil(controller.panel)
    XCTAssertFalse(originalPanel.isVisible)
    XCTAssertEqual(originalPanel.transitionContext.phase, .hidden)

    controller.show(
      frame: initialFrame,
      content: try makeContent(title: "最新 canonical focus")
    )
    let recreatedPanel = try XCTUnwrap(controller.panel)
    XCTAssertFalse(recreatedPanel === originalPanel)
    XCTAssertEqual(recreatedPanel.transitionContext.phase, .settled)
    controller.remove()
  }

  func testControllerReusesAndRightSizesNotchedPanelAcrossLevels() throws {
    let controller = TopSurfaceController()
    let compactPanelFrame = CGRect(x: 675, y: 1_085, width: 377, height: 32)
    let expandedPanelFrame = CGRect(x: 683, y: 901, width: 360, height: 216)
    let compactLayout = SurfaceLayout(
      panelFrame: compactPanelFrame,
      surfaceFrameInPanel: CGRect(origin: .zero, size: compactPanelFrame.size),
      obstructionSize: CGSize(width: 185, height: 32)
    )
    let expandedLayout = SurfaceLayout(
      panelFrame: expandedPanelFrame,
      surfaceFrameInPanel: CGRect(origin: .zero, size: expandedPanelFrame.size),
      obstructionSize: CGSize(width: 185, height: 32)
    )
    defer { controller.remove() }

    controller.show(
      layout: compactLayout,
      content: try makeContent(title: "写 Keep3")
    )
    let panel = try XCTUnwrap(controller.panel)

    controller.show(
      layout: expandedLayout,
      content: try makeContent(title: "写 Keep3", isExpanded: true)
    )

    XCTAssertEqual(panel.frame, expandedPanelFrame)
    XCTAssertEqual(
      panel.renderedSurfaceFrameInPanel,
      expandedLayout.surfaceFrameInPanel
    )
    XCTAssertTrue(controller.panel === panel)
  }

  func testControllerCanReuseTheSamePanelForMediaAndFocus() throws {
    let controller = TopSurfaceController()
    let frame = CGRect(x: 100, y: 500, width: 310, height: 44)
    defer { controller.remove() }

    controller.show(
      frame: frame,
      content: try makeContent(title: "写 Keep3")
    )
    let panel = try XCTUnwrap(controller.panel)
    let media = MediaSurfacePayload(
      sessionID: "session-1",
      contentRevision: 1,
      isExpanded: false,
      areControlsEnabled: true,
      session: MediaSession.normalize(
        .init(
          sessionID: "session-1",
          sourceBundleIdentifier: "com.netease.163music",
          title: "Track",
          artist: "Artist",
          duration: nil,
          progress: nil,
          capabilities: ["playPause"]
        )
      ),
      playbackState: .playing
    )
    let layout = SurfaceLayout(
      panelFrame: frame,
      surfaceFrameInPanel: CGRect(origin: .zero, size: frame.size),
      obstructionSize: nil
    )

    controller.showMedia(layout: layout, payload: media)

    XCTAssertTrue(controller.panel === panel)
    XCTAssertEqual(panel.renderedMediaPayload, media)

    controller.show(
      frame: frame,
      content: try makeContent(title: "发布 Keep3")
    )

    XCTAssertEqual(panel.renderedContent.item.title, "发布 Keep3")
  }

  func testControllerCanReuseTheSamePanelForCalendar() throws {
    let controller = TopSurfaceController()
    let compactFrame = CGRect(x: 100, y: 500, width: 280, height: 44)
    let expandedFrame = CGRect(x: 60, y: 328, width: 360, height: 216)
    defer { controller.remove() }

    controller.show(
      frame: compactFrame,
      content: try makeContent(title: "写 Keep3")
    )
    let panel = try XCTUnwrap(controller.panel)
    let payload = CalendarSurfacePayload(
      state: .content(
        events: [],
        isRefreshing: false,
        refreshFailure: nil
      ),
      level: .expanded,
      revision: 1
    )
    let layout = SurfaceLayout(
      panelFrame: expandedFrame,
      surfaceFrameInPanel: CGRect(origin: .zero, size: expandedFrame.size),
      obstructionSize: nil
    )

    controller.showCalendar(layout: layout, payload: payload)

    XCTAssertTrue(controller.panel === panel)
    XCTAssertEqual(panel.renderedCalendarPayload, payload)
    XCTAssertEqual(panel.frame, expandedFrame)
  }

  func testHostIdentitySurvivesFocusMediaAndCalendarUpdates() throws {
    let frame = CGRect(x: 100, y: 100, width: 360, height: 216)
    let panel = TopSurfacePanel(
      contentRect: frame,
      content: try makeContent(title: "Focus")
    )
    let hostIdentity = panel.hostingViewIdentity

    panel.update(
      mediaPayload: MediaSurfacePayload(
        sessionID: "session-1",
        contentRevision: 1,
        isExpanded: false,
        areControlsEnabled: true
      ),
      presentationStyle: .floatingCapsule,
      surfaceFrameInPanel: CGRect(origin: .zero, size: frame.size),
      onHoverChanged: { _ in },
      onScroll: { _ in },
      onActivateSurface: {},
      onMediaAction: { _ in }
    )
    XCTAssertEqual(panel.hostingViewIdentity, hostIdentity)

    panel.update(
      calendarPayload: CalendarSurfacePayload(
        state: .content(
          events: [],
          isRefreshing: false,
          refreshFailure: nil
        ),
        level: .expanded,
        revision: 1
      ),
      presentationStyle: .floatingCapsule,
      surfaceFrameInPanel: CGRect(origin: .zero, size: frame.size),
      onHoverChanged: { _ in },
      onScroll: { _ in },
      onActivateSurface: {}
    )
    XCTAssertEqual(panel.hostingViewIdentity, hostIdentity)

    panel.update(
      content: try makeContent(title: "Back to focus", isExpanded: true),
      presentationStyle: .floatingCapsule,
      surfaceFrameInPanel: CGRect(origin: .zero, size: frame.size),
      onHoverChanged: { _ in },
      onScroll: { _ in },
      onActivateSurface: {},
      onRequestKeyboardNavigation: {},
      onSurfaceNavigation: { _ in },
      onDismiss: {},
      onNavigate: { _ in },
      onOpenItem: {}
    )
    XCTAssertEqual(panel.hostingViewIdentity, hostIdentity)
  }

  func testStableActionRouterAlwaysInvokesLatestDestinationHandlers() throws {
    let frame = CGRect(x: 100, y: 100, width: 360, height: 216)
    var activatedDestination = "initial"
    var mediaActions: [MediaSurfaceAction] = []
    let panel = TopSurfacePanel(
      contentRect: frame,
      content: try makeContent(title: "Focus"),
      onActivateSurface: {
        activatedDestination = "focus"
      }
    )

    panel.performActivateSurface()
    XCTAssertEqual(activatedDestination, "focus")

    panel.update(
      mediaPayload: MediaSurfacePayload(
        sessionID: "session-1",
        contentRevision: 1,
        isExpanded: false,
        areControlsEnabled: true
      ),
      presentationStyle: .floatingCapsule,
      surfaceFrameInPanel: CGRect(origin: .zero, size: frame.size),
      onHoverChanged: { _ in },
      onScroll: { _ in },
      onActivateSurface: {
        activatedDestination = "media"
      },
      onMediaAction: {
        mediaActions.append($0)
      }
    )

    panel.performActivateSurface()
    panel.performMediaAction(.next)
    XCTAssertEqual(activatedDestination, "media")
    XCTAssertEqual(mediaActions, [.next])

    panel.update(
      calendarPayload: CalendarSurfacePayload(
        state: .content(
          events: [],
          isRefreshing: false,
          refreshFailure: nil
        ),
        level: .expanded,
        revision: 1
      ),
      presentationStyle: .floatingCapsule,
      surfaceFrameInPanel: CGRect(origin: .zero, size: frame.size),
      onHoverChanged: { _ in },
      onScroll: { _ in },
      onActivateSurface: {
        activatedDestination = "calendar"
      }
    )

    panel.performActivateSurface()
    panel.performMediaAction(.previous)
    XCTAssertEqual(activatedDestination, "calendar")
    XCTAssertEqual(mediaActions, [.next])
  }

  func testPresentedGeometryInterpolatesAndClipsWithoutUsingEndpointUnion() {
    let panelBounds = CGRect(x: 0, y: 0, width: 360, height: 216)
    let source = TopSurfacePresentedGeometry(
      frame: CGRect(x: 80, y: 184, width: 200, height: 32),
      presentationStyle: .floatingCapsule,
      level: .compact,
      panelBounds: panelBounds
    )
    let target = TopSurfacePresentedGeometry(
      frame: CGRect(x: -20, y: 0, width: 400, height: 216),
      presentationStyle: .floatingCapsule,
      level: .expanded,
      panelBounds: panelBounds
    )

    let midpoint = source.interpolated(to: target, progress: 0.5)

    XCTAssertEqual(source.interpolated(to: target, progress: 0), source)
    XCTAssertEqual(source.interpolated(to: target, progress: 1), target)
    XCTAssertEqual(
      midpoint.frame,
      CGRect(x: 40, y: 92, width: 280, height: 124)
    )
    XCTAssertFalse(midpoint.contains(CGPoint(x: 40, y: 92)))
    XCTAssertTrue(midpoint.contains(CGPoint(x: 180, y: 154)))
    XCTAssertFalse(midpoint.contains(CGPoint(x: 10, y: 154)))
  }

  func testFloatingHoverExitUsesCurrentSilhouetteWithEightPointSlop() {
    let geometry = TopSurfacePresentedGeometry(
      frame: CGRect(x: 80, y: 80, width: 200, height: 44),
      presentationStyle: .floatingCapsule,
      level: .compact,
      panelBounds: CGRect(x: 0, y: 0, width: 360, height: 216)
    )

    XCTAssertFalse(
      geometry.containsForHover(CGPoint(x: 73, y: 102), wasInside: false)
    )
    XCTAssertTrue(
      geometry.containsForHover(CGPoint(x: 73, y: 102), wasInside: true)
    )
    XCTAssertFalse(
      geometry.containsForHover(CGPoint(x: 71, y: 102), wasInside: true)
    )
  }

  func testNotchHoverExitKeepsTopEdgeCorridor() {
    let geometry = TopSurfacePresentedGeometry(
      frame: CGRect(x: 40, y: 120, width: 280, height: 44),
      presentationStyle: .notchAttached(
        notchSize: CGSize(width: 185, height: 32)
      ),
      level: .compact,
      panelBounds: CGRect(x: 0, y: 0, width: 360, height: 216)
    )
    let corridorPoint = CGPoint(x: 180, y: 190)

    XCTAssertFalse(
      geometry.containsForHover(corridorPoint, wasInside: false)
    )
    XCTAssertTrue(
      geometry.containsForHover(corridorPoint, wasInside: true)
    )
  }

  func testRapidRetargetKeepsOnlyLatestTwoLayersAndLatestIntent() throws {
    let frame = CGRect(x: 0, y: 0, width: 360, height: 216)
    let panel = TopSurfacePanel(
      contentRect: frame,
      content: try makeContent(title: "Focus")
    )
    let firstGeneration = panel.transitionContext.generation

    panel.update(
      mediaPayload: MediaSurfacePayload(
        sessionID: "session-1",
        contentRevision: 1,
        isExpanded: false,
        areControlsEnabled: true
      ),
      presentationStyle: .floatingCapsule,
      surfaceFrameInPanel: frame,
      transitionIntent: .manualComponent(.next),
      onHoverChanged: { _ in },
      onScroll: { _ in },
      onActivateSurface: {},
      onMediaAction: { _ in }
    )
    let mediaGeneration = panel.transitionContext.generation

    panel.update(
      calendarPayload: CalendarSurfacePayload(
        state: .content(
          events: [],
          isRefreshing: false,
          refreshFailure: nil
        ),
        level: .compact,
        revision: 1
      ),
      presentationStyle: .floatingCapsule,
      surfaceFrameInPanel: frame,
      transitionIntent: .manualComponent(.next),
      onHoverChanged: { _ in },
      onScroll: { _ in },
      onActivateSurface: {}
    )

    XCTAssertGreaterThan(mediaGeneration, firstGeneration)
    XCTAssertGreaterThan(
      panel.transitionContext.generation,
      mediaGeneration
    )
    XCTAssertEqual(panel.transitionContext.target.componentID, .calendar)
    XCTAssertEqual(panel.transitionContext.direction, .next)
    XCTAssertEqual(panel.liveHostedLayerCount, 2)
  }

  func testRapidRetargetPreservesOriginalVisualSourceAndHandoffProgress()
    throws
  {
    let frame = CGRect(x: 0, y: 0, width: 360, height: 216)
    let focusSnapshot = TopSurfaceHostSnapshot(
      content: .focus(try makeContent(title: "Focus")),
      presentationStyle: .floatingCapsule,
      panelSize: frame.size,
      surfaceFrameInPanel: frame
    )
    let state = TopSurfaceHostState(initialSnapshot: focusSnapshot)

    state.update(
      snapshot: TopSurfaceHostSnapshot(
        content: .media(
          MediaSurfacePayload(
            sessionID: "session-1",
            contentRevision: 1,
            isExpanded: false,
            areControlsEnabled: true
          )
        ),
        presentationStyle: .floatingCapsule,
        panelSize: frame.size,
        surfaceFrameInPanel: frame
      ),
      intent: .manualComponent(.next),
      reduceMotion: false
    )
    let firstHandoffGeneration = state.handoffStartGeneration

    state.update(
      snapshot: TopSurfaceHostSnapshot(
        content: .calendar(
          CalendarSurfacePayload(
            state: .content(
              events: [],
              isRefreshing: false,
              refreshFailure: nil
            ),
            level: .compact,
            revision: 1
          )
        ),
        presentationStyle: .floatingCapsule,
        panelSize: frame.size,
        surfaceFrameInPanel: frame
      ),
      intent: .manualComponent(.next),
      reduceMotion: false
    )

    XCTAssertEqual(state.sourceSnapshot, focusSnapshot)
    XCTAssertEqual(
      state.handoffStartGeneration,
      firstHandoffGeneration
    )
    XCTAssertGreaterThan(
      state.shellGeneration,
      firstHandoffGeneration
    )
    XCTAssertEqual(state.liveLayerCount, 2)
  }

  func testSameIdentityLayoutChangePublishesLayoutOnlyVisualUpdate() {
    let compactFrame = CGRect(x: 40, y: 172, width: 280, height: 44)
    let peekFrame = CGRect(x: 8, y: 152, width: 344, height: 64)
    let initialSnapshot = TopSurfaceHostSnapshot(
      content: .media(
        MediaSurfacePayload(
          sessionID: "session-1",
          contentRevision: 1,
          isExpanded: false,
          areControlsEnabled: true
        )
      ),
      presentationStyle: .floatingCapsule,
      panelSize: CGSize(width: 360, height: 216),
      surfaceFrameInPanel: compactFrame
    )
    let state = TopSurfaceHostState(initialSnapshot: initialSnapshot)

    state.update(
      snapshot: TopSurfaceHostSnapshot(
        content: .media(
          MediaSurfacePayload(
            sessionID: "session-1",
            contentRevision: 2,
            isExpanded: false,
            areControlsEnabled: true,
            trackPeek: MediaTrackPeek(
              direction: .next,
              title: "Next",
              artist: "Artist"
            )
          )
        ),
        presentationStyle: .floatingCapsule,
        panelSize: CGSize(width: 360, height: 216),
        surfaceFrameInPanel: peekFrame
      ),
      intent: .content,
      reduceMotion: false
    )

    XCTAssertEqual(state.transitionContext.phase, .settled)
    XCTAssertEqual(state.liveLayerCount, 1)
    XCTAssertEqual(state.layoutOnlyGeneration, state.shellGeneration)
    XCTAssertEqual(state.snapshot.layout.surfaceFrameInPanel, peekFrame)
  }

  func testComponentActionRouterWaitsForTransitionSettlement() throws {
    let frame = CGRect(x: 0, y: 0, width: 360, height: 216)
    let state = TopSurfaceHostState(
      initialSnapshot: TopSurfaceHostSnapshot(
        content: .focus(try makeContent(title: "Focus")),
        presentationStyle: .floatingCapsule,
        panelSize: frame.size,
        surfaceFrameInPanel: frame
      )
    )
    var browsed: [TopSurfaceBrowseDirection] = []
    var mediaActions: [MediaSurfaceAction] = []
    var shellNavigation: [SurfaceGestureIntent] = []
    let router = TopSurfaceActionRouter(
      onActivateSurface: {},
      onRequestKeyboardNavigation: {},
      onSurfaceNavigation: { shellNavigation.append($0) },
      onNavigate: { browsed.append($0) },
      onOpenItem: {},
      onMediaAction: { mediaActions.append($0) },
      areComponentControlsEnabled: {
        state.transitionContext.phase == .settled
      },
      onAccessibilityNavigationAction: { _ in }
    )
    state.update(
      snapshot: TopSurfaceHostSnapshot(
        content: .media(
          MediaSurfacePayload(
            sessionID: "session-1",
            contentRevision: 1,
            isExpanded: false,
            areControlsEnabled: true
          )
        ),
        presentationStyle: .floatingCapsule,
        panelSize: frame.size,
        surfaceFrameInPanel: frame
      ),
      intent: .manualComponent(.next),
      reduceMotion: false
    )

    router.navigate(.next)
    router.performMediaAction(.next)
    router.navigateSurface(.nextComponent)

    XCTAssertEqual(browsed, [])
    XCTAssertEqual(mediaActions, [])
    XCTAssertEqual(shellNavigation, [.nextComponent])

    state.complete(shellGeneration: state.shellGeneration)
    router.navigate(.next)
    router.performMediaAction(.next)

    XCTAssertEqual(browsed, [.next])
    XCTAssertEqual(mediaActions, [.next])
  }

  func testShellNavigationRemainsAvailableWhileControlsAreInert() throws {
    let frame = CGRect(x: 0, y: 0, width: 360, height: 216)
    var navigation: [SurfaceGestureIntent] = []
    let panel = TopSurfacePanel(
      contentRect: frame,
      content: try makeContent(title: "Focus")
    )
    panel.update(
      mediaPayload: MediaSurfacePayload(
        sessionID: "session-1",
        contentRevision: 1,
        isExpanded: false,
        areControlsEnabled: true
      ),
      presentationStyle: .floatingCapsule,
      surfaceFrameInPanel: frame,
      transitionIntent: .manualComponent(.next),
      onHoverChanged: { _ in },
      onScroll: { _ in },
      onActivateSurface: {},
      onSurfaceNavigation: {
        navigation.append($0)
      },
      onMediaAction: { _ in }
    )

    XCTAssertFalse(panel.areComponentControlsEnabled)
    panel.performSurfaceNavigation(.nextComponent)
    XCTAssertEqual(navigation, [.nextComponent])
  }

  func testContentRevisionsStaySettledWithoutCreatingShellOverlap() throws {
    let frame = CGRect(x: 0, y: 0, width: 360, height: 216)
    let focusID = UUID()
    let initialFocus = TopSurfaceContent(
      item: try FocusItem(id: focusID, title: "Initial"),
      position: 1,
      itemCount: 1,
      isCurrentFocus: true,
      presentation: FocusSurfacePayload(
        visibleItemID: focusID,
        isExpanded: false,
        revision: 1,
        expansionReason: .none
      )
    )
    let panel = TopSurfacePanel(contentRect: frame, content: initialFocus)

    panel.update(
      content: TopSurfaceContent(
        item: try FocusItem(id: focusID, title: "Edited"),
        position: 1,
        itemCount: 1,
        isCurrentFocus: true,
        presentation: FocusSurfacePayload(
          visibleItemID: focusID,
          isExpanded: false,
          revision: 2,
          expansionReason: .none
        )
      ),
      presentationStyle: .floatingCapsule,
      surfaceFrameInPanel: frame,
      transitionIntent: .content,
      onHoverChanged: { _ in },
      onScroll: { _ in },
      onActivateSurface: {},
      onRequestKeyboardNavigation: {},
      onSurfaceNavigation: { _ in },
      onDismiss: {},
      onNavigate: { _ in },
      onOpenItem: {}
    )
    XCTAssertEqual(panel.transitionContext.phase, .settled)
    XCTAssertEqual(panel.liveHostedLayerCount, 1)

    let mediaPanel = TopSurfacePanel(
      contentRect: frame,
      mediaPayload: MediaSurfacePayload(
        sessionID: "session-1",
        contentRevision: 1,
        isExpanded: false,
        areControlsEnabled: true
      )
    )
    mediaPanel.update(
      mediaPayload: MediaSurfacePayload(
        sessionID: "session-1",
        contentRevision: 2,
        isExpanded: false,
        areControlsEnabled: true
      ),
      presentationStyle: .floatingCapsule,
      surfaceFrameInPanel: frame,
      transitionIntent: .content,
      onHoverChanged: { _ in },
      onScroll: { _ in },
      onActivateSurface: {},
      onMediaAction: { _ in }
    )
    XCTAssertEqual(mediaPanel.transitionContext.phase, .settled)
    XCTAssertEqual(mediaPanel.liveHostedLayerCount, 1)

    let calendar = CalendarSurfacePayload(
      state: .content(
        events: [],
        isRefreshing: false,
        refreshFailure: nil
      ),
      level: .compact,
      revision: 1
    )
    let calendarPanel = TopSurfacePanel(
      contentRect: frame,
      calendarPayload: calendar
    )
    calendarPanel.update(
      calendarPayload: CalendarSurfacePayload(
        state: .content(
          events: [],
          isRefreshing: true,
          refreshFailure: nil
        ),
        level: .compact,
        revision: 2
      ),
      presentationStyle: .floatingCapsule,
      surfaceFrameInPanel: frame,
      transitionIntent: .content,
      onHoverChanged: { _ in },
      onScroll: { _ in },
      onActivateSurface: {}
    )
    XCTAssertEqual(calendarPanel.transitionContext.phase, .settled)
    XCTAssertEqual(calendarPanel.liveHostedLayerCount, 1)
  }

  func testAccessibilityRequestCrossesDualLayerHandoffIntoSettledTarget() {
    let frame = CGRect(x: 0, y: 0, width: 360, height: 216)
    let state = TopSurfaceHostState(
      initialSnapshot: TopSurfaceHostSnapshot(
        content: .media(
          MediaSurfacePayload(
            sessionID: "session-1",
            contentRevision: 1,
            isExpanded: true,
            areControlsEnabled: true
          )
        ),
        presentationStyle: .floatingCapsule,
        panelSize: frame.size,
        surfaceFrameInPanel: frame
      )
    )
    state.update(
      snapshot: TopSurfaceHostSnapshot(
        content: .media(
          MediaSurfacePayload(
            sessionID: "session-1",
            contentRevision: 1,
            isExpanded: false,
            areControlsEnabled: true
          )
        ),
        presentationStyle: .floatingCapsule,
        panelSize: frame.size,
        surfaceFrameInPanel: frame
      ),
      intent: .collapse,
      reduceMotion: false
    )

    state.requestAccessibilityFocus(
      for: .expandedRetreat(for: .media)
    )

    XCTAssertEqual(state.transitionContext.phase, .transitioning)
    XCTAssertNil(state.accessibilityFocusRequest)

    state.complete(shellGeneration: state.shellGeneration)

    XCTAssertEqual(state.transitionContext.phase, .settled)
    XCTAssertEqual(
      state.accessibilityFocusRequest?.destination,
      .compactMedia
    )
    XCTAssertEqual(
      state.rendererContext.accessibilityFocusRequest,
      state.accessibilityFocusRequest
    )
  }

  func testAccessibilityInteractionPinsOnlyUntilItsHandoffSettles() {
    let frame = CGRect(x: 0, y: 0, width: 360, height: 216)
    let state = TopSurfaceHostState(
      initialSnapshot: TopSurfaceHostSnapshot(
        content: .media(
          MediaSurfacePayload(
            sessionID: "session-1",
            contentRevision: 1,
            isExpanded: true,
            areControlsEnabled: true
          )
        ),
        presentationStyle: .floatingCapsule,
        panelSize: frame.size,
        surfaceFrameInPanel: frame
      )
    )
    var deferralChanges: [Bool] = []
    state.onAccessibilityInteractionChanged = {
      deferralChanges.append($0)
    }

    state.requestAccessibilityFocus(
      for: .expandedRetreat(for: .media)
    )
    state.update(
      snapshot: TopSurfaceHostSnapshot(
        content: .media(
          MediaSurfacePayload(
            sessionID: "session-1",
            contentRevision: 1,
            isExpanded: false,
            areControlsEnabled: true
          )
        ),
        presentationStyle: .floatingCapsule,
        panelSize: frame.size,
        surfaceFrameInPanel: frame
      ),
      intent: .collapse,
      reduceMotion: false
    )

    XCTAssertEqual(deferralChanges, [true])
    state.complete(shellGeneration: state.shellGeneration)

    XCTAssertEqual(deferralChanges, [true, false])
    XCTAssertEqual(
      state.accessibilityFocusRequest?.destination,
      .compactMedia
    )
  }

  func testLifecycleRestoreIsNotDiscardedAsAnUnchangedSnapshot() {
    let frame = CGRect(x: 0, y: 0, width: 360, height: 44)
    let snapshot = TopSurfaceHostSnapshot(
      content: .media(
        MediaSurfacePayload(
          sessionID: "session-1",
          contentRevision: 1,
          isExpanded: false,
          areControlsEnabled: true
        )
      ),
      presentationStyle: .floatingCapsule,
      panelSize: frame.size,
      surfaceFrameInPanel: frame
    )
    let state = TopSurfaceHostState(initialSnapshot: snapshot)

    state.cancelForLifecycle()
    state.update(
      snapshot: snapshot,
      intent: .lifecycleRestore,
      reduceMotion: false
    )

    XCTAssertEqual(state.transitionContext.phase, .settled)
    XCTAssertEqual(state.transitionContext.target, snapshot.presentation)
  }

  func testContentOmitsBlankDetailsAndSubitems() throws {
    let item = try FocusItem(
      title: "设计 Keep3",
      details: " \n ",
      subitems: ["", "只展示上下文", "  "]
    )
    let content = TopSurfaceContent(
      item: item,
      position: 2,
      itemCount: 3,
      isCurrentFocus: false,
      isExpanded: true
    )

    XCTAssertNil(content.displayDetails)
    XCTAssertEqual(content.displaySubitems, ["只展示上下文"])
  }

  func testExpandedNotchLayoutKeepsSupportingContentAndFooterInBounds() {
    let layout = ExpandedSurfaceContentLayout(
      surfaceSize: CGSize(width: 377, height: 216),
      topInset: 32
    )

    XCTAssertEqual(
      layout.supportingContentFrame,
      CGRect(x: 20, y: 88, width: 337, height: 75)
    )
    XCTAssertEqual(
      layout.footerFrame,
      CGRect(x: 20, y: 178, width: 337, height: 28)
    )
    XCTAssertEqual(
      layout.surfaceSize.height - layout.footerFrame.maxY,
      10,
      accuracy: 0.001
    )
  }

  func testTransitionIdentityChangesOnlyWhenTheVisibleItemChanges() throws {
    let firstID = UUID()
    let secondID = UUID()
    let first = TopSurfaceContent(
      item: try FocusItem(id: firstID, title: "第一件事"),
      position: 1,
      itemCount: 2,
      isCurrentFocus: true,
      presentation: .init(
        visibleItemID: firstID,
        isExpanded: false,
        revision: 1,
        expansionReason: .none
      )
    )
    let editedFirst = TopSurfaceContent(
      item: try FocusItem(id: firstID, title: "修改后的第一件事"),
      position: 1,
      itemCount: 2,
      isCurrentFocus: true,
      presentation: .init(
        visibleItemID: firstID,
        isExpanded: false,
        revision: 2,
        expansionReason: .none
      )
    )
    let second = TopSurfaceContent(
      item: try FocusItem(id: secondID, title: "第二件事"),
      position: 2,
      itemCount: 2,
      isCurrentFocus: false,
      presentation: .init(
        visibleItemID: secondID,
        isExpanded: false,
        revision: 1,
        expansionReason: .none
      )
    )

    XCTAssertEqual(first.transitionIdentity.itemID, editedFirst.transitionIdentity.itemID)
    XCTAssertNotEqual(first.transitionIdentity.revision, editedFirst.transitionIdentity.revision)
    XCTAssertNotEqual(first.transitionIdentity, second.transitionIdentity)
  }

  private func makeContent(
    title: String,
    isExpanded: Bool = false
  ) throws -> TopSurfaceContent {
    TopSurfaceContent(
      item: try FocusItem(title: title),
      position: 1,
      itemCount: 1,
      isCurrentFocus: true,
      isExpanded: isExpanded
    )
  }
}
