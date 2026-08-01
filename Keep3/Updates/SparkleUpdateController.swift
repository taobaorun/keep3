import Combine
import Foundation
import Sparkle

enum UpdateCheckStatus: Equatable {
  case ready
  case checking
  case unavailable

  var message: String {
    switch self {
    case .ready:
      "可以检查更新"
    case .checking:
      "正在检查更新…"
    case .unavailable:
      "暂时无法检查更新"
    }
  }
}

@MainActor
final class SparkleUpdateController: ObservableObject {
  @Published private(set) var canCheckForUpdates: Bool
  @Published private(set) var automaticallyChecksForUpdates: Bool
  @Published private(set) var automaticallyDownloadsUpdates: Bool
  @Published private(set) var status: UpdateCheckStatus

  private let checker: any UpdateChecking

  init(checker: any UpdateChecking) {
    self.checker = checker
    canCheckForUpdates = checker.canCheckForUpdates
    automaticallyChecksForUpdates = checker.automaticallyChecksForUpdates
    automaticallyDownloadsUpdates = checker.automaticallyDownloadsUpdates
    status = checker.canCheckForUpdates ? .ready : .unavailable

    if checker.sendsSystemProfile {
      checker.sendsSystemProfile = false
    }
    checker.stateDidChange = { [weak self] in
      self?.synchronizeFromChecker()
    }
  }

  static func inactive() -> SparkleUpdateController {
    SparkleUpdateController(checker: InactiveUpdateChecker())
  }

  static func live() -> SparkleUpdateController {
    SparkleUpdateController(checker: SparkleUpdateChecker())
  }

  func checkForUpdates() {
    guard canCheckForUpdates, status != .checking else {
      return
    }
    canCheckForUpdates = false
    status = .checking
    checker.checkForUpdates()
  }

  func setAutomaticallyChecksForUpdates(_ isEnabled: Bool) {
    if !isEnabled && checker.automaticallyDownloadsUpdates {
      checker.automaticallyDownloadsUpdates = false
    }
    if checker.automaticallyChecksForUpdates != isEnabled {
      checker.automaticallyChecksForUpdates = isEnabled
    }
    synchronizeFromChecker()
  }

  func setAutomaticallyDownloadsUpdates(_ isEnabled: Bool) {
    if isEnabled && !checker.automaticallyChecksForUpdates {
      checker.automaticallyChecksForUpdates = true
    }
    if checker.automaticallyDownloadsUpdates != isEnabled {
      checker.automaticallyDownloadsUpdates = isEnabled
    }
    synchronizeFromChecker()
  }

  private func synchronizeFromChecker() {
    let wasAvailable = canCheckForUpdates
    let nextCanCheckForUpdates = checker.canCheckForUpdates
    let nextAutomaticallyChecks = checker.automaticallyChecksForUpdates
    let nextAutomaticallyDownloads = checker.automaticallyDownloadsUpdates
    let nextStatus: UpdateCheckStatus
    if nextCanCheckForUpdates {
      nextStatus = .ready
    } else if wasAvailable {
      nextStatus = .checking
    } else {
      nextStatus = status
    }

    guard
      nextCanCheckForUpdates != canCheckForUpdates
        || nextAutomaticallyChecks != automaticallyChecksForUpdates
        || nextAutomaticallyDownloads != automaticallyDownloadsUpdates
        || nextStatus != status
    else {
      return
    }

    canCheckForUpdates = nextCanCheckForUpdates
    automaticallyChecksForUpdates = nextAutomaticallyChecks
    automaticallyDownloadsUpdates = nextAutomaticallyDownloads
    status = nextStatus
  }
}

@MainActor
private final class SparkleUpdateChecker: UpdateChecking {
  private let standardController: SPUStandardUpdaterController
  private var observations: [NSKeyValueObservation] = []

  var canCheckForUpdates: Bool {
    standardController.updater.canCheckForUpdates
  }

  var automaticallyChecksForUpdates: Bool {
    get { standardController.updater.automaticallyChecksForUpdates }
    set { standardController.updater.automaticallyChecksForUpdates = newValue }
  }

  var automaticallyDownloadsUpdates: Bool {
    get { standardController.updater.automaticallyDownloadsUpdates }
    set {
      standardController.updater.automaticallyDownloadsUpdates = newValue
    }
  }

  var sendsSystemProfile: Bool {
    get { standardController.updater.sendsSystemProfile }
    set { standardController.updater.sendsSystemProfile = newValue }
  }

  var stateDidChange: (() -> Void)?

  init() {
    standardController = SPUStandardUpdaterController(
      startingUpdater: true,
      updaterDelegate: nil,
      userDriverDelegate: nil
    )
    _ = standardController.updater.clearFeedURLFromUserDefaults()

    let updater = standardController.updater
    observations = [
      updater.observe(\.canCheckForUpdates, options: [.new]) {
        [weak self] _, _ in
        MainActor.assumeIsolated {
          self?.stateDidChange?()
        }
      },
      updater.observe(\.automaticallyChecksForUpdates, options: [.new]) {
        [weak self] _, _ in
        MainActor.assumeIsolated {
          self?.stateDidChange?()
        }
      },
      updater.observe(\.automaticallyDownloadsUpdates, options: [.new]) {
        [weak self] _, _ in
        MainActor.assumeIsolated {
          self?.stateDidChange?()
        }
      },
    ]
  }

  func checkForUpdates() {
    standardController.checkForUpdates(nil)
  }
}
