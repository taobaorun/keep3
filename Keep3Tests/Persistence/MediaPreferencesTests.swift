import XCTest

@testable import Keep3

@MainActor
final class MediaPreferencesTests: XCTestCase {
  func testMediaFirstDefaultsOnAndSuppressionIsReversible() {
    let defaults = makeDefaults()
    let preferences = MediaPreferences(defaults: defaults)

    XCTAssertTrue(preferences.isMediaFirstEnabled)
    XCTAssertTrue(preferences.isQuickPeekEnabled)
    XCTAssertEqual(preferences.quickPeekDuration, 2)
    XCTAssertFalse(preferences.hidesFrontmostSource)
    XCTAssertEqual(preferences.expansionTrigger, .hover)
    XCTAssertEqual(preferences.artworkTreatment, .artwork)
    XCTAssertTrue(preferences.showsWaveform)
    XCTAssertFalse(preferences.showsArtworkFlip)
    XCTAssertFalse(preferences.showsMediaTitleExtras)
    XCTAssertEqual(preferences.secondaryAction, .none)
    XCTAssertEqual(preferences.backgroundOpacity, 0.94)
    XCTAssertEqual(preferences.automationPermissionPosture, .notRequested)

    XCTAssertTrue(
      preferences.setSuppressed(
        "com.spotify.client",
        isSuppressed: true
      )
    )
    XCTAssertTrue(
      preferences.suppressedBundleIdentifiers.contains("com.spotify.client")
    )

    XCTAssertTrue(
      preferences.setSuppressed(
        "com.spotify.client",
        isSuppressed: false
      )
    )
    XCTAssertFalse(
      preferences.suppressedBundleIdentifiers.contains("com.spotify.client")
    )
  }

  func testAppearanceSettingsPersistAndOpacityIsBounded() {
    let defaults = makeDefaults()
    let preferences = MediaPreferences(defaults: defaults)

    preferences.setExpansionTrigger(.click)
    preferences.setArtworkTreatment(.monochrome)
    preferences.setShowsWaveform(false)
    preferences.setShowsArtworkFlip(true)
    preferences.setShowsMediaTitleExtras(true)
    preferences.setSecondaryAction(.repeatOne)
    preferences.setBackgroundOpacity(9)

    let relaunched = MediaPreferences(defaults: defaults)
    XCTAssertEqual(relaunched.expansionTrigger, .click)
    XCTAssertEqual(relaunched.artworkTreatment, .monochrome)
    XCTAssertFalse(relaunched.showsWaveform)
    XCTAssertTrue(relaunched.showsArtworkFlip)
    XCTAssertTrue(relaunched.showsMediaTitleExtras)
    XCTAssertEqual(relaunched.secondaryAction, .repeatOne)
    XCTAssertEqual(
      relaunched.backgroundOpacity,
      MediaPreferences.backgroundOpacityRange.upperBound
    )
    XCTAssertEqual(
      relaunched.appearance,
      MediaSurfaceAppearance(
        artworkTreatment: .monochrome,
        showsWaveform: false,
        showsArtworkFlip: true,
        showsMediaTitleExtras: true,
        secondaryAction: .repeatOne,
        backgroundOpacity: 1
      )
    )
  }

  func testQuickPeekDurationIsClampedOnReadAndWrite() {
    let defaults = makeDefaults()
    defaults.set(99.0, forKey: "mediaQuickPeekDuration")
    let preferences = MediaPreferences(defaults: defaults)

    XCTAssertEqual(preferences.quickPeekDuration, 5)

    preferences.setQuickPeekDuration(-4)

    XCTAssertEqual(preferences.quickPeekDuration, 1)
    XCTAssertEqual(defaults.double(forKey: "mediaQuickPeekDuration"), 1)
  }

  func testStoredSuppressionIsBoundedValidatedAndPersistsPermissionPosture() {
    let defaults = makeDefaults()
    defaults.set(
      ["", "invalid value"] + (0..<40).map { "com.example.player\($0)" },
      forKey: "mediaSuppressedSources"
    )
    defaults.set("future-value", forKey: "mediaAutomationPermissionPosture")

    let preferences = MediaPreferences(defaults: defaults)

    XCTAssertEqual(preferences.suppressedBundleIdentifiers.count, 32)
    XCTAssertFalse(
      preferences.setSuppressed("", isSuppressed: true)
    )
    XCTAssertEqual(preferences.automationPermissionPosture, .notRequested)

    preferences.setAutomationPermissionPosture(.denied)
    let relaunched = MediaPreferences(defaults: defaults)

    XCTAssertEqual(relaunched.automationPermissionPosture, .denied)
    XCTAssertEqual(
      relaunched.suppressedBundleIdentifiers,
      preferences.suppressedBundleIdentifiers
    )
  }

  private func makeDefaults() -> UserDefaults {
    let suiteName = "MediaPreferencesTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
  }
}
