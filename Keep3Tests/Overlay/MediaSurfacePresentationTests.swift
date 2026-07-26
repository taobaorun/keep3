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

  func testSecondaryActionsRequireTheirExactCapability() {
    let favorite = MediaSurfacePresentation(
      payload: payload(
        capabilities: [.playPause, .favorite],
        secondaryAction: .favorite
      )
    )
    let repeatOne = MediaSurfacePresentation(
      payload: payload(
        capabilities: [.playPause, .repeatOne],
        secondaryAction: .repeatOne
      )
    )

    XCTAssertEqual(favorite.secondaryAction, .favorite)
    XCTAssertEqual(repeatOne.secondaryAction, .repeatOne)
    XCTAssertNil(
      MediaSurfacePresentation(
        payload: payload(
          capabilities: [.playPause, .repeatMode],
          secondaryAction: .repeatOne
        )
      ).secondaryAction
    )
  }

  func testCopySourceRequiresValidatedPublicHTTPSURL() {
    let copyable = MediaSurfacePresentation(
      payload: payload(
        capabilities: [.playPause],
        secondaryAction: .copySource,
        publicShareURL: "https://music.example.com/track/42"
      )
    )
    let local = MediaSurfacePresentation(
      payload: payload(
        capabilities: [.playPause],
        secondaryAction: .copySource,
        publicShareURL: "https://localhost/track/42"
      )
    )

    XCTAssertEqual(
      copyable.secondaryAction,
      .copySource(URL(string: "https://music.example.com/track/42")!)
    )
    XCTAssertNil(local.secondaryAction)
  }

  func testSourceHideRequiresPersistableBundleIdentifier() {
    XCTAssertTrue(
      MediaSurfacePresentation(payload: payload()).canHideSource
    )
    XCTAssertFalse(
      MediaSurfacePresentation(
        payload: payload(sourceBundleIdentifier: nil)
      ).canHideSource
    )
    XCTAssertFalse(
      MediaSurfacePresentation(
        payload: payload(sourceBundleIdentifier: "not stable")
      ).canHideSource
    )
  }

  func testTitleExtrasAreOptIn() {
    let hidden = MediaSurfacePresentation(payload: payload())
    let visible = MediaSurfacePresentation(
      payload: payload(showsMediaTitleExtras: true)
    )

    XCTAssertNil(hidden.album)
    XCTAssertNil(hidden.applicationName)
    XCTAssertEqual(visible.album, "Album")
    XCTAssertEqual(visible.applicationName, "网易云音乐")
  }

  private func payload(
    isExpanded: Bool = false,
    expansionReason: SurfaceExpansionReason = .none,
    duration: TimeInterval? = nil,
    progress: TimeInterval? = nil,
    capabilities: Set<MediaCapability> = [.playPause],
    secondaryAction: MediaSecondaryAction = .none,
    sourceBundleIdentifier: String? = "com.netease.163music",
    publicShareURL: String? = nil,
    showsMediaTitleExtras: Bool = false
  ) -> MediaSurfacePayload {
    let session = MediaSession.normalize(
      .init(
        sessionID: "session-1",
        sourceBundleIdentifier: sourceBundleIdentifier,
        title: "Track",
        artist: "Artist",
        album: "Album",
        applicationName: "网易云音乐",
        publicShareURL: publicShareURL,
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
        showsArtworkFlip: false,
        showsMediaTitleExtras: showsMediaTitleExtras,
        secondaryAction: secondaryAction,
        backgroundOpacity: 0.94
      )
    )
  }
}
