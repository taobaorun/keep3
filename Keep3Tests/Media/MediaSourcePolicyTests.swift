import XCTest

@testable import Keep3

final class MediaSourcePolicyTests: XCTestCase {
  func testPlayingControllableSourceIsBlockedByMasterAndSuppression() {
    let session = session()
    XCTAssertFalse(
      MediaSourcePolicy(isMediaFirstEnabled: false)
        .allows(session, frontmostBundleIdentifier: nil)
    )
    XCTAssertFalse(
      MediaSourcePolicy(suppressedBundleIdentifiers: ["com.spotify.client"])
        .allows(session, frontmostBundleIdentifier: nil)
    )
    XCTAssertTrue(
      MediaSourcePolicy().allows(session, frontmostBundleIdentifier: nil)
    )
  }

  func testFrontmostHidingNeedsAnExactStableSourceMatch() {
    let policy = MediaSourcePolicy(hidesFrontmostSource: true)

    XCTAssertFalse(
      policy.allows(
        session(),
        frontmostBundleIdentifier: "com.spotify.client"
      )
    )
    XCTAssertTrue(
      policy.allows(
        session(),
        frontmostBundleIdentifier: "com.apple.TextEdit"
      )
    )
    XCTAssertTrue(
      policy.allows(
        session(sourceBundleIdentifier: nil),
        frontmostBundleIdentifier: "com.spotify.client"
      )
    )
  }

  private func session(
    sourceBundleIdentifier: String? = "com.spotify.client"
  ) -> MediaSession {
    MediaSession.normalize(
      .init(
        sessionID: "session-1",
        sourceBundleIdentifier: sourceBundleIdentifier,
        title: nil,
        artist: nil,
        duration: nil,
        progress: nil,
        capabilities: ["playPause"]
      )
    )!
  }
}
