import Sparkle
import XCTest

@testable import Keep3

@MainActor
final class SparkleUpdateControllerTests: XCTestCase {
  func testManualCheckStartsOnceAndPreventsOverlap() {
    let checker = FakeUpdateChecker()
    let controller = SparkleUpdateController(checker: checker)

    controller.checkForUpdates()
    controller.checkForUpdates()

    XCTAssertEqual(checker.checkCount, 1)
    XCTAssertFalse(controller.canCheckForUpdates)
    XCTAssertEqual(controller.status, .checking)
  }

  func testCompletedCheckRestoresAvailability() {
    let checker = FakeUpdateChecker()
    let controller = SparkleUpdateController(checker: checker)

    controller.checkForUpdates()
    checker.completeCheck()

    XCTAssertTrue(controller.canCheckForUpdates)
    XCTAssertEqual(controller.status, .ready)
  }

  func testUnavailableCheckerDoesNotStartManualCheck() {
    let checker = FakeUpdateChecker(canCheckForUpdates: false)
    let controller = SparkleUpdateController(checker: checker)

    controller.checkForUpdates()

    XCTAssertEqual(checker.checkCount, 0)
    XCTAssertEqual(controller.status, .unavailable)
  }

  func testEnablingAutomaticDownloadEnablesCheckingFirst() {
    let checker = FakeUpdateChecker()
    let controller = SparkleUpdateController(checker: checker)

    controller.setAutomaticallyDownloadsUpdates(true)

    XCTAssertEqual(
      checker.preferenceChanges,
      [.automaticallyChecks(true), .automaticallyDownloads(true)]
    )
    XCTAssertTrue(controller.automaticallyChecksForUpdates)
    XCTAssertTrue(controller.automaticallyDownloadsUpdates)
  }

  func testDisablingAutomaticCheckingClearsDownloadFirst() {
    let checker = FakeUpdateChecker(
      automaticallyChecksForUpdates: true,
      automaticallyDownloadsUpdates: true
    )
    let controller = SparkleUpdateController(checker: checker)

    controller.setAutomaticallyChecksForUpdates(false)

    XCTAssertEqual(
      checker.preferenceChanges,
      [.automaticallyDownloads(false), .automaticallyChecks(false)]
    )
    XCTAssertFalse(controller.automaticallyChecksForUpdates)
    XCTAssertFalse(controller.automaticallyDownloadsUpdates)
  }

  func testValidAutomaticPreferencesSurviveControllerRecreation() {
    let checker = FakeUpdateChecker()
    let firstController = SparkleUpdateController(checker: checker)

    firstController.setAutomaticallyChecksForUpdates(true)
    firstController.setAutomaticallyDownloadsUpdates(true)
    let recreatedController = SparkleUpdateController(checker: checker)

    XCTAssertTrue(recreatedController.automaticallyChecksForUpdates)
    XCTAssertTrue(recreatedController.automaticallyDownloadsUpdates)
  }

  func testControllerDisablesUnexpectedSystemProfiling() {
    let checker = FakeUpdateChecker(sendsSystemProfile: true)

    _ = SparkleUpdateController(checker: checker)

    XCTAssertFalse(checker.sendsSystemProfile)
  }

  func testSparkleVersionComparatorOnlyAdvancesToHigherBuilds() {
    let comparator = SUStandardVersionComparator.default

    XCTAssertEqual(
      comparator.compareVersion("1", toVersion: "1"),
      .orderedSame
    )
    XCTAssertEqual(
      comparator.compareVersion("1", toVersion: "2"),
      .orderedAscending
    )
    XCTAssertEqual(
      comparator.compareVersion("2", toVersion: "1"),
      .orderedDescending
    )
  }

  func testBuiltUpdaterConfigurationIsOptInAndPrivacyBounded() throws {
    let info = try XCTUnwrap(Bundle.main.infoDictionary)

    XCTAssertEqual(
      info["SUFeedURL"] as? String,
      "https://taobaorun.github.io/keep3/release-channel/appcast.xml"
    )
    XCTAssertEqual(info["SUEnableAutomaticChecks"] as? Bool, false)
    XCTAssertEqual(info["SUAutomaticallyUpdate"] as? Bool, false)
    XCTAssertEqual(info["SUEnableSystemProfiling"] as? Bool, false)
    XCTAssertEqual(info["SUVerifyUpdateBeforeExtraction"] as? Bool, true)
    XCTAssertEqual(info["SURequireSignedFeed"] as? Bool, true)
    XCTAssertEqual(
      info["SUPublicEDKey"] as? String,
      "eRFPLZuNM6m8bltmtpPX4fzKbufI1z6rKJHtgIIsllk="
    )
  }

  func testUpdateBoundaryAddsNoContentOrAnalyticsPayload() throws {
    let implementation = try source(at: "Keep3/Updates/SparkleUpdateController.swift")

    for forbiddenPayloadAPI in [
      "feedParameters",
      "httpHeaders",
      "URLRequest",
      "URLSession",
      "donor",
      "analytics",
    ] {
      XCTAssertFalse(implementation.contains(forbiddenPayloadAPI))
    }
  }

  func testSparklePackageIsPinnedToExact294Revision() throws {
    let project = try source(at: "Keep3.xcodeproj/project.pbxproj")
    let resolved = try source(
      at: "Keep3.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
    )

    XCTAssertTrue(project.contains("kind = exactVersion;"))
    XCTAssertTrue(project.contains("version = 2.9.4;"))
    XCTAssertTrue(resolved.contains(#""version" : "2.9.4""#))
    XCTAssertTrue(
      resolved.contains(
        #""revision" : "b6496a74a087257ef5e6da1c5b29a447a60f5bd7""#
      )
    )
  }

  private func source(at relativePath: String) throws -> String {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    return try String(
      contentsOf: repositoryRoot.appendingPathComponent(relativePath),
      encoding: .utf8
    )
  }
}

@MainActor
private final class FakeUpdateChecker: UpdateChecking {
  enum PreferenceChange: Equatable {
    case automaticallyChecks(Bool)
    case automaticallyDownloads(Bool)
  }

  var canCheckForUpdates: Bool
  var automaticallyChecksForUpdates: Bool {
    didSet {
      preferenceChanges.append(
        .automaticallyChecks(automaticallyChecksForUpdates)
      )
    }
  }
  var automaticallyDownloadsUpdates: Bool {
    didSet {
      preferenceChanges.append(
        .automaticallyDownloads(automaticallyDownloadsUpdates)
      )
    }
  }
  var sendsSystemProfile: Bool
  var stateDidChange: (() -> Void)?
  private(set) var checkCount = 0
  private(set) var preferenceChanges: [PreferenceChange] = []

  init(
    canCheckForUpdates: Bool = true,
    automaticallyChecksForUpdates: Bool = false,
    automaticallyDownloadsUpdates: Bool = false,
    sendsSystemProfile: Bool = false
  ) {
    self.canCheckForUpdates = canCheckForUpdates
    self.automaticallyChecksForUpdates = automaticallyChecksForUpdates
    self.automaticallyDownloadsUpdates = automaticallyDownloadsUpdates
    self.sendsSystemProfile = sendsSystemProfile
  }

  func checkForUpdates() {
    checkCount += 1
    canCheckForUpdates = false
    stateDidChange?()
  }

  func completeCheck() {
    canCheckForUpdates = true
    stateDidChange?()
  }
}
