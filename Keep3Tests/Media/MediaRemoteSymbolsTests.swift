import XCTest

@testable import Keep3

final class MediaRemoteSymbolsTests: XCTestCase {
  func testMandatorySymbolsCoverInactiveClientDiscoveryAndControl() {
    let symbols = Set(MediaRemoteSymbolResolver.mandatorySymbols)

    XCTAssertTrue(symbols.contains("MRContentItemGetArtworkData"))
    XCTAssertTrue(symbols.contains("MRContentItemGetArtworkMIMEType"))
    XCTAssertTrue(symbols.contains("MRMediaRemoteGetLocalOrigin"))
    XCTAssertTrue(symbols.contains("MRMediaRemoteGetNowPlayingClient"))
    XCTAssertTrue(symbols.contains("MRMediaRemoteGetNowPlayingClients"))
    XCTAssertTrue(symbols.contains("MRMediaRemoteGetNowPlayingInfoForClient"))
    XCTAssertTrue(
      symbols.contains("MRMediaRemoteGetNowPlayingInfoForPlayer")
    )
    XCTAssertTrue(
      symbols.contains("MRMediaRemoteGetNowPlayingPlayerForClient")
    )
    XCTAssertTrue(symbols.contains("MRMediaRemoteGetSupportedCommandsForClient"))
    XCTAssertTrue(symbols.contains("MRMediaRemoteGetSupportedCommandsForPlayer"))
    XCTAssertTrue(symbols.contains("MRMediaRemoteSendCommandToClient"))
    XCTAssertTrue(
      symbols.contains(
        "MRMediaRemoteRequestNowPlayingPlaybackQueueForPlayerSync"
      )
    )
    XCTAssertTrue(symbols.contains("MRNowPlayingClientCreate"))
    XCTAssertTrue(symbols.contains("MRNowPlayingClientGetBundleIdentifier"))
    XCTAssertTrue(
      symbols.contains("MRNowPlayingClientGetParentAppBundleIdentifier")
    )
    XCTAssertTrue(symbols.contains("MRNowPlayingPlayerPathCreate"))
    XCTAssertTrue(symbols.contains("MRPlaybackQueueGetContentItemAtOffset"))
    XCTAssertTrue(symbols.contains("MRPlaybackQueueRequestCreateDefault"))
    XCTAssertTrue(
      symbols.contains("MRPlaybackQueueRequestSetIncludeArtwork")
    )
    XCTAssertTrue(
      symbols.contains(
        "MRPlaybackQueueRequestSetReturnContentItemAssetsInUserCompletion"
      )
    )
  }

  func testInactiveClientSelectionPrefersSystemThenPreviousThenDiscoveryOrder() {
    XCTAssertEqual(
      MediaRemoteClientSelectionPolicy.orderedIndices(
        clientCount: 4,
        systemSelectedIndex: 2,
        previouslySelectedIndex: 1
      ),
      [2, 1, 0, 3]
    )
    XCTAssertEqual(
      MediaRemoteClientSelectionPolicy.orderedIndices(
        clientCount: 3,
        systemSelectedIndex: nil,
        previouslySelectedIndex: 2
      ),
      [2, 0, 1]
    )
  }

  func testInactiveClientSelectionIgnoresDuplicateAndInvalidPriorities() {
    XCTAssertEqual(
      MediaRemoteClientSelectionPolicy.orderedIndices(
        clientCount: 3,
        systemSelectedIndex: 1,
        previouslySelectedIndex: 1
      ),
      [1, 0, 2]
    )
    XCTAssertEqual(
      MediaRemoteClientSelectionPolicy.orderedIndices(
        clientCount: 2,
        systemSelectedIndex: 9,
        previouslySelectedIndex: -1
      ),
      [0, 1]
    )
    XCTAssertTrue(
      MediaRemoteClientSelectionPolicy.orderedIndices(
        clientCount: 0,
        systemSelectedIndex: nil,
        previouslySelectedIndex: nil
      ).isEmpty
    )
  }

  func testDormantPlayerSelectionUsesDynamicallyDiscoveredPlayers() {
    let qqMusic = MediaRemoteRunningApplication(
      processIdentifier: 11,
      bundleIdentifier: "com.tencent.QQMusicMac",
      applicationName: "QQ音乐"
    )
    let anotherPlayer = MediaRemoteRunningApplication(
      processIdentifier: 22,
      bundleIdentifier: "com.example.player",
      applicationName: "Another Player"
    )
    let ordinaryApplication = MediaRemoteRunningApplication(
      processIdentifier: 44,
      bundleIdentifier: "com.example.video",
      applicationName: "Video"
    )
    let applications = [ordinaryApplication, qqMusic, anotherPlayer]
    let discoveredBundleIdentifiers: Set<String> = [
      qqMusic.bundleIdentifier,
      anotherPlayer.bundleIdentifier,
    ]

    XCTAssertEqual(
      MediaRemoteDormantPlayerPolicy.select(
        from: applications,
        discoveredBundleIdentifiers: discoveredBundleIdentifiers,
        frontmostBundleIdentifier: qqMusic.bundleIdentifier,
        previouslySelectedBundleIdentifier: anotherPlayer.bundleIdentifier
      ),
      qqMusic
    )
    XCTAssertEqual(
      MediaRemoteDormantPlayerPolicy.select(
        from: applications,
        discoveredBundleIdentifiers: discoveredBundleIdentifiers,
        frontmostBundleIdentifier: ordinaryApplication.bundleIdentifier,
        previouslySelectedBundleIdentifier: anotherPlayer.bundleIdentifier
      ),
      anotherPlayer
    )
    XCTAssertEqual(
      MediaRemoteDormantPlayerPolicy.select(
        from: applications,
        discoveredBundleIdentifiers: discoveredBundleIdentifiers,
        frontmostBundleIdentifier: nil,
        previouslySelectedBundleIdentifier: nil
      ),
      qqMusic
    )
  }

