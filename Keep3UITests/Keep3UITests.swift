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

  func testExpandedPrioritiesSettingsPreservesFocusAndEditorRoute() throws {
    try launchIsolatedApp(expandedSurface: true)
    defer { cleanUpIsolatedApp() }

    addItem("Alpha")
    addItem("Beta")

    let nextButton = app.buttons["overlay.next"]
    XCTAssertTrue(nextButton.waitForExistence(timeout: 3))
    nextButton.click()

    let settingsButton = app.buttons["overlay.settings"]
    XCTAssertTrue(
      settingsButton.waitForExistence(timeout: 2),
      app.debugDescription
    )
    XCTAssertEqual(settingsButton.label, "设置")
    settingsButton.click()

    XCTAssertTrue(
      app.descendants(matching: .any)["settings.category.general"]
        .waitForExistence(timeout: 3)
    )

    let openItem = app.buttons["overlay.openItem"]
    XCTAssertTrue(openItem.waitForExistence(timeout: 2))
    XCTAssertTrue(openItem.label.contains("Beta"))
    openItem.click()

    let titleField = app.textFields["editor.title"]
    XCTAssertTrue(titleField.waitForExistence(timeout: 3))
    XCTAssertEqual(titleField.value as? String, "Beta")
    XCTAssertTrue(app.buttons["editor.item.1"].label.contains("当前重点"))
    XCTAssertTrue(app.buttons["editor.item.1"].label.contains("Alpha"))
  }

  func testExpandedPrioritiesSettingsRemainsCenteredForOneAndMultipleItems()
    throws
  {
    try launchIsolatedApp(expandedSurface: true)
    defer { cleanUpIsolatedApp() }

    addItem("Alpha")

    let settingsButton = app.buttons["overlay.settings"]
    XCTAssertTrue(settingsButton.waitForExistence(timeout: 3))
    XCTAssertFalse(app.buttons["overlay.previous"].exists)
    XCTAssertFalse(app.buttons["overlay.next"].exists)
    let oneItemSettingsMidX = settingsButton.frame.midX

    addItem("Beta")

    let previousButton = app.buttons["overlay.previous"]
    let nextButton = app.buttons["overlay.next"]
    XCTAssertTrue(previousButton.waitForExistence(timeout: 3))
    XCTAssertTrue(nextButton.waitForExistence(timeout: 3))
    XCTAssertEqual(settingsButton.frame.midX, oneItemSettingsMidX, accuracy: 1)
    XCTAssertEqual(
      settingsButton.frame.midX - previousButton.frame.midX,
      nextButton.frame.midX - settingsButton.frame.midX,
      accuracy: 1
    )
  }

  func testCompactPrioritiesDoesNotExposeSettingsAction() throws {
    try launchIsolatedApp(surfaceLevel: "compact")
    defer { cleanUpIsolatedApp() }

    addItem("Compact Focus")

    XCTAssertTrue(
      app.buttons["overlay.compact"].waitForExistence(timeout: 3)
    )
    XCTAssertFalse(app.buttons["overlay.settings"].exists)
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
    XCTAssertFalse(app.buttons["overlay.settings"].exists)
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

    let compactFocus = app.buttons["overlay.compact"]
    XCTAssertTrue(compactFocus.waitForExistence(timeout: 4))
    XCTAssertTrue(compactFocus.label.contains("Focus Returns"))
  }

  func testCalendarFixtureOwnsSurfaceAndDisablingRestoresFocus() throws {
    try launchIsolatedApp(
      expandedSurface: true,
      calendarFixture: true
    )
    defer { cleanUpIsolatedApp() }

    openSettings()
    openSettingsCategory("calendar")
    var calendarEnabled =
      app.checkBoxes["settings.calendar.enabled"]
    XCTAssertTrue(calendarEnabled.waitForExistence(timeout: 2))
    calendarEnabled.click()

    let expandedCalendarEvent =
      app.descendants(matching: .any)
      .matching(
        NSPredicate(
          format: "identifier == %@ AND label CONTAINS %@",
          "calendar.expanded",
          "UI Fixture Event"
        )
      )
      .firstMatch
    XCTAssertTrue(
      expandedCalendarEvent.waitForExistence(timeout: 4),
      app.debugDescription
    )
    XCTAssertFalse(app.buttons["overlay.settings"].exists)

    app.radioButtons["重点"].click()
    addItem("Calendar Fallback")
    openSettings()
    openSettingsCategory("calendar")
    calendarEnabled = app.checkBoxes["settings.calendar.enabled"]
    XCTAssertTrue(calendarEnabled.waitForExistence(timeout: 2))
    calendarEnabled.click()

    XCTAssertTrue(
      app.buttons["overlay.openItem"].waitForExistence(timeout: 4)
    )
    XCTAssertTrue(
      app.buttons["overlay.openItem"].label.contains("Calendar Fallback")
    )
  }

  func testRotationResumesAfterPausingMedia() throws {
    try launchIsolatedApp(
      mediaFixture: true,
      surfaceLevel: "compact"
    )
    defer { cleanUpIsolatedApp() }

    addItem("Rotation Current")
    addItem("Rotation Secondary")
    let compactMedia = app.buttons["media.compact"]
    XCTAssertTrue(compactMedia.waitForExistence(timeout: 4))
    compactMedia.click()

    let pause =
      app.descendants(matching: .any)["media.action.playPause"]
    XCTAssertTrue(pause.waitForExistence(timeout: 4))
    pause.click()
    app.windows["Keep3"]
      .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
      .hover()

    let compactFocus = app.buttons["overlay.compact"]
    XCTAssertTrue(compactFocus.waitForExistence(timeout: 4))
    XCTAssertTrue(compactFocus.label.contains("Rotation Current"))

    let rotated = expectation(
      for: NSPredicate(
        format: "label CONTAINS %@",
        "Rotation Secondary"
      ),
      evaluatedWith: compactFocus
    )
    wait(for: [rotated], timeout: 32)
  }

  private func launchIsolatedApp(
    mediaFixture: Bool = false,
    expandedSurface: Bool = false,
    calendarFixture: Bool = false,
    surfaceLevel: String? = nil
  ) throws {
    continueAfterFailure = false

    let identifier = UUID().uuidString
    testDirectoryURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("Keep3UITests-\(identifier)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: testDirectoryURL,
      withIntermediateDirectories: true
    )
    let stateFileURL =
      testDirectoryURL.appendingPathComponent("state.json")
    defaultsSuiteName = "Keep3UITests.\(identifier)"

    app = XCUIApplication()
    app.launchEnvironment["KEEP3_UI_TEST_STATE_PATH"] =
      stateFileURL.path
    app.launchEnvironment["KEEP3_UI_TEST_DEFAULTS_SUITE"] = defaultsSuiteName
    app.launchEnvironment["KEEP3_UI_TEST_MEDIA_ENABLED"] =
      mediaFixture.description
    if mediaFixture {
      app.launchEnvironment["KEEP3_UI_TEST_MEDIA_FIXTURE"] = "playing"
    }
    app.launchEnvironment["KEEP3_UI_TEST_CALENDAR_ENABLED"] =
      false.description
    if calendarFixture {
      app.launchEnvironment["KEEP3_UI_TEST_CALENDAR_FIXTURE"] = "authorized"
    }
    if let surfaceLevel {
      app.launchEnvironment["KEEP3_UI_TEST_SURFACE_LEVEL"] = surfaceLevel
    } else if expandedSurface {
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
