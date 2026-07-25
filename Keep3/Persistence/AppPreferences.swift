import Foundation

enum SurfaceExpansionTrigger: String, CaseIterable, Sendable {
  case hover
  case click
}

@MainActor
final class AppPreferences: ObservableObject {
  private enum Key {
    static let isAutomaticRotationEnabled = "isAutomaticRotationEnabled"
    static let currentFocusDuration = "currentFocusDuration"
    static let secondaryDuration = "secondaryDuration"
    static let expansionTrigger = "expansionTrigger"
    static let capsuleWidth = "capsuleWidth"
    static let backgroundOpacity = "backgroundOpacity"
  }

  static let capsuleWidthRange = 240.0...420.0
  static let backgroundOpacityRange = 0.78...1.0

  @Published private(set) var isAutomaticRotationEnabled: Bool
  @Published private(set) var currentFocusDuration: TimeInterval
  @Published private(set) var secondaryDuration: TimeInterval
  @Published private(set) var expansionTrigger: SurfaceExpansionTrigger
  @Published private(set) var capsuleWidth: Double
  @Published private(set) var backgroundOpacity: Double

  var onChange: (() -> Void)?

  private let defaults: UserDefaults

  init(defaults: UserDefaults) {
    self.defaults = defaults
    isAutomaticRotationEnabled =
      defaults.object(forKey: Key.isAutomaticRotationEnabled) as? Bool ?? true
    currentFocusDuration =
      (defaults.object(forKey: Key.currentFocusDuration) as? Double
      ?? RotationDurations.default.currentFocus).clamped(to: RotationDurations.currentFocusRange)
    secondaryDuration =
      (defaults.object(forKey: Key.secondaryDuration) as? Double
      ?? RotationDurations.default.secondary).clamped(to: RotationDurations.secondaryRange)
    expansionTrigger =
      defaults.string(forKey: Key.expansionTrigger)
      .flatMap(SurfaceExpansionTrigger.init(rawValue:)) ?? .hover
    capsuleWidth =
      (defaults.object(forKey: Key.capsuleWidth) as? Double ?? 280)
      .clamped(to: Self.capsuleWidthRange)
    backgroundOpacity =
      (defaults.object(forKey: Key.backgroundOpacity) as? Double ?? 0.94)
      .clamped(to: Self.backgroundOpacityRange)
  }

  static func live() -> AppPreferences {
    AppPreferences(defaults: .standard)
  }

  var rotationDurations: RotationDurations {
    RotationDurations(
      currentFocus: currentFocusDuration,
      secondary: secondaryDuration
    )
  }

  func setAutomaticRotationEnabled(_ value: Bool) {
    update(
      \.isAutomaticRotationEnabled,
      value: value,
      key: Key.isAutomaticRotationEnabled
    )
  }

  func setCurrentFocusDuration(_ value: TimeInterval) {
    update(
      \.currentFocusDuration,
      value: value.clamped(to: RotationDurations.currentFocusRange),
      key: Key.currentFocusDuration
    )
  }

  func setSecondaryDuration(_ value: TimeInterval) {
    update(
      \.secondaryDuration,
      value: value.clamped(to: RotationDurations.secondaryRange),
      key: Key.secondaryDuration
    )
  }

  func setExpansionTrigger(_ value: SurfaceExpansionTrigger) {
    update(
      \.expansionTrigger,
      value: value,
      key: Key.expansionTrigger,
      storedValue: value.rawValue
    )
  }

  func setCapsuleWidth(_ value: Double) {
    update(
      \.capsuleWidth,
      value: value.clamped(to: Self.capsuleWidthRange),
      key: Key.capsuleWidth
    )
  }

  func setBackgroundOpacity(_ value: Double) {
    update(
      \.backgroundOpacity,
      value: value.clamped(to: Self.backgroundOpacityRange),
      key: Key.backgroundOpacity
    )
  }

  private func update<Value: Equatable>(
    _ keyPath: ReferenceWritableKeyPath<AppPreferences, Value>,
    value: Value,
    key: String,
    storedValue: Any? = nil
  ) {
    guard self[keyPath: keyPath] != value else {
      return
    }
    self[keyPath: keyPath] = value
    defaults.set(storedValue ?? value, forKey: key)
    onChange?()
  }
}