  func testDormantPlayerSelectionRejectsApplicationsWithoutMediaValidation() {
    XCTAssertNil(
      MediaRemoteDormantPlayerPolicy.select(
        from: [
          MediaRemoteRunningApplication(
            processIdentifier: 44,
            bundleIdentifier: "com.example.video",
            applicationName: "Video"
          )
        ],
        discoveredBundleIdentifiers: [],
        frontmostBundleIdentifier: "com.example.video",
        previouslySelectedBundleIdentifier: nil
      )
    )
  }

  func testDormantPlayerUpgradesReportedMetadataAndRetriesAreBounded() {
    XCTAssertEqual(
      MediaRemoteDormantPlayerPolicy.playbackState(forPlaybackRate: 1),
      .playing
    )
    XCTAssertEqual(
      MediaRemoteDormantPlayerPolicy.playbackState(forPlaybackRate: 0),
      .paused
    )
    XCTAssertEqual(
      MediaRemoteDormantPlayerPolicy.resolvedCapabilities(reported: []),
      [.playPause]
    )
    XCTAssertEqual(
      MediaRemoteDormantPlayerPolicy.resolvedCapabilities(
        reported: [.playPause, .next]
      ),
      [.playPause, .next]
    )
    XCTAssertEqual(
      MediaRemoteDormantPlayerPolicy.upgradeRetryDelays,
      [0.35, 1.2, 2.5]
    )
  }

  func testUnavailableDormantPlayerKeepsRetryingUntilRecovery() {
    var policy = MediaRemoteAvailabilityRecoveryPolicy()

    XCTAssertNil(
      policy.nextRetryDelay(hasDiscoveredPlayerRunning: false)
    )
    XCTAssertEqual(
      policy.nextRetryDelay(hasDiscoveredPlayerRunning: true),
      0.5
    )
    XCTAssertEqual(
      policy.nextRetryDelay(hasDiscoveredPlayerRunning: true),
      2
    )
    XCTAssertEqual(
      policy.nextRetryDelay(hasDiscoveredPlayerRunning: true),
      5
    )
    XCTAssertEqual(
      policy.nextRetryDelay(hasDiscoveredPlayerRunning: true),
      15
    )
    XCTAssertEqual(
      policy.nextRetryDelay(hasDiscoveredPlayerRunning: true),
      30
    )
    XCTAssertEqual(
      policy.nextRetryDelay(hasDiscoveredPlayerRunning: true),
      30
    )

    policy.reset()

    XCTAssertEqual(
      policy.nextRetryDelay(hasDiscoveredPlayerRunning: true),
      0.5
    )
  }

  func testRunningApplicationContextRoundTripsAcrossPropertyListBoundary() {
    let application = MediaRemoteRunningApplication(
      processIdentifier: 33,
      bundleIdentifier: "com.netease.163music",
      applicationName: "网易云音乐"
    )

    XCTAssertEqual(
      MediaRemoteRunningApplication(propertyList: application.propertyList),
      application
    )
    XCTAssertNil(
      MediaRemoteRunningApplication(
        propertyList: ["processIdentifier": true]
      )
    )
    XCTAssertNil(
      MediaRemoteRunningApplication(
        propertyList: [
          "processIdentifier": 0,
          "bundleIdentifier": application.bundleIdentifier,
        ]
      )
    )
  }

  func testClientCommandStatusZeroMeansAccepted() {
    XCTAssertTrue(MediaRemoteClientCommandStatus.isAccepted(0))
    XCTAssertFalse(MediaRemoteClientCommandStatus.isAccepted(1))
    XCTAssertFalse(MediaRemoteClientCommandStatus.isAccepted(.max))
  }

  func testMissingMandatorySymbolDisablesTheWholeAdapter() {
    let report = MediaRemoteSymbolResolver.resolve(using: { name in
      name == "MRMediaRemoteGetNowPlayingInfo"
        ? UnsafeMutableRawPointer(bitPattern: 1) : nil
    })

    XCTAssertEqual(report.status, .unavailable)
    XCTAssertEqual(
      report.missingMandatorySymbols.count,
      MediaRemoteSymbolResolver.mandatorySymbols.count - 1
    )
    XCTAssertTrue(report.optionalCapabilities.isEmpty)
  }

  func testMissingOptionalSymbolRetainsBaselineCapabilities() {
    let report = MediaRemoteSymbolResolver.resolve(using: { name in
      MediaRemoteSymbolResolver.mandatorySymbols.contains(name)
        ? UnsafeMutableRawPointer(bitPattern: 1)
        : nil
    })

    XCTAssertEqual(report.status, .available)
    XCTAssertEqual(report.optionalCapabilities, [])
    XCTAssertEqual(report.missingOptionalSymbols.count, 3)
  }
}
