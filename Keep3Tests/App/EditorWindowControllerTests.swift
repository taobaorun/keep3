import AppKit
import SwiftUI
import XCTest

@testable import Keep3

@MainActor
final class EditorWindowControllerTests: XCTestCase {
  func testShowEditorSelectsEditorDestinationOnOriginalWindow() throws {
    let (preferences, defaults, suiteName) = makePreferences()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let controller = EditorWindowController(
      model: AppModel(),
      preferences: preferences
    )
    let originalWindow = try XCTUnwrap(controller.window)
    defer { originalWindow.orderOut(nil) }

    controller.showEditor(activate: false)

    XCTAssertEqual(controller.destination, .editor)
    XCTAssertTrue(originalWindow.isVisible)
    XCTAssertTrue(controller.window === originalWindow)
  }

  func testShowSettingsReusesWindowAfterCloseAndReopen() throws {
    let (preferences, defaults, suiteName) = makePreferences()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let controller = EditorWindowController(
      model: AppModel(),
      preferences: preferences
    )
    let originalWindow = try XCTUnwrap(controller.window)
    let hostingView = try XCTUnwrap(
      originalWindow.contentView as? NSHostingView<RootView>
    )
    defer { originalWindow.orderOut(nil) }

    controller.showEditor(activate: false)
    controller.showSettings(activate: false)

    XCTAssertEqual(controller.destination, .settings)
    XCTAssertEqual(hostingView.rootView.destinationState.destination, .settings)
    XCTAssertTrue(originalWindow.isVisible)

    originalWindow.close()
    XCTAssertFalse(originalWindow.isVisible)
    XCTAssertTrue(controller.window === originalWindow)

    controller.showSettings(activate: false)

    XCTAssertEqual(controller.destination, .settings)
    XCTAssertTrue(originalWindow.isVisible)
    XCTAssertTrue(controller.window === originalWindow)
  }

  func testShowEditorAfterSettingsSelectsEditorOnSameWindow() throws {
    let (preferences, defaults, suiteName) = makePreferences()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let controller = EditorWindowController(
      model: AppModel(),
      preferences: preferences
    )
    let originalWindow = try XCTUnwrap(controller.window)
    let hostingView = try XCTUnwrap(
      originalWindow.contentView as? NSHostingView<RootView>
    )
    defer { originalWindow.orderOut(nil) }

    controller.showSettings(activate: false)
    controller.showEditor(activate: false)

    XCTAssertEqual(controller.destination, .editor)
    XCTAssertEqual(hostingView.rootView.destinationState.destination, .editor)
    XCTAssertTrue(controller.window === originalWindow)
  }

  func testEditorWindowProvidesStandardMacWindowBehavior() throws {
    let (preferences, defaults, suiteName) = makePreferences()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let controller = EditorWindowController(
      model: AppModel(),
      preferences: preferences
    )
    let window = try XCTUnwrap(controller.window)
    defer { window.orderOut(nil) }

    XCTAssertEqual(window.title, "Keep3")
    XCTAssertTrue(window.styleMask.contains(.titled))
    XCTAssertTrue(window.styleMask.contains(.closable))
    XCTAssertTrue(window.styleMask.contains(.resizable))
    XCTAssertFalse(window.isReleasedWhenClosed)
  }

  private func makePreferences()
    -> (AppPreferences, UserDefaults, String)
  {
    let suiteName = "Keep3Tests.EditorWindow.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return (AppPreferences(defaults: defaults), defaults, suiteName)
  }
}
