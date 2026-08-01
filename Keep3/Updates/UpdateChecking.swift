import Foundation

@MainActor
protocol UpdateChecking: AnyObject {
  var canCheckForUpdates: Bool { get }
  var automaticallyChecksForUpdates: Bool { get set }
  var automaticallyDownloadsUpdates: Bool { get set }
  var sendsSystemProfile: Bool { get set }
  var stateDidChange: (() -> Void)? { get set }

  func checkForUpdates()
}

@MainActor
final class InactiveUpdateChecker: UpdateChecking {
  let canCheckForUpdates = false
  var automaticallyChecksForUpdates = false
  var automaticallyDownloadsUpdates = false
  var sendsSystemProfile = false
  var stateDidChange: (() -> Void)?

  func checkForUpdates() {}
}

#if DEBUG
  @MainActor
  final class UpdateUITestFixtureChecker: UpdateChecking {
    private(set) var canCheckForUpdates = true
    var automaticallyChecksForUpdates: Bool {
      get { defaults.bool(forKey: automaticallyChecksKey) }
      set {
        defaults.set(newValue, forKey: automaticallyChecksKey)
        stateDidChange?()
      }
    }
    var automaticallyDownloadsUpdates: Bool {
      get { defaults.bool(forKey: automaticallyDownloadsKey) }
      set {
        defaults.set(newValue, forKey: automaticallyDownloadsKey)
        stateDidChange?()
      }
    }
    var sendsSystemProfile = false
    var stateDidChange: (() -> Void)?
    private let defaults: UserDefaults
    private let automaticallyChecksKey = "SUEnableAutomaticChecks"
    private let automaticallyDownloadsKey = "SUAutomaticallyUpdate"

    init(defaults: UserDefaults) {
      self.defaults = defaults
    }

    func checkForUpdates() {
      canCheckForUpdates = false
      stateDidChange?()
    }
  }
#endif
