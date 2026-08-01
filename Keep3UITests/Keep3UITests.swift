import XCTest

@MainActor
final class Keep3UITests: XCTestCase {
  private var app: XCUIApplication!
  private var testDirectoryURL: URL!
  private var defaultsSuiteName: String!

  func testEditorSidebarShowsLogoAndBrandNameAtMinimumWindowSize()
    throws
  {
    try launchIsolatedApp()
    defer { cleanUpIsolatedApp() }

    let brandLogo = app.images["editor.brandLogo"]
    XCTAssertTrue(
      brandLogo.waitForExistence(timeout: 2),
      app.debugDescription
    )
    XCTAssertEqual(
      app.images.matching(identifier: "editor.brandLogo").count,
      1
    )
    XCTAssertEqual(brandLogo.label, "Keep3")
    let brandName = app.staticTexts["editor.brandName"]
    XCTAssertTrue(brandName.exists)
    XCTAssertEqual(brandName.label, "Keep3")
    XCTAssertTrue(app.staticTexts["把重要的事留在视线里"].exists)
    let keep3Tab = app.radioButtons["Keep3"]
    XCTAssertTrue(keep3Tab.exists)
    XCTAssertEqual(valueDescription(of: keep3Tab), "1")
    XCTAssertTrue(app.radioButtons["设置"].exists)
    XCTAssertFalse(app.staticTexts["设置"].exists)
    XCTAssertEqual(brandLogo.frame.width, brandLogo.frame.height, accuracy: 1)
    XCTAssertGreaterThan(brandName.frame.minX, brandLogo.frame.maxX)
    XCTAssertEqual(brandName.frame.midY, brandLogo.frame.midY, accuracy: 1)
    let editorWindow = app.windows["Keep3"]
    XCTAssertEqual(editorWindow.frame.width, 720, accuracy: 1)
    XCTAssertTrue(editorWindow.frame.contains(brandLogo.frame))
  }

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

  func testUpdateSettingsAndApplicationCommandUseOfflineFixture() throws {
    try launchIsolatedApp(updateFixture: true)
    defer { cleanUpIsolatedApp() }

    openSettings()

    let manualCheck = app.buttons["settings.updates.checkNow"]
    let automaticChecks =
      app.checkBoxes["settings.updates.automaticChecks"]
    let automaticDownloads =
      app.checkBoxes["settings.updates.automaticDownloads"]
    XCTAssertTrue(manualCheck.waitForExistence(timeout: 2))
    XCTAssertEqual(valueDescription(of: automaticChecks), "0")
    XCTAssertEqual(valueDescription(of: automaticDownloads), "0")
    XCTAssertFalse(automaticDownloads.isEnabled)

    automaticChecks.click()
    XCTAssertTrue(automaticDownloads.isEnabled)
    automaticDownloads.click()
    XCTAssertEqual(valueDescription(of: automaticChecks), "1")
    XCTAssertEqual(valueDescription(of: automaticDownloads), "1")

    automaticChecks.click()
    XCTAssertEqual(valueDescription(of: automaticChecks), "0")
    XCTAssertEqual(valueDescription(of: automaticDownloads), "0")
    XCTAssertFalse(automaticDownloads.isEnabled)

    app.menuBars.menuBarItems["Keep3"].click()
    let updateCommand = app.menuItems["检查更新…"]
    XCTAssertTrue(updateCommand.waitForExistence(timeout: 2))
    XCTAssertTrue(updateCommand.isEnabled)
    app.typeKey(.escape, modifierFlags: [])

    automaticChecks.click()
    automaticDownloads.click()
    app.terminate()
    app.launch()

    XCTAssertTrue(app.windows["Keep3"].waitForExistence(timeout: 5))
    openSettings()
    XCTAssertEqual(
      valueDescription(
        of: app.checkBoxes["settings.updates.automaticChecks"]
      ),
      "1"
    )
    XCTAssertEqual(
      valueDescription(
        of: app.checkBoxes["settings.updates.automaticDownloads"]
      ),
      "1"
    )
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

  func testExpandedPrioritiesKeep3ActionSelectsKeep3Tab() throws {
    try launchIsolatedApp(expandedSurface: true)
    defer { cleanUpIsolatedApp() }

    addItem("Alpha")
    addItem("Beta")

    let nextButton = app.buttons["overlay.next"]
    XCTAssertTrue(nextButton.waitForExistence(timeout: 3))
    nextButton.click()

    openSettings()

    let keep3Button = app.buttons["overlay.keep3"]
    XCTAssertTrue(
      keep3Button.waitForExistence(timeout: 2),
      app.debugDescription
    )
    XCTAssertEqual(keep3Button.label, "Keep3")
    XCTAssertGreaterThan(keep3Button.frame.width, keep3Button.frame.height)
    keep3Button.click()

    XCTAssertEqual(valueDescription(of: app.radioButtons["Keep3"]), "1")
    let titleField = app.textFields["editor.title"]
    XCTAssertTrue(titleField.waitForExistence(timeout: 3))
    XCTAssertEqual(titleField.value as? String, "Beta")
    XCTAssertTrue(app.buttons["editor.item.1"].label.contains("当前重点"))
    XCTAssertTrue(app.buttons["editor.item.1"].label.contains("Alpha"))
  }

  func testExpandedPrioritiesKeep3ActionRemainsCenteredForItemCounts()
    throws
  {
    try launchIsolatedApp(expandedSurface: true)
    defer { cleanUpIsolatedApp() }

    addItem("Alpha")

    let keep3Button = app.buttons["overlay.keep3"]
    XCTAssertTrue(keep3Button.waitForExistence(timeout: 3))
    XCTAssertFalse(app.buttons["overlay.previous"].exists)
    XCTAssertFalse(app.buttons["overlay.next"].exists)
    let oneItemKeep3MidX = keep3Button.frame.midX

    addItem("Beta")

    let previousButton = app.buttons["overlay.previous"]
    let nextButton = app.buttons["overlay.next"]
    XCTAssertTrue(previousButton.waitForExistence(timeout: 3))
    XCTAssertTrue(nextButton.waitForExistence(timeout: 3))
    XCTAssertEqual(keep3Button.frame.midX, oneItemKeep3MidX, accuracy: 1)
    XCTAssertEqual(
      keep3Button.frame.midX - previousButton.frame.midX,
      nextButton.frame.midX - keep3Button.frame.midX,
      accuracy: 1
    )
  }

  func testCompactPrioritiesDoesNotExposeKeep3Action() throws {
    try launchIsolatedApp(surfaceLevel: "compact")
    defer { cleanUpIsolatedApp() }

    addItem("Compact Focus")

    XCTAssertTrue(
      app.buttons["overlay.compact"].waitForExistence(timeout: 3)
    )
    XCTAssertFalse(app.buttons["overlay.keep3"].exists)
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
    XCTAssertFalse(app.buttons["overlay.keep3"].exists)
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
    XCTAssertFalse(app.buttons["overlay.keep3"].exists)

    app.radioButtons["Keep3"].click()
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
    updateFixture: Bool = false,
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
    app.launchEnvironment["KEEP3_UI_TEST_UPDATE_FIXTURE"] =
      updateFixture.description
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
