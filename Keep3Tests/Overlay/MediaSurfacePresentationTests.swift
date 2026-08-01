import XCTest

@testable import Keep3

final class MediaSurfacePresentationTests: XCTestCase {
  func testExpandedMediaAccessibilityRetreatTargetsCompactMedia() {
    let action = SurfaceAccessibilityNavigationAction.expandedRetreat(
      for: .media
    )

    XCTAssertEqual(action.name, "返回普通播放器")
    XCTAssertEqual(action.intent, .retreatDepth)
    XCTAssertEqual(action.focusDestination, .compactMedia)
    XCTAssertEqual(action.announcement, "已返回普通播放器")
  }

  func testExpandedNonMediaAccessibilityRetreatKeepsComponentNavigation() {
    for component in [SurfaceComponentID.priorities, .calendar] {
      let action = SurfaceAccessibilityNavigationAction.expandedRetreat(
        for: component
      )

      XCTAssertEqual(action.name, "上一个组件")
      XCTAssertEqual(action.intent, .previousComponent)
      XCTAssertNil(action.focusDestination)
      XCTAssertNil(action.announcement)
    }
  }

  func testTrackPeekRetainsUnicodeTitleAndArtistForCompactMetadata() {
    let peek = MediaTrackPeek(
      direction: .next,
      title: "很长的歌名 🎵 with Unicode that must truncate",
      artist: "歌手 Artist"
    )

    XCTAssertEqual(peek.title, "很长的歌名 🎵 with Unicode that must truncate")
    XCTAssertEqual(peek.artist, "歌手 Artist")
  }

  func testDirectionalNotchLayoutKeepsTheOppositeWingStable() {
    let previous = DirectionalMediaNotchLayout(
      surfaceSize: CGSize(width: 344, height: 68),
      obstructionSize: CGSize(width: 185, height: 32),
      baseWingWidth: SurfaceMetrics.mediaNotchedWingWidth,
      extensionDirection: .previous
    )
    let next = DirectionalMediaNotchLayout(
      surfaceSize: CGSize(width: 344, height: 68),
      obstructionSize: CGSize(width: 185, height: 32),
      baseWingWidth: SurfaceMetrics.mediaNotchedWingWidth,
      extensionDirection: .next
    )

    XCTAssertEqual(previous.leftWingFrame.width, 115)
    XCTAssertEqual(previous.rightWingFrame.width, 44)
    XCTAssertEqual(next.leftWingFrame.width, 44)
    XCTAssertEqual(next.rightWingFrame.width, 115)
    XCTAssertEqual(previous.rightWingFrame.size, next.leftWingFrame.size)
    XCTAssertEqual(previous.artworkFrame.width, 44)
    XCTAssertEqual(next.artworkFrame.width, 44)
    XCTAssertEqual(
      previous.artworkFrame.maxX,
      previous.obstructionFrame.minX
    )
    XCTAssertEqual(next.artworkFrame.maxX, next.obstructionFrame.minX)
  }

  func testNotchedQuickPeekKeepsSymmetricWingsAndPlacesMetadataBelowNotch() {
    let layout = MediaNotchQuickPeekLayout(
      surfaceSize: CGSize(width: 273, height: 64),
      obstructionSize: CGSize(width: 185, height: 32),
    )

    XCTAssertEqual(layout.leftWingFrame, CGRect(x: 0, y: 0, width: 44, height: 32))
    XCTAssertEqual(layout.obstructionFrame, CGRect(x: 44, y: 0, width: 185, height: 32))
    XCTAssertEqual(
      layout.rightWingFrame,
      CGRect(x: 229, y: 0, width: 44, height: 32)
    )
    XCTAssertEqual(layout.metadataFrame, CGRect(x: 52, y: 32, width: 169, height: 32))
    XCTAssertFalse(layout.metadataFrame.intersects(layout.obstructionFrame))
  }

  func testQuickPeekShapeRemainsContinuousAcrossBothWings() {
    let layout = MediaNotchQuickPeekLayout(
      surfaceSize: CGSize(width: 273, height: 64),
      obstructionSize: CGSize(width: 185, height: 32),
    )
    let path = TopSurfaceShape(
      presentationStyle: .notchAttached(
        notchSize: layout.obstructionFrame.size
      ),
      isExpanded: false,
      isQuickPeek: true
    ).path(
      in: CGRect(origin: .zero, size: layout.surfaceSize)
    )

    XCTAssertTrue(path.contains(CGPoint(x: layout.leftWingFrame.midX, y: 16)))
    XCTAssertTrue(path.contains(CGPoint(x: layout.rightWingFrame.midX, y: 16)))
    XCTAssertTrue(path.contains(CGPoint(x: layout.leftWingFrame.midX, y: 48)))
    XCTAssertTrue(path.contains(CGPoint(x: layout.rightWingFrame.midX, y: 48)))
    XCTAssertTrue(path.contains(CGPoint(x: layout.metadataFrame.midX, y: 48)))
    XCTAssertFalse(path.contains(CGPoint(x: 1, y: 48)))
    XCTAssertFalse(path.contains(CGPoint(x: 272, y: 48)))
  }

