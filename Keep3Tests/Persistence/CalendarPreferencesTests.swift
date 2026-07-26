import XCTest

@testable import Keep3

@MainActor
final class CalendarPreferencesTests: XCTestCase {
  func testCalendarDefaultsOffAndPersistsExplicitChoice() {
    let defaults = makeDefaults()
    let preferences = CalendarPreferences(defaults: defaults)
    var changeCount = 0
    preferences.onChange = { changeCount += 1 }

    XCTAssertFalse(preferences.isEnabled)

    preferences.setEnabled(true)
    preferences.setEnabled(true)

    XCTAssertTrue(preferences.isEnabled)
    XCTAssertEqual(changeCount, 1)
    XCTAssertTrue(CalendarPreferences(defaults: defaults).isEnabled)

    preferences.setEnabled(false)

    XCTAssertFalse(CalendarPreferences(defaults: defaults).isEnabled)
    XCTAssertEqual(changeCount, 2)
  }

  private func makeDefaults() -> UserDefaults {
    let suiteName = "CalendarPreferencesTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
  }
}
