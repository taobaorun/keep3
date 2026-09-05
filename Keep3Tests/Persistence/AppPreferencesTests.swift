import XCTest

@testable import Keep3

@MainActor
final class AppPreferencesTests: XCTestCase {
  func testDefaultsMatchProductDecisions() {
    let (defaults, suiteName) = makeDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let preferences = AppPreferences(defaults: defaults)

    XCTAssertTrue(preferences.isAutomaticRotationEnabled)
    XCTAssertEqual(preferences.currentFocusDuration, 30)
    XCTAssertEqual(preferences.secondaryDuration, 8)
    XCTAssertEqual(preferences.expansionTrigger, .hover)
    XCTAssertEqual(preferences.capsuleWidth, 280)
    XCTAssertEqual(preferences.backgroundOpacity, 0.94)
    XCTAssertEqual(preferences.itemSwitchEffect, .instant)
  }

  func testBehaviorValuesClampPersistAndEmitOneChangeEach() {
    let (defaults, suiteName) = makeDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let preferences = AppPreferences(defaults: defaults)
    var changeCount = 0
    preferences.onChange = { changeCount += 1 }

    preferences.setAutomaticRotationEnabled(false)
    preferences.setCurrentFocusDuration(999)
    preferences.setSecondaryDuration(99)
    preferences.setExpansionTrigger(.click)
    preferences.setItemSwitchEffect(.cardFlip)

    XCTAssertFalse(preferences.isAutomaticRotationEnabled)
    XCTAssertEqual(preferences.currentFocusDuration, 600)
    XCTAssertEqual(preferences.secondaryDuration, 30)
    XCTAssertEqual(preferences.expansionTrigger, .click)
    XCTAssertEqual(preferences.itemSwitchEffect, .cardFlip)
    XCTAssertEqual(changeCount, 5)

    let reloaded = AppPreferences(defaults: defaults)
    XCTAssertFalse(reloaded.isAutomaticRotationEnabled)
    XCTAssertEqual(reloaded.currentFocusDuration, 600)
    XCTAssertEqual(reloaded.secondaryDuration, 30)
    XCTAssertEqual(reloaded.expansionTrigger, .click)
    XCTAssertEqual(reloaded.itemSwitchEffect, .cardFlip)
  }

  func testAppearanceValuesClampAndPersist() {
    let (defaults, suiteName) = makeDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let preferences = AppPreferences(defaults: defaults)

    preferences.setCapsuleWidth(100)
    preferences.setBackgroundOpacity(0.1)

    let reloaded = AppPreferences(defaults: defaults)
    XCTAssertEqual(reloaded.capsuleWidth, 240)
    XCTAssertEqual(reloaded.backgroundOpacity, 0.78)
  }

  func testInvalidStoredEnumsFallBackWithoutChangingOtherValues() {
    let (defaults, suiteName) = makeDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.set("unknown-trigger", forKey: "expansionTrigger")
    defaults.set("carousel", forKey: "itemSwitchEffect")
    defaults.set(360, forKey: "capsuleWidth")

    let preferences = AppPreferences(defaults: defaults)

    XCTAssertEqual(preferences.expansionTrigger, .hover)
    XCTAssertEqual(preferences.itemSwitchEffect, .instant)
    XCTAssertEqual(preferences.capsuleWidth, 360)
  }

  func testSurfaceAppearanceKeepsConfiguredOpacityAndSwitchEffect() {
    let appearance = SurfaceAppearance(
      backgroundOpacity: 0.78,
      itemSwitchEffect: .cardFlip
    )
    XCTAssertEqual(appearance.backgroundOpacity, 0.78)
    XCTAssertEqual(appearance.itemSwitchEffect, .cardFlip)
  }

  func testItemSwitchTransitionOnlyRunsCardFlipInCompactLevel() {
    XCTAssertEqual(
      FocusItemSwitchTransition.resolve(
        effect: .instant,
        level: .compact,
        reduceMotion: false
      ),
      .instant
    )
    XCTAssertEqual(
      FocusItemSwitchTransition.resolve(
        effect: .cardFlip,
        level: .compact,
        reduceMotion: false
      ),
      .cardFlip(duration: 0.22)
    )
    XCTAssertEqual(
      FocusItemSwitchTransition.resolve(
        effect: .cardFlip,
        level: .compact,
        reduceMotion: true
      ),
      .crossfade(duration: 0.12)
    )
    XCTAssertEqual(
      FocusItemSwitchTransition.resolve(
        effect: .cardFlip,
        level: .expanded,
        reduceMotion: false
      ),
      .instant
    )
    XCTAssertEqual(
      FocusItemSwitchTransition.resolve(
        effect: .cardFlip,
        level: .hardware,
        reduceMotion: false
      ),
      .instant
    )
    XCTAssertEqual(
      FocusItemSwitchTransition.resolve(
        effect: .cardFlip,
        level: .compact,
        reduceMotion: false,
        keyboardNavigationActive: true
      ),
      .instant
    )
  }

  func testSettingsCategoriesPreserveVisualOrderAndExposeEventEntries() {
    XCTAssertEqual(
      SettingsCategory.allCases,
      [
        .general,
        .focusSurface,
        .rotation,
        .interaction,
        .accessibility,
        .media,
        .calendar,
      ]
    )
  }

  private func makeDefaults() -> (UserDefaults, String) {
    let suiteName = "Keep3Tests.AppPreferences.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return (defaults, suiteName)
  }
}