  func testNotchedArtworkOverlayPersistsAcrossCompactAndQuickPeek() {
    let compact = MediaSurfacePresentation(payload: payload())
    let quickPeek = MediaSurfacePresentation(
      payload: payload(
        trackPeek: MediaTrackPeek(
          direction: .next,
          title: "Next Track",
          artist: "Artist"
        )
      )
    )
    let expanded = MediaSurfacePresentation(
      payload: payload(isExpanded: true)
    )
    let hardware = MediaSurfacePresentation(
      payload: payload(level: .hardware)
    )
    let hardwareQuickPeek = MediaSurfacePresentation(
      payload: payload(
        level: .hardware,
        trackPeek: MediaTrackPeek(
          direction: .next,
          title: "Next Track",
          artist: "Artist"
        )
      )
    )

    XCTAssertTrue(compact.shouldShowNotchedArtworkOverlay)
    XCTAssertTrue(quickPeek.shouldShowNotchedArtworkOverlay)
    XCTAssertFalse(expanded.shouldShowNotchedArtworkOverlay)
    XCTAssertFalse(hardware.shouldShowNotchedArtworkOverlay)
    XCTAssertTrue(hardwareQuickPeek.shouldShowNotchedArtworkOverlay)
  }

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

  func testPlayingProgressAdvancesFromItsTimestampAndClampsAtDuration()
    throws
  {
    let sampledAt = Date(timeIntervalSince1970: 1_000)
    let presentation = MediaSurfacePresentation(
      payload: payload(
        duration: 60,
        progress: 55,
        progressSampleDate: sampledAt
      )
    )

    let advancedProgress = try XCTUnwrap(
      presentation.resolvedProgress(
        at: Date(timeIntervalSince1970: 1_003)
      )
    )
    let clampedProgress = try XCTUnwrap(
      presentation.resolvedProgress(
        at: Date(timeIntervalSince1970: 1_010)
      )
    )

    XCTAssertEqual(advancedProgress, 58, accuracy: 0.001)
    XCTAssertEqual(clampedProgress, 60, accuracy: 0.001)
  }

