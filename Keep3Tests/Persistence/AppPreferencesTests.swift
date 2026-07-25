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
    XCTAssertEqual(preferences.motionPreset, .fade)
    XCTAssertEqual(preferences.motionSpeed, 1)
    XCTAssertEqual(preferences.capsuleWidth, 280)
    XCTAssertEqual(preferences.backgroundOpacity, 0.94)
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

    XCTAssertFalse(preferences.isAutomaticRotationEnabled)
    XCTAssertEqual(preferences.currentFocusDuration, 600)
    XCTAssertEqual(preferences.secondaryDuration, 30)
    XCTAssertEqual(preferences.expansionTrigger, .click)
    XCTAssertEqual(changeCount, 4)

    let reloaded = AppPreferences(defaults: defaults)
    XCTAssertFalse(reloaded.isAutomaticRotationEnabled)
    XCTAssertEqual(reloaded.currentFocusDuration, 600)
    XCTAssertEqual(reloaded.secondaryDuration, 30)
    XCTAssertEqual(reloaded.expansionTrigger, .click)
  }

  func testAppearanceValuesClampAndPersist() {
    let (defaults, suiteName) = makeDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let preferences = AppPreferences(defaults: defaults)

    preferences.setMotionPreset(.slide)
    preferences.setMotionSpeed(4)
    preferences.setCapsuleWidth(100)
    preferences.setBackgroundOpacity(0.1)

    let reloaded = AppPreferences(defaults: defaults)
    XCTAssertEqual(reloaded.motionPreset, .slide)
    XCTAssertEqual(reloaded.motionSpeed, 2)
    XCTAssertEqual(reloaded.capsuleWidth, 240)
    XCTAssertEqual(reloaded.backgroundOpacity, 0.78)
  }

  func testInvalidStoredEnumsFallBackWithoutChangingOtherValues() {
    let (defaults, suiteName) = makeDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.set("unknown-trigger", forKey: "expansionTrigger")
    defaults.set("unknown-motion", forKey: "motionPreset")
    defaults.set(360, forKey: "capsuleWidth")

    let preferences = AppPreferences(defaults: defaults)

    XCTAssertEqual(preferences.expansionTrigger, .hover)
    XCTAssertEqual(preferences.motionPreset, .fade)
    XCTAssertEqual(preferences.capsuleWidth, 360)
  }

  func testSystemAccessibilitySettingsOverrideCustomAppearance() {
    let appearance = SurfaceAppearance(
      motionPreset: .slide,
      motionSpeed: 2,
      backgroundOpacity: 0.78
    )

    let ordinary = appearance.resolved(
      reduceMotion: false,
      reduceTransparency: false
    )
    XCTAssertEqual(ordinary.motionPreset, .slide)
    XCTAssertEqual(ordinary.animationDuration, 0.225)
    XCTAssertEqual(ordinary.backgroundOpacity, 0.78)

    let accessible = appearance.resolved(
      reduceMotion: true,
      reduceTransparency: true
    )
    XCTAssertNil(accessible.motionPreset)
    XCTAssertEqual(accessible.animationDuration, 0.12)
    XCTAssertEqual(accessible.backgroundOpacity, 1)
  }

  private func makeDefaults() -> (UserDefaults, String) {
    let suiteName = "Keep3Tests.AppPreferences.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return (defaults, suiteName)
  }
}
