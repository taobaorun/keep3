import Foundation
import XCTest

final class ProjectSmokeTests: XCTestCase {
  func testHarnessRuns() {
    XCTAssertTrue(true)
  }

  func testDistributionMetadataPreservesAppAndMediaCompatibilityIdentities()
    throws
  {
    let project = try source(at: "Keep3.xcodeproj/project.pbxproj")
    let appInfo = try source(at: "Keep3/Resources/Info.plist")
    let helperInfo = try source(at: "Keep3MediaService/Info.plist")
    let mediaAdapter = try source(at: "Keep3/Media/MediaRemoteAdapter.swift")

    XCTAssertGreaterThanOrEqual(
      project.components(separatedBy: "MARKETING_VERSION = 0.1.0;").count - 1,
      4
    )
    XCTAssertGreaterThanOrEqual(
      project.components(separatedBy: "CURRENT_PROJECT_VERSION = 1;").count - 1,
      4
    )
    XCTAssertTrue(project.contains("PRODUCT_BUNDLE_IDENTIFIER = dev.keep3.Keep3;"))
    XCTAssertGreaterThanOrEqual(
      project.components(
        separatedBy:
          "PRODUCT_BUNDLE_IDENTIFIER = com.apple.controlcenter.Keep3MediaService;"
      ).count - 1,
      2
    )
    XCTAssertFalse(
      project.contains("PRODUCT_BUNDLE_IDENTIFIER = dev.keep3.Keep3MediaService;")
    )

    for info in [appInfo, helperInfo] {
      XCTAssertTrue(info.contains("<string>$(MARKETING_VERSION)</string>"))
      XCTAssertTrue(info.contains("<string>$(CURRENT_PROJECT_VERSION)</string>"))
    }
    XCTAssertTrue(
      mediaAdapter.contains(
        "static let serviceName = \"com.apple.controlcenter.Keep3MediaService\""
      )
    )
  }

  func testPublicSourceMaterialsDeclareFreeGPLDistribution() throws {
    let license = try source(at: "LICENSE")
    let readme = try source(at: "README.md")
    let notices = try source(at: "THIRD_PARTY_NOTICES.md")

    XCTAssertTrue(license.contains("GNU GENERAL PUBLIC LICENSE"))
    XCTAssertTrue(license.contains("Version 3, 29 June 2007"))
    XCTAssertTrue(license.contains("Copyright © 2007 Free Software Foundation"))
    XCTAssertTrue(readme.contains("GPL-3.0"))
    XCTAssertTrue(readme.contains("exact source tag"))
    XCTAssertTrue(notices.contains("Third-Party Notices"))
  }

  func testProjectHasNoPaidDistributionConfiguration() throws {
    let distributionInputs = try [
      source(at: "Keep3.xcodeproj/project.pbxproj"),
      source(at: "Keep3/Resources/Info.plist"),
      source(at: "Keep3MediaService/Info.plist"),
    ].joined(separator: "\n").lowercased()

    for paidGate in ["license key", "trial expiry", "subscription", "payment", "donor"] {
      XCTAssertFalse(distributionInputs.contains(paidGate))
    }
  }

  func testWebsiteIsExcludedFromNativeProjectInputs() throws {
    let project = try source(at: "Keep3.xcodeproj/project.pbxproj")

    XCTAssertFalse(project.lowercased().contains("website"))
  }

  func testDebugAdHocBuildDisablesLibraryValidationWithoutWeakeningRelease()
    throws
  {
    let project = try source(at: "Keep3.xcodeproj/project.pbxproj")
    let debugEntitlements = try propertyList(
      at: "Keep3/Keep3Debug.entitlements"
    )
    let releaseEntitlements = try propertyList(
      at: "Keep3/Keep3.entitlements"
    )

    XCTAssertTrue(
      project.contains(
        "CODE_SIGN_ENTITLEMENTS = Keep3/Keep3Debug.entitlements;"
      )
    )
    XCTAssertEqual(
      debugEntitlements["com.apple.security.cs.disable-library-validation"]
        as? Bool,
      true
    )
    XCTAssertNil(
      releaseEntitlements[
        "com.apple.security.cs.disable-library-validation"
      ]
    )
  }

  private func propertyList(at relativePath: String) throws -> [String: Any] {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let data = try Data(
      contentsOf: repositoryRoot.appendingPathComponent(relativePath)
    )
    return try XCTUnwrap(
      PropertyListSerialization.propertyList(from: data, format: nil)
        as? [String: Any]
    )
  }

  private func source(at relativePath: String) throws -> String {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    return try String(
      contentsOf: repositoryRoot.appendingPathComponent(relativePath),
      encoding: .utf8
    )
  }
}