  func testPausedProgressDoesNotAdvancePastItsSample() throws {
    let sampledAt = Date(timeIntervalSince1970: 1_000)
    let presentation = MediaSurfacePresentation(
      payload: payload(
        duration: 60,
        progress: 20,
        progressSampleDate: sampledAt,
        playbackState: .paused
      )
    )

    let resolvedProgress = try XCTUnwrap(
      presentation.resolvedProgress(
        at: Date(timeIntervalSince1970: 1_010)
      )
    )

    XCTAssertEqual(resolvedProgress, 20, accuracy: 0.001)
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

  func testArtworkOpenTargetRequiresPersistableBundleIdentifier() {
    XCTAssertEqual(
      MediaSurfacePresentation(payload: payload()).sourceBundleIdentifier,
      "com.netease.163music"
    )
    XCTAssertNil(
      MediaSurfacePresentation(
        payload: payload(sourceBundleIdentifier: nil)
      ).sourceBundleIdentifier
    )
    XCTAssertNil(
      MediaSurfacePresentation(
        payload: payload(sourceBundleIdentifier: "not stable")
      ).sourceBundleIdentifier
    )
  }

  @MainActor
  func testPlayerApplicationActivatorUsesCurrentSourceBundleIdentifier() {
    var activatedBundleIdentifiers: [String] = []
    let activator = MediaPlayerApplicationActivator {
      activatedBundleIdentifiers.append($0)
      return true
    }

    XCTAssertTrue(
      activator.activate(bundleIdentifier: "com.netease.163music")
    )
    XCTAssertEqual(
      activatedBundleIdentifiers,
      ["com.netease.163music"]
    )
  }

  @MainActor
  func testPlayerApplicationActivatorRejectsMissingOrUnstableIdentifiers() {
    var activationCount = 0
    let activator = MediaPlayerApplicationActivator { _ in
      activationCount += 1
      return true
    }

    XCTAssertFalse(activator.activate(bundleIdentifier: nil))
    XCTAssertFalse(activator.activate(bundleIdentifier: "not stable"))
    XCTAssertEqual(activationCount, 0)
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

  func testInactivePlayerUsesItsApplicationNameWhenTrackMetadataIsAbsent() {
    let presentation = MediaSurfacePresentation(
      payload: payload(
        title: nil,
        playbackState: .paused
      )
    )

    XCTAssertEqual(presentation.title, "网易云音乐")
    XCTAssertFalse(presentation.isPlaying)
  }

  func testNotchedCompactWaveformMatchesTheAlcoveEnvelope() {
    let style = MediaWaveformStyle.notchedCompact

    XCTAssertEqual(style.barCount, 6)
    XCTAssertEqual(style.intrinsicWidth, 16.5, accuracy: 0.001)
    XCTAssertEqual(style.maximumHeight, 10, accuracy: 0.001)
  }

  @MainActor
  func testEveryWaveformStyleRetainsTheResolvedArtworkAccent() {
    let accent = MediaArtworkAccent(
      red: 0.24,
      green: 0.54,
      blue: 0.94
    )

    let regular = MediaWaveformView(
      seed: "session-1",
      isPlaying: true,
      accent: accent
    )
    let notched = MediaWaveformView(
      seed: "session-1",
      isPlaying: true,
      style: .notchedCompact,
      accent: accent
    )
    let expanded = MediaWaveformView(
      seed: "session-1",
      isPlaying: true,
      style: .expanded,
      accent: accent
    )

    XCTAssertEqual(regular.accent, accent)
    XCTAssertEqual(notched.accent, accent)
    XCTAssertEqual(expanded.accent, accent)
    XCTAssertEqual(regular.scalarSeed, notched.scalarSeed)
    XCTAssertEqual(notched.scalarSeed, expanded.scalarSeed)
  }

  func testExpandedLayoutMatchesTheAlcoveSpacing() {
    let metrics = MediaExpandedLayoutMetrics(surfaceWidth: 344)
    let expectedCenters: [CGFloat] = [
      40.8, 106.4, 172, 237.6, 303.2,
    ]

    XCTAssertEqual(metrics.horizontalInset, 22, accuracy: 0.001)
    XCTAssertEqual(metrics.progressTrackLeadingEdge, 58, accuracy: 0.001)
    XCTAssertEqual(metrics.progressTrackHeight, 4, accuracy: 0.001)
    XCTAssertEqual(metrics.progressHitTargetHeight, 14, accuracy: 0.001)
    XCTAssertEqual(metrics.controlCenters.count, expectedCenters.count)
    for (actual, expected) in zip(
      metrics.controlCenters,
      expectedCenters
    ) {
      XCTAssertEqual(actual, expected, accuracy: 0.001)
    }
    XCTAssertEqual(metrics.bottomInset, 22, accuracy: 0.001)
  }

  func testArtworkTransitionIdentityTracksArtworkArrivingAfterMetadata() {
    let pendingArtwork = MediaSurfacePresentation(
      payload: payload(
        contentRevision: 2,
        artworkRevision: 3
      )
    )
    let artwork = Data([1, 2, 3])
    let resolvedArtwork = MediaSurfacePresentation(
      payload: payload(
        contentRevision: 2,
        artworkRevision: 4,
        artworkData: artwork
      )
    )
    let progressOnlyUpdate = MediaSurfacePresentation(
      payload: payload(
        contentRevision: 2,
        artworkRevision: 4,
        progress: 10,
        artworkData: artwork
      )
    )

    XCTAssertNotEqual(
      pendingArtwork.artworkTransitionIdentity,
      resolvedArtwork.artworkTransitionIdentity
    )
    XCTAssertEqual(
      resolvedArtwork.artworkTransitionIdentity,
      progressOnlyUpdate.artworkTransitionIdentity
    )
  }

  private func payload(
    contentRevision: UInt64 = 1,
    artworkRevision: UInt64? = nil,
    isExpanded: Bool = false,
    level: SurfaceLevel? = nil,
    expansionReason: SurfaceExpansionReason = .none,
    duration: TimeInterval? = nil,
    progress: TimeInterval? = nil,
    progressSampleDate: Date? = nil,
    capabilities: Set<MediaCapability> = [.playPause],
    secondaryAction: MediaSecondaryAction = .none,
    sourceBundleIdentifier: String? = "com.netease.163music",
    publicShareURL: String? = nil,
    showsMediaTitleExtras: Bool = false,
    title: String? = "Track",
    artworkData: Data? = nil,
    playbackState: MediaPlaybackState = .playing,
    trackPeek: MediaTrackPeek? = nil
  ) -> MediaSurfacePayload {
    let session = MediaSession.normalize(
      .init(
        sessionID: "session-1",
        sourceBundleIdentifier: sourceBundleIdentifier,
        title: title,
        artist: "Artist",
        album: "Album",
        applicationName: "网易云音乐",
        publicShareURL: publicShareURL,
        artworkData: artworkData,
        artworkMIMEType: artworkData == nil ? nil : "image/png",
        duration: duration,
        progress: progress,
        progressSampleDate: progressSampleDate,
        capabilities: capabilities.map(\.rawValue)
      )
    )
    return MediaSurfacePayload(
      sessionID: "session-1",
      contentRevision: contentRevision,
      artworkRevision: artworkRevision,
      isExpanded: isExpanded,
      level: level,
      areControlsEnabled: true,
      session: session,
      playbackState: playbackState,
      capabilityRevision: 1,
      expansionReason: expansionReason,
      appearance: MediaSurfaceAppearance(
        artworkTreatment: .artwork,
        showsWaveform: true,
        showsArtworkFlip: false,
        showsMediaTitleExtras: showsMediaTitleExtras,
        secondaryAction: secondaryAction,
        backgroundOpacity: 0.94
      ),
      trackPeek: trackPeek
    )
  }
}
