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
    XCTAssertNil(TopSurfaceKeyboardCommand(keyCode: 123, modifiers: [.option]))
    XCTAssertNil(TopSurfaceKeyboardCommand(keyCode: 123, modifiers: [.control]))
    XCTAssertNil(TopSurfaceKeyboardCommand(keyCode: 123, modifiers: [.shift]))
    XCTAssertNil(TopSurfaceKeyboardCommand(keyCode: 0, modifiers: []))
  }

  func testExplicitKeyboardSessionRoutesHorizontalArrowsExactlyOnce() throws {
    var directions: [TopSurfaceBrowseDirection] = []
    let panel = TopSurfacePanel(
      contentRect: CGRect(x: 100, y: 100, width: 360, height: 216),
      content: try makeContent(title: "当前重点", isExpanded: true),
      onNavigate: { directions.append($0) }
    )
    defer {
      panel.setKeyboardNavigationEnabled(false, activateApplication: false)
      panel.orderOut(nil)
    }

    panel.setKeyboardNavigationEnabled(true, activateApplication: false)
    panel.makeKeyAndOrderFront(nil)
    XCTAssertTrue(panel.makeFirstResponder(panel.contentView))

    panel.sendEvent(keyDownEvent(keyCode: 123, windowNumber: panel.windowNumber))
    panel.sendEvent(keyDownEvent(keyCode: 124, windowNumber: panel.windowNumber))

    XCTAssertEqual(directions, [.previous, .next])
  }

  func testExplicitKeyboardSessionEmitsOneCompleteGesturePerVerticalArrow()
    throws
  {
    var events: [SurfaceScrollEvent] = []
    let panel = TopSurfacePanel(
      contentRect: CGRect(x: 100, y: 100, width: 360, height: 216),
      content: try makeContent(title: "当前重点", isExpanded: true),
      onScroll: { events.append($0) }
    )
    defer {
      panel.setKeyboardNavigationEnabled(false, activateApplication: false)
      panel.orderOut(nil)
    }

    panel.setKeyboardNavigationEnabled(true, activateApplication: false)
    panel.makeKeyAndOrderFront(nil)
    XCTAssertTrue(panel.makeFirstResponder(panel.contentView))

    panel.sendEvent(keyDownEvent(keyCode: 126, windowNumber: panel.windowNumber))
    panel.sendEvent(keyDownEvent(keyCode: 125, windowNumber: panel.windowNumber))

    XCTAssertEqual(events.map(\.deltaY), [-30, 0, 30, 0])
    XCTAssertEqual(
      events.map(\.physicalPhase),
      [.began, .ended, .began, .ended]
    )
  }

  func testKeyboardSessionPassesArrowThroughAfterPanelLosesKeyStatus() throws {
    var directions: [TopSurfaceBrowseDirection] = []
    let panel = TopSurfacePanel(
      contentRect: CGRect(x: 100, y: 100, width: 360, height: 216),
      content: try makeContent(title: "当前重点", isExpanded: true),
      onNavigate: { directions.append($0) }
    )
    defer {
      panel.setKeyboardNavigationEnabled(false, activateApplication: false)
      panel.orderOut(nil)
    }

    panel.setKeyboardNavigationEnabled(true, activateApplication: false)
    panel.resignKey()

    panel.sendEvent(keyDownEvent(keyCode: 124, windowNumber: panel.windowNumber))

    XCTAssertTrue(directions.isEmpty)
  }

  func testDisabledKeyboardSessionDoesNotRouteArrows() throws {
    var directions: [TopSurfaceBrowseDirection] = []
    let panel = TopSurfacePanel(
      contentRect: CGRect(x: 100, y: 100, width: 360, height: 216),
      content: try makeContent(title: "当前重点", isExpanded: true),
      onNavigate: { directions.append($0) }
    )
    defer { panel.orderOut(nil) }

    panel.sendEvent(keyDownEvent(keyCode: 124, windowNumber: panel.windowNumber))

    XCTAssertTrue(directions.isEmpty)
  }

  func testExplicitKeyboardSessionDoesNotRouteModifiedArrows() throws {
    var directions: [TopSurfaceBrowseDirection] = []
    let panel = TopSurfacePanel(
      contentRect: CGRect(x: 100, y: 100, width: 360, height: 216),
      content: try makeContent(title: "当前重点", isExpanded: true),
      onNavigate: { directions.append($0) }
    )
    defer {
      panel.setKeyboardNavigationEnabled(false, activateApplication: false)
      panel.orderOut(nil)
    }
    panel.setKeyboardNavigationEnabled(true, activateApplication: false)
    panel.makeKeyAndOrderFront(nil)
    XCTAssertTrue(panel.makeFirstResponder(panel.contentView))

    for modifier: NSEvent.ModifierFlags in [
      .command, .option, .control, .shift,
    ] {
      panel.sendEvent(
        keyDownEvent(
          keyCode: 124,
          modifiers: modifier,
          windowNumber: panel.windowNumber
        )
      )
    }

    XCTAssertTrue(directions.isEmpty)
  }

  func testKeyboardSessionPassesArrowThroughAfterEventViewLosesFocus() throws {
    var directions: [TopSurfaceBrowseDirection] = []
    let panel = TopSurfacePanel(
      contentRect: CGRect(x: 100, y: 100, width: 360, height: 216),
      content: try makeContent(title: "当前重点", isExpanded: true),
      onNavigate: { directions.append($0) }
    )
    defer {
      panel.setKeyboardNavigationEnabled(false, activateApplication: false)
      panel.orderOut(nil)
    }

    panel.setKeyboardNavigationEnabled(true, activateApplication: false)
    panel.makeKeyAndOrderFront(nil)
    XCTAssertTrue(panel.makeFirstResponder(nil))

    panel.sendEvent(keyDownEvent(keyCode: 124, windowNumber: panel.windowNumber))

    XCTAssertTrue(directions.isEmpty)
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

  func testEscapeRestoresTheCapturedApplicationOnce() throws {
    var captureCount = 0
    var restoreCount = 0
    let controller = TopSurfaceController(
      captureApplicationRestoration: {
        captureCount += 1
        return TopSurfaceApplicationRestoration {
          restoreCount += 1
        }
      }
    )
    let frame = CGRect(x: 100, y: 500, width: 360, height: 216)
    defer { controller.remove() }
    controller.show(
      frame: frame,
      content: try makeContent(title: "写 Keep3", isExpanded: true),
      onDismiss: {
        controller.endKeyboardNavigation()
      }
    )
    controller.beginKeyboardNavigation()
    let panel = try XCTUnwrap(controller.panel)

    panel.sendEvent(keyDownEvent(keyCode: 53, windowNumber: panel.windowNumber))
    controller.endKeyboardNavigation()

    XCTAssertEqual(captureCount, 1)
    XCTAssertEqual(restoreCount, 1)
    XCTAssertFalse(panel.canBecomeKey)
  }

  func testSessionTeardownSafelySkipsUnavailableCapturedApplication() throws {
    var isApplicationAvailable = true
    var restoreCount = 0
    let controller = TopSurfaceController(
      captureApplicationRestoration: {
        TopSurfaceApplicationRestoration {
          guard isApplicationAvailable else {
            return
          }
          restoreCount += 1
        }
      }
    )
    controller.show(
      frame: CGRect(x: 100, y: 500, width: 360, height: 216),
      content: try makeContent(title: "写 Keep3", isExpanded: true)
    )
    controller.beginKeyboardNavigation()
    isApplicationAvailable = false

    controller.remove()

    XCTAssertEqual(restoreCount, 0)
    XCTAssertNil(controller.panel)
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

  private func keyDownEvent(
    keyCode: UInt16,
    modifiers: NSEvent.ModifierFlags = [],
    windowNumber: Int = 0
  ) -> NSEvent {
    NSEvent.keyEvent(
      with: .keyDown,
      location: .zero,
      modifierFlags: modifiers,
      timestamp: 0,
      windowNumber: windowNumber,
      context: nil,
      characters: "",
      charactersIgnoringModifiers: "",
      isARepeat: false,
      keyCode: keyCode
    )!
  }
}
