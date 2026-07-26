import XCTest

@MainActor
final class Keep3UITests: XCTestCase {
  private var app: XCUIApplication!
  private var testDirectoryURL: URL!
  private var defaultsSuiteName: String!

  func testThreeItemLimitCurrentFocusAndReordering() throws {
    try launchIsolatedApp()
    defer { cleanUpIsolatedApp() }

    addItem("Alpha")
    addItem("Beta")
    addItem("Gamma")

    XCTAssertTrue(app.staticTexts["三件事已全部写下"].exists)
    XCTAssertFalse(app.textFields["editor.newItemTitle"].exists)

    app.buttons["editor.item.3"].click()
    let makeCurrent = app.buttons["editor.makeCurrent"]
    XCTAssertTrue(makeCurrent.waitForExistence(timeout: 2))
    makeCurrent.click()

    let moveUp = app.buttons["editor.moveUp"]
    moveUp.click()
    XCTAssertTrue(moveUp.waitForExistence(timeout: 2))
    moveUp.click()

    let firstItem = app.buttons["editor.item.1"]
    XCTAssertTrue(firstItem.waitForExistence(timeout: 2))
    XCTAssertTrue(firstItem.label.contains("Gamma"))
    XCTAssertTrue(firstItem.label.contains("当前重点"))
  }

  func testContentAndBehaviorSettingsSurviveRelaunch() throws {
    try launchIsolatedApp()
    defer { cleanUpIsolatedApp() }

    addItem("Persistent Focus")
    openSettings()
    openSettingsCategory("rotation")

    let automaticRotation = automaticRotationCheckbox()
    XCTAssertTrue(automaticRotation.waitForExistence(timeout: 2))
    automaticRotation.click()

    app.terminate()
    app.launch()

    XCTAssertTrue(app.windows["Keep3"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["editor.item.1"].label.contains("Persistent Focus"))

    openSettings()
    openSettingsCategory("rotation")
    XCTAssertEqual(valueDescription(of: automaticRotationCheckbox()), "0")
  }

  func testOverlayBrowsingOpensTheMatchingEditorItem() throws {
    try launchIsolatedApp(expandedSurface: true)
    defer { cleanUpIsolatedApp() }

    addItem("Alpha")
    addItem("Beta")
    addItem("Gamma")
    let nextButton = app.buttons["overlay.next"]
    XCTAssertTrue(
      nextButton.waitForExistence(timeout: 3),
      app.debugDescription
    )
    nextButton.click()

    let openItem = app.buttons["overlay.openItem"]
    XCTAssertTrue(openItem.waitForExistence(timeout: 2))
    XCTAssertTrue(openItem.label.contains("Beta"))
    openItem.click()

    let titleField = app.textFields["editor.title"]
    XCTAssertTrue(titleField.waitForExistence(timeout: 3))
    XCTAssertEqual(titleField.value as? String, "Beta")
  }

  func testPlayingMediaOwnsSurfaceAndDisablingMediaRestoresFocus()
    throws
  {
    try launchIsolatedApp(
      mediaFixture: true,
      expandedSurface: true
    )
    defer { cleanUpIsolatedApp() }

    let next =
      app.descendants(matching: .any)["media.action.next"]
    XCTAssertTrue(
      next.waitForExistence(timeout: 4),
      app.debugDescription
    )
    next.click()
    XCTAssertTrue(
      app.staticTexts["Keep3 Fixture 2"].waitForExistence(timeout: 2)
    )

    addItem("Focus Returns")
    openSettings()
    let mediaCategory =
      app.descendants(matching: .any)["settings.category.media"]
    XCTAssertTrue(mediaCategory.waitForExistence(timeout: 2))
    mediaCategory.click()

    let mediaEnabled = app.checkBoxes["settings.media.enabled"]
    XCTAssertTrue(mediaEnabled.waitForExistence(timeout: 2))
    mediaEnabled.click()

    XCTAssertTrue(
      app.buttons["overlay.openItem"].waitForExistence(timeout: 4)
    )
    XCTAssertTrue(app.buttons["overlay.openItem"].label.contains("Focus Returns"))
  }

  private func launchIsolatedApp(
    mediaFixture: Bool = false,
    expandedSurface: Bool = false
  ) throws {
    continueAfterFailure = false

    let identifier = UUID().uuidString
    testDirectoryURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("Keep3UITests-\(identifier)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: testDirectoryURL,
      withIntermediateDirectories: true
    )
    defaultsSuiteName = "Keep3UITests.\(identifier)"

    app = XCUIApplication()
    app.launchEnvironment["KEEP3_UI_TEST_STATE_PATH"] =
      testDirectoryURL.appendingPathComponent("state.json").path
    app.launchEnvironment["KEEP3_UI_TEST_DEFAULTS_SUITE"] = defaultsSuiteName
    app.launchEnvironment["KEEP3_UI_TEST_MEDIA_ENABLED"] =
      mediaFixture.description
    if mediaFixture {
      app.launchEnvironment["KEEP3_UI_TEST_MEDIA_FIXTURE"] = "playing"
    }
    if expandedSurface {
      app.launchEnvironment["KEEP3_UI_TEST_SURFACE_LEVEL"] = "expanded"
    }
    app.launch()

    XCTAssertTrue(app.windows["Keep3"].waitForExistence(timeout: 5))
  }

  private func cleanUpIsolatedApp() {
    app?.terminate()
    if let defaultsSuiteName,
      let defaults = UserDefaults(suiteName: defaultsSuiteName)
    {
      defaults.removePersistentDomain(forName: defaultsSuiteName)
    }
    if let testDirectoryURL,
      FileManager.default.fileExists(atPath: testDirectoryURL.path)
    {
      try? FileManager.default.removeItem(at: testDirectoryURL)
    }
    app = nil
    testDirectoryURL = nil
    defaultsSuiteName = nil
  }

  private func addItem(_ title: String) {
    let titleField = app.textFields["editor.newItemTitle"]
    XCTAssertTrue(titleField.waitForExistence(timeout: 2))
    titleField.click()
    titleField.typeText(title)
    app.buttons["editor.addItem"].click()
    XCTAssertTrue(
      app.buttons.matching(
        NSPredicate(format: "label CONTAINS %@", title)
      ).firstMatch.waitForExistence(timeout: 2)
    )
  }

  private func openSettings() {
    let settingsTab = app.radioButtons["设置"]
    XCTAssertTrue(settingsTab.waitForExistence(timeout: 2))
    settingsTab.click()
    XCTAssertTrue(
      app.descendants(matching: .any)["settings.category.general"]
        .waitForExistence(timeout: 2)
    )
  }

  private func openSettingsCategory(_ identifier: String) {
    let category =
      app.descendants(matching: .any)["settings.category.\(identifier)"]
    XCTAssertTrue(category.waitForExistence(timeout: 2))
    category.click()
  }

  private func automaticRotationCheckbox() -> XCUIElement {
    app.checkBoxes["settings.autoRotation"]
  }

  private func valueDescription(of element: XCUIElement) -> String {
    String(describing: element.value ?? "")
  }
}
