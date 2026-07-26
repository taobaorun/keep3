import Foundation

@MainActor
final class CalendarPreferences: ObservableObject {
  @Published private(set) var isEnabled: Bool

  var onChange: (() -> Void)?

  private static let enabledKey = "calendarSurfaceEnabled"
  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    isEnabled = defaults.bool(forKey: Self.enabledKey)
  }

  static func live() -> CalendarPreferences {
    CalendarPreferences()
  }

  func setEnabled(_ isEnabled: Bool) {
    guard self.isEnabled != isEnabled else {
      return
    }
    self.isEnabled = isEnabled
    defaults.set(isEnabled, forKey: Self.enabledKey)
    onChange?()
  }
}
