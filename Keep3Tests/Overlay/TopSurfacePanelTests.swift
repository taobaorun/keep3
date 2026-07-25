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

  func testControllerKeepsNotchedPanelFrameWhileSurfaceExpandsInsideIt() throws {
    let controller = TopSurfaceController()
    let panelFrame = CGRect(x: 675, y: 901, width: 377, height: 216)
    let compactLayout = SurfaceLayout(
      panelFrame: panelFrame,
      surfaceFrameInPanel: CGRect(x: 0, y: 184, width: 377, height: 32),
      obstructionSize: CGSize(width: 185, height: 32)
    )
    let expandedLayout = SurfaceLayout(
      panelFrame: panelFrame,
      surfaceFrameInPanel: CGRect(x: 0, y: 0, width: 377, height: 216),
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

    XCTAssertEqual(panel.frame, panelFrame)
    XCTAssertEqual(
      panel.renderedSurfaceFrameInPanel,
      expandedLayout.surfaceFrameInPanel
    )
    XCTAssertTrue(controller.panel === panel)
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
