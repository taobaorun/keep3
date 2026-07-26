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
  static let backgroundOpacityRange = 0.78...1.0

  @Published private(set) var isMediaFirstEnabled: Bool
  @Published private(set) var isQuickPeekEnabled: Bool
  @Published private(set) var quickPeekDuration: TimeInterval
  @Published private(set) var hidesFrontmostSource: Bool
  @Published private(set) var expansionTrigger: SurfaceExpansionTrigger
  @Published private(set) var artworkTreatment: MediaArtworkTreatment
  @Published private(set) var showsWaveform: Bool
  @Published private(set) var showsArtworkFlip: Bool
  @Published private(set) var showsMediaTitleExtras: Bool
  @Published private(set) var secondaryAction: MediaSecondaryAction
  @Published private(set) var backgroundOpacity: Double
  @Published private(set) var suppressedBundleIdentifiers: Set<String>
  @Published private(set) var automationPermissionPosture: AutomationPermissionPosture

  var onChange: (() -> Void)?

  private let defaults: UserDefaults

  private enum Key {
    static let enabled = "mediaFirstEnabled"
    static let quickPeekEnabled = "mediaQuickPeekEnabled"
    static let quickPeekDuration = "mediaQuickPeekDuration"
    static let frontmost = "mediaHideFrontmost"
    static let expansionTrigger = "mediaExpansionTrigger"
    static let artworkTreatment = "mediaArtworkTreatment"
    static let waveform = "mediaShowsWaveform"
    static let artworkFlip = "mediaShowsArtworkFlip"
    static let titleExtras = "mediaShowsTitleExtras"
    static let secondaryAction = "mediaSecondaryAction"
    static let backgroundOpacity = "mediaBackgroundOpacity"
    static let suppressed = "mediaSuppressedSources"
    static let permissionPosture = "mediaAutomationPermissionPosture"
  }

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    isMediaFirstEnabled = defaults.object(forKey: Key.enabled) as? Bool ?? true
    isQuickPeekEnabled =
      defaults.object(forKey: Key.quickPeekEnabled) as? Bool ?? true
    quickPeekDuration =
      (defaults.object(forKey: Key.quickPeekDuration) as? Double ?? 2)
      .clamped(to: Self.quickPeekDurationRange)
    hidesFrontmostSource = defaults.bool(forKey: Key.frontmost)
    expansionTrigger =
      defaults.string(forKey: Key.expansionTrigger)
      .flatMap(SurfaceExpansionTrigger.init(rawValue:)) ?? .hover
    artworkTreatment =
      defaults.string(forKey: Key.artworkTreatment)
      .flatMap(MediaArtworkTreatment.init(rawValue:)) ?? .artwork
    showsWaveform =
      defaults.object(forKey: Key.waveform) as? Bool ?? true
    showsArtworkFlip =
      defaults.object(forKey: Key.artworkFlip) as? Bool ?? false
    showsMediaTitleExtras =
      defaults.object(forKey: Key.titleExtras) as? Bool ?? false
    secondaryAction =
      defaults.string(forKey: Key.secondaryAction)
      .flatMap(MediaSecondaryAction.init(rawValue:)) ?? .none
    backgroundOpacity =
      (defaults.object(forKey: Key.backgroundOpacity) as? Double ?? 0.94)
      .clamped(to: Self.backgroundOpacityRange)
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

  static func live() -> MediaPreferences {
    MediaPreferences(defaults: .standard)
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
      value: value.clamped(to: Self.quickPeekDurationRange),
      key: Key.quickPeekDuration
    )
  }

  func setHidesFrontmostSource(_ value: Bool) {
    update(\.hidesFrontmostSource, value: value, key: Key.frontmost)
  }

  func setExpansionTrigger(_ value: SurfaceExpansionTrigger) {
    update(
      \.expansionTrigger,
      value: value,
      key: Key.expansionTrigger,
      storedValue: value.rawValue
    )
  }

  func setArtworkTreatment(_ value: MediaArtworkTreatment) {
    update(
      \.artworkTreatment,
      value: value,
      key: Key.artworkTreatment,
      storedValue: value.rawValue
    )
  }

  func setShowsWaveform(_ value: Bool) {
    update(\.showsWaveform, value: value, key: Key.waveform)
  }

  func setShowsArtworkFlip(_ value: Bool) {
    update(\.showsArtworkFlip, value: value, key: Key.artworkFlip)
  }

  func setShowsMediaTitleExtras(_ value: Bool) {
    update(\.showsMediaTitleExtras, value: value, key: Key.titleExtras)
  }

  func setSecondaryAction(_ value: MediaSecondaryAction) {
    update(
      \.secondaryAction,
      value: value,
      key: Key.secondaryAction,
      storedValue: value.rawValue
    )
  }

  func setBackgroundOpacity(_ value: Double) {
    update(
      \.backgroundOpacity,
      value: value.clamped(to: Self.backgroundOpacityRange),
      key: Key.backgroundOpacity
    )
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
      guard
        updated.contains(identifier)
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

  var appearance: MediaSurfaceAppearance {
    MediaSurfaceAppearance(
      artworkTreatment: artworkTreatment,
      showsWaveform: showsWaveform,
      showsArtworkFlip: showsArtworkFlip,
      showsMediaTitleExtras: showsMediaTitleExtras,
      secondaryAction: secondaryAction,
      backgroundOpacity: backgroundOpacity
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

  nonisolated static func isPersistableBundleIdentifier(
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
}
