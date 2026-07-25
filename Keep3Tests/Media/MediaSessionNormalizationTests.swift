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
}
