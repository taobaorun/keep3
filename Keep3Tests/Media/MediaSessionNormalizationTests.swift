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
  }
}
