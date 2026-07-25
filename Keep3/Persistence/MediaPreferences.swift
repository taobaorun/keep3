import Foundation

enum AutomationPermissionPosture: String, Equatable, Sendable {
  case notRequested
  case granted
  case denied
}

@MainActor
final class MediaPreferences: ObservableObject {
  static let quickPeekDurationRange = 1.0...5.0
  static let maximumSuppressedSources = 32

  @Published private(set) var isMediaFirstEnabled: Bool
  @Published private(set) var isQuickPeekEnabled: Bool
  @Published private(set) var quickPeekDuration: TimeInterval
  @Published private(set) var hidesFrontmostSource: Bool
  @Published private(set) var suppressedBundleIdentifiers: Set<String>
  @Published private(set) var automationPermissionPosture:
    AutomationPermissionPosture

  var onChange: (() -> Void)?

  private let defaults: UserDefaults

  private enum Key {
    static let enabled = "mediaFirstEnabled"
    static let quickPeekEnabled = "mediaQuickPeekEnabled"
    static let quickPeekDuration = "mediaQuickPeekDuration"
    static let frontmost = "mediaHideFrontmost"
    static let suppressed = "mediaSuppressedSources"
    static let permissionPosture = "mediaAutomationPermissionPosture"
  }

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    isMediaFirstEnabled = defaults.object(forKey: Key.enabled) as? Bool ?? true
    isQuickPeekEnabled =
      defaults.object(forKey: Key.quickPeekEnabled) as? Bool ?? true
    quickPeekDuration = Self.clamp(
      defaults.object(forKey: Key.quickPeekDuration) as? Double ?? 2,
      to: Self.quickPeekDurationRange
    )
    hidesFrontmostSource = defaults.bool(forKey: Key.frontmost)
    suppressedBundleIdentifiers = Set(
      (defaults.stringArray(forKey: Key.suppressed) ?? [])
        .filter(Self.isPersistableBundleIdentifier)
        .sorted()
        .prefix(Self.maximumSuppressedSources)
    )
    automationPermissionPosture =
      defaults.string(forKey: Key.permissionPosture)
      .flatMap(AutomationPermissionPosture.init(rawValue:))
      ?? .notRequested
  }

  func setMediaFirstEnabled(_ value: Bool) {
    update(\.isMediaFirstEnabled, value: value, key: Key.enabled)
  }

  func setQuickPeekEnabled(_ value: Bool) {
    update(\.isQuickPeekEnabled, value: value, key: Key.quickPeekEnabled)
  }

  func setQuickPeekDuration(_ value: TimeInterval) {
    update(
      \.quickPeekDuration,
      value: Self.clamp(value, to: Self.quickPeekDurationRange),
      key: Key.quickPeekDuration
    )
  }

  func setHidesFrontmostSource(_ value: Bool) {
    update(\.hidesFrontmostSource, value: value, key: Key.frontmost)
  }

  @discardableResult
  func setSuppressed(
    _ identifier: String?,
    isSuppressed: Bool
  ) -> Bool {
    guard let identifier,
      Self.isPersistableBundleIdentifier(identifier)
    else {
      return false
    }

    var updated = suppressedBundleIdentifiers
    if isSuppressed {
      guard updated.contains(identifier)
        || updated.count < Self.maximumSuppressedSources
      else {
        return false
      }
      updated.insert(identifier)
    } else {
      guard updated.remove(identifier) != nil else {
        return false
      }
    }
    guard updated != suppressedBundleIdentifiers else {
      return false
    }

    suppressedBundleIdentifiers = updated
    defaults.set(updated.sorted(), forKey: Key.suppressed)
    onChange?()
    return true
  }

  func setAutomationPermissionPosture(
    _ posture: AutomationPermissionPosture
  ) {
    update(
      \.automationPermissionPosture,
      value: posture,
      key: Key.permissionPosture,
      storedValue: posture.rawValue
    )
  }

  var sourcePolicy: MediaSourcePolicy {
    MediaSourcePolicy(
      isMediaFirstEnabled: isMediaFirstEnabled,
      hidesFrontmostSource: hidesFrontmostSource,
      suppressedBundleIdentifiers: suppressedBundleIdentifiers
    )
  }

  private func update<Value: Equatable>(
    _ keyPath: ReferenceWritableKeyPath<MediaPreferences, Value>,
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

  private static func isPersistableBundleIdentifier(
    _ identifier: String
  ) -> Bool {
    guard !identifier.isEmpty, identifier.utf8.count <= 255,
      identifier.contains(".")
    else {
      return false
    }
    return identifier.unicodeScalars.allSatisfy { scalar in
      CharacterSet.alphanumerics.contains(scalar)
        || scalar == "." || scalar == "-"
    }
  }

  private static func clamp<T: Comparable>(
    _ value: T,
    to range: ClosedRange<T>
  ) -> T {
    min(max(value, range.lowerBound), range.upperBound)
  }
}
