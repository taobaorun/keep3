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

    let automaticRotation = automaticRotationCheckbox()
    XCTAssertTrue(automaticRotation.waitForExistence(timeout: 2))
    automaticRotation.click()
    app.radioButtons["点击"].click()

    app.terminate()
    app.launch()

    XCTAssertTrue(app.windows["Keep3"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["editor.item.1"].label.contains("Persistent Focus"))

    openSettings()
    XCTAssertEqual(valueDescription(of: automaticRotationCheckbox()), "0")
    XCTAssertEqual(valueDescription(of: app.radioButtons["点击"]), "1")
  }

  func testOverlayBrowsingOpensTheMatchingEditorItem() throws {
    try launchIsolatedApp()
    defer { cleanUpIsolatedApp() }

    addItem("Alpha")
    addItem("Beta")
    addItem("Gamma")
    openSettings()
    app.radioButtons["点击"].click()
    app.radioButtons["重点"].click()

    let compactSurface = app.buttons["overlay.compact"]
    XCTAssertTrue(compactSurface.waitForExistence(timeout: 3))
    compactSurface.click()

    let nextButton = app.buttons["overlay.next"]
    XCTAssertTrue(nextButton.waitForExistence(timeout: 3))
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
    try launchIsolatedApp(mediaFixture: true)
    defer { cleanUpIsolatedApp() }

    let expandedMedia = app.descendants(matching: .any)["media.expanded"]
    XCTAssertTrue(expandedMedia.waitForExistence(timeout: 4))

    let next = app.buttons["media.action.next"]
    XCTAssertTrue(next.waitForExistence(timeout: 2))
    next.click()
    XCTAssertTrue(next.waitForExistence(timeout: 2))
    XCTAssertTrue(next.isEnabled)

    addItem("Focus Returns")
    openSettings()
    let mediaCategory =
      app.descendants(matching: .any)["settings.category.media"]
    XCTAssertTrue(mediaCategory.waitForExistence(timeout: 2))
    mediaCategory.click()

    let mediaEnabled = app.switches["settings.media.enabled"]
    XCTAssertTrue(mediaEnabled.waitForExistence(timeout: 2))
    mediaEnabled.click()

    XCTAssertTrue(
      app.buttons["overlay.compact"].waitForExistence(timeout: 4)
    )
  }

  private func launchIsolatedApp(mediaFixture: Bool = false) throws {
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
    if mediaFixture {
      app.launchEnvironment["KEEP3_UI_TEST_MEDIA_FIXTURE"] = "playing"
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
      app.descendants(matching: .any)["settings.root"]
        .waitForExistence(timeout: 2)
    )
  }

  private func automaticRotationCheckbox() -> XCUIElement {
    app.switches["settings.autoRotation"]
  }

  private func valueDescription(of element: XCUIElement) -> String {
    String(describing: element.value ?? "")
  }
}
