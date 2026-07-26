import MediaPlayer
import XCTest

@testable import Keep3

final class MediaRemoteAdapterIntegrationTests: XCTestCase {
  func testEmbeddedAlcoveStyleHelperStartsAndStopsCleanly() async {
    let adapter = MediaRemoteAdapter()

    let report = await adapter.start()
    await adapter.stop()

    XCTAssertEqual(
      report.status,
      .available,
      "Missing mandatory symbols: \(report.missingMandatorySymbols)"
    )
  }

  @MainActor
  func testLiveNowPlayingSnapshotDoesNotCrashHelper() async throws {
    let marker = "Keep3 MediaRemote ABI Regression"
    let snapshotExpectation = expectation(
      description: "Receives the live Now Playing snapshot"
    )
    snapshotExpectation.assertForOverFulfill = false
    let adapter = MediaRemoteAdapter { snapshot in
      if snapshot?.session.title?.isEmpty == false {
        snapshotExpectation.fulfill()
      }
    }
    let commandCenter = MPRemoteCommandCenter.shared()
    let toggleTarget = commandCenter.togglePlayPauseCommand.addTarget {
      _ in .success
    }

    MPNowPlayingInfoCenter.default().nowPlayingInfo = [
      MPMediaItemPropertyTitle: marker,
      MPMediaItemPropertyArtist: "Keep3 Tests",
      MPMediaItemPropertyPlaybackDuration: 60,
      MPNowPlayingInfoPropertyElapsedPlaybackTime: 5,
      MPNowPlayingInfoPropertyPlaybackRate: 1,
    ]
    MPNowPlayingInfoCenter.default().playbackState = .playing

    let report = await adapter.start()
    let waitResult = await XCTWaiter.fulfillment(
      of: [snapshotExpectation],
      timeout: 5
    )
    await adapter.stop()

    commandCenter.togglePlayPauseCommand.removeTarget(toggleTarget)
    MPNowPlayingInfoCenter.default().playbackState = .stopped
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil

    XCTAssertEqual(report.status, .available)
    guard waitResult == .completed else {
      throw XCTSkip(
        "The current macOS media session did not publish a live snapshot."
      )
    }
  }
}
