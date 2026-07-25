import XCTest

@testable import Keep3

final class MediaSurfacePresentationTests: XCTestCase {
  func testOmitsUnsupportedControlsWithoutLeavingPlaceholderActions() {
    let presentation = MediaSurfacePresentation(
      payload: payload(
        capabilities: [.playPause, .next],
        secondaryAction: .shuffle
      )
    )

    XCTAssertEqual(
      presentation.primaryActions,
      [.togglePlayPause, .next]
    )
    XCTAssertNil(presentation.secondaryAction)
  }

  func testShowsSupportedSecondaryActionAndBoundsProgress() {
    let presentation = MediaSurfacePresentation(
      payload: payload(
        duration: 200,
        progress: 50,
        capabilities: [.previous, .playPause, .next, .shuffle],
        secondaryAction: .shuffle
      )
    )

    XCTAssertEqual(
      presentation.primaryActions,
      [.previous, .togglePlayPause, .next]
    )
    XCTAssertEqual(presentation.secondaryAction, .shuffle)
    XCTAssertEqual(presentation.progressFraction, 0.25)
    XCTAssertEqual(presentation.elapsedLabel, "0:50")
    XCTAssertEqual(presentation.remainingLabel, "-2:30")
    XCTAssertFalse(presentation.canSeek)
  }

  func testSeekingRequiresTheExplicitCapability() {
    let seekable = MediaSurfacePresentation(
      payload: payload(
        duration: 200,
        progress: 50,
        capabilities: [.playPause, .seek]
      )
    )
    XCTAssertTrue(seekable.canSeek)
    XCTAssertEqual(seekable.duration, 200)
    XCTAssertEqual(seekable.progress, 50)
  }

  func testQuickPeekRemainsDistinctFromManualExpansion() {
    let quickPeek = MediaSurfacePresentation(
      payload: payload(
        isExpanded: true,
        expansionReason: .quickPeek
      )
    )
    let manual = MediaSurfacePresentation(
      payload: payload(
        isExpanded: true,
        expansionReason: .manual
      )
    )

    XCTAssertTrue(quickPeek.isTemporaryExpansion)
    XCTAssertFalse(manual.isTemporaryExpansion)
  }

  private func payload(
    isExpanded: Bool = false,
    expansionReason: SurfaceExpansionReason = .none,
    duration: TimeInterval? = nil,
    progress: TimeInterval? = nil,
    capabilities: Set<MediaCapability> = [.playPause],
    secondaryAction: MediaSecondaryAction = .none
  ) -> MediaSurfacePayload {
    let session = MediaSession.normalize(
      .init(
        sessionID: "session-1",
        sourceBundleIdentifier: "com.netease.163music",
        title: "Track",
        artist: "Artist",
        applicationName: "网易云音乐",
        duration: duration,
        progress: progress,
        capabilities: capabilities.map(\.rawValue)
      )
    )
    return MediaSurfacePayload(
      sessionID: "session-1",
      contentRevision: 1,
      isExpanded: isExpanded,
      areControlsEnabled: true,
      session: session,
      playbackState: .playing,
      capabilityRevision: 1,
      expansionReason: expansionReason,
      appearance: MediaSurfaceAppearance(
        artworkTreatment: .artwork,
        showsWaveform: true,
        secondaryAction: secondaryAction,
        backgroundOpacity: 0.94
      )
    )
  }
}
