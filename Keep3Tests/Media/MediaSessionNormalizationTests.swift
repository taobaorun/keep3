import XCTest

@testable import Keep3

final class MediaSessionNormalizationTests: XCTestCase {
  func testNormalizesInvalidFieldsToSafeAbsence() {
    let session = MediaSession.normalize(
      .init(
        sessionID: "",
        sourceBundleIdentifier: String(repeating: "a", count: 300),
        title: String(repeating: "x", count: 600),
        artist: "\u{0}",
        duration: -1,
        progress: .infinity,
        capabilities: ["playPause", "unknown"]
      )
    )

    XCTAssertNil(session)
  }

  func testKeepsTitleOnlyPlaybackSessionUsable() {
    let session = MediaSession.normalize(
      .init(
        sessionID: "session-1",
        sourceBundleIdentifier: "com.example.browser",
        title: "Episode",
        artist: nil,
        duration: nil,
        progress: nil,
        capabilities: ["playPause"]
      )
    )

    XCTAssertEqual(session?.title, "Episode")
    XCTAssertEqual(session?.capabilities, [.playPause])
    XCTAssertNil(session?.duration)
  }

  func testNormalizesVersionedXPCSnapshotAndRejectsProtocolMismatch() {
    let propertyList: NSDictionary = [
      "protocolVersion": NSNumber(
        value: MediaCompatibilityReport.protocolVersion
      ),
      "isPresent": true,
      "sessionID": "com.netease.163music:42",
      "sourceBundleIdentifier": "com.netease.163music",
      "applicationName": "网易云音乐",
      "title": "Track",
      "artist": "Artist",
      "playbackState": "playing",
      "capabilityRevision": 1,
      "contentRevision": 2,
      "capabilities": ["previous", "playPause", "next"],
    ]

    let snapshot = MediaAdapterSnapshot(propertyList: propertyList)

    XCTAssertEqual(
      snapshot?.session.sourceBundleIdentifier,
      "com.netease.163music"
    )
    XCTAssertEqual(snapshot?.playbackState, .playing)
    XCTAssertEqual(snapshot?.contentRevision, 2)

    let mismatched = propertyList.mutableCopy() as! NSMutableDictionary
    mismatched["protocolVersion"] = -1
    XCTAssertNil(MediaAdapterSnapshot(propertyList: mismatched))

    let fractional = propertyList.mutableCopy() as! NSMutableDictionary
    fractional["protocolVersion"] = NSNumber(
      value: Double(MediaCompatibilityReport.protocolVersion) + 0.5
    )
    XCTAssertNil(MediaAdapterSnapshot(propertyList: fractional))

    let boolean = propertyList.mutableCopy() as! NSMutableDictionary
    boolean["protocolVersion"] = NSNumber(value: true)
    XCTAssertNil(MediaAdapterSnapshot(propertyList: boolean))
  }

  func testCompatibilityReportRejectsFractionalAndBooleanProtocolVersions() {
    let valid = MediaCompatibilityReport(
      status: .available,
      missingMandatorySymbols: [],
      missingOptionalSymbols: [],
      optionalCapabilities: []
    ).propertyList
    XCTAssertNotNil(MediaCompatibilityReport(propertyList: valid))

    let fractional = valid.mutableCopy() as! NSMutableDictionary
    fractional["protocolVersion"] = NSNumber(
      value: Double(MediaCompatibilityReport.protocolVersion) + 0.25
    )
    XCTAssertNil(MediaCompatibilityReport(propertyList: fractional))

    let boolean = valid.mutableCopy() as! NSMutableDictionary
    boolean["protocolVersion"] = NSNumber(value: true)
    XCTAssertNil(MediaCompatibilityReport(propertyList: boolean))
  }

  func testAcceptsOnlyCredentialFreePublicHTTPSShareURLs() {
    let accepted = MediaSession.validatedPublicHTTPSURL(
      "https://music.example.com/track/42?share=1"
    )

    XCTAssertEqual(
      accepted?.absoluteString,
      "https://music.example.com/track/42?share=1"
    )
    XCTAssertNil(
      MediaSession.validatedPublicHTTPSURL(
        "https://user:secret@music.example.com/track/42"
      )
    )
    XCTAssertNil(
      MediaSession.validatedPublicHTTPSURL(
        "http://music.example.com/track/42"
      )
    )
    XCTAssertNil(
      MediaSession.validatedPublicHTTPSURL(
        "https://192.168.1.2/track/42"
      )
    )
    XCTAssertNil(
      MediaSession.validatedPublicHTTPSURL(
        "https://localhost/track/42"
      )
    )
  }

  func testArtworkWireUpdatesReplaceRetainAndClearPayload() {
    let artwork = Data([1, 2, 3])
    let replacement = snapshotPropertyList()
    replacement["artworkUpdate"] = MediaArtworkWireUpdate.replace.rawValue
    replacement["artworkData"] = artwork
    replacement["artworkMIMEType"] = "image/png"
    XCTAssertEqual(
      MediaAdapterSnapshot(propertyList: replacement)?.session.artworkData,
      artwork
    )

    let unchanged = snapshotPropertyList()
    unchanged["artworkUpdate"] = MediaArtworkWireUpdate.unchanged.rawValue
    let retained = MediaAdapterSnapshot(
      propertyList: unchanged,
      retainedArtwork: MediaArtworkPayload(
        data: artwork,
        mimeType: "image/png"
      )
    )
    XCTAssertEqual(retained?.session.artworkData, artwork)
    XCTAssertEqual(retained?.session.artworkMIMEType, "image/png")

    let cleared = snapshotPropertyList()
    cleared["artworkUpdate"] = MediaArtworkWireUpdate.clear.rawValue
    XCTAssertNil(
      MediaAdapterSnapshot(
        propertyList: cleared,
        retainedArtwork: MediaArtworkPayload(
          data: artwork,
          mimeType: "image/png"
        )
      )?.session.artworkData
    )
  }

  func testCapabilityPolicyOnlyMapsVerifiedEnabledCommands() {
    XCTAssertEqual(
      MediaRemoteCapabilityPolicy.capability(forEnabledCommand: 2),
      .playPause
    )
    XCTAssertEqual(
      MediaRemoteCapabilityPolicy.capability(forEnabledCommand: 4),
      .next
    )
    XCTAssertNil(
      MediaRemoteCapabilityPolicy.capability(forEnabledCommand: 999)
    )
  }

  func testCapabilityPolicyComplementsSourceCommandsWithIndependentSeekTransport() {
    let capabilities = MediaRemoteCapabilityPolicy.capabilities(
      forEnabledCommands: [2, 4, 999],
      independentTransports: [.seek]
    )

    XCTAssertEqual(capabilities, [.playPause, .next, .seek])
  }

  private func snapshotPropertyList() -> NSMutableDictionary {
    [
      "protocolVersion": NSNumber(
        value: MediaCompatibilityReport.protocolVersion
      ),
      "isPresent": true,
      "sessionID": "session-1",
      "title": "Track",
      "playbackState": "playing",
      "capabilityRevision": 1,
      "contentRevision": 2,
      "capabilities": ["playPause"],
    ] as NSMutableDictionary
  }
}
