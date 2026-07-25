import XCTest

@testable import Keep3

final class ProviderEnrichmentServiceTests: XCTestCase {
  func testUnknownProviderIsRejectedWithoutRequestingPermission() async {
    let requester = RecordingAutomationPermissionRequester(result: .granted)
    let service = ProviderEnrichmentService(
      permissionRequester: requester,
      isApplicationRunning: { _ in true }
    )

    let enrichment = await service.requestUserInitiatedEnrichment(
      for: session(bundleIdentifier: "com.example.unknown")
    )

    XCTAssertNil(enrichment)
    let requestCount = await requester.requestCount
    XCTAssertEqual(requestCount, 0)
  }

  func testKnownProviderUsesOnlyCompileTimeCapabilityBackends() async {
    let requester = RecordingAutomationPermissionRequester(result: .granted)
    let service = ProviderEnrichmentService(
      permissionRequester: requester,
      isApplicationRunning: { $0 == "com.spotify.client" }
    )

    let enrichment = await service.requestUserInitiatedEnrichment(
      for: session(bundleIdentifier: "com.spotify.client")
    )

    XCTAssertEqual(enrichment?.bundleIdentifier, "com.spotify.client")
    XCTAssertEqual(
      enrichment?.capabilityBackends[.favorite],
      .automation(
        targetBundleIdentifier: "com.spotify.client",
        command: .spotifyFavorite
      )
    )
    let requestCount = await requester.requestCount
    XCTAssertEqual(requestCount, 1)
  }

  func testFailureOutcomesRetractOnlyEnrichment() async {
    let failures: [AutomationPermissionOutcome] = [
      .denied, .revoked, .timedOut, .missingScriptingSupport,
    ]
    let baseline = session(bundleIdentifier: "com.apple.Music")

    for failure in failures {
      let service = ProviderEnrichmentService(
        permissionRequester: RecordingAutomationPermissionRequester(
          result: failure
        ),
        isApplicationRunning: { _ in true }
      )

      let enrichment = await service.requestUserInitiatedEnrichment(
        for: baseline
      )
      XCTAssertNil(
        enrichment,
        "\(failure) must retract provider-owned capabilities"
      )
      XCTAssertTrue(baseline.capabilities.contains(.playPause))
    }

    let notRunning = ProviderEnrichmentService(
      permissionRequester: RecordingAutomationPermissionRequester(
        result: .granted
      ),
      isApplicationRunning: { _ in false }
    )
    let notRunningEnrichment =
      await notRunning.requestUserInitiatedEnrichment(for: baseline)
    XCTAssertNil(notRunningEnrichment)
  }

  private func session(bundleIdentifier: String) -> MediaSession {
    MediaSession.normalize(
      .init(
        sessionID: "session-1",
        sourceBundleIdentifier: bundleIdentifier,
        title: "Track",
        artist: nil,
        duration: nil,
        progress: nil,
        capabilities: ["playPause"]
      )
    )!
  }
}

private actor RecordingAutomationPermissionRequester:
  AutomationPermissionRequesting
{
  let result: AutomationPermissionOutcome
  private(set) var requestCount = 0

  init(result: AutomationPermissionOutcome) {
    self.result = result
  }

  func requestPermission(
    for _: ProviderAutomationTarget
  ) -> AutomationPermissionOutcome {
    requestCount += 1
    return result
  }
}
