import Foundation

#if DEBUG
  actor MediaFixtureAdapter: MediaSessionAdapter {
    private let onSnapshot: MediaAdapterSnapshotDelivery
    private var contentRevision: UInt64 = 1
    private var isStarted = false
    private var playbackState = MediaPlaybackState.playing

    init(onSnapshot: @escaping MediaAdapterSnapshotDelivery) {
      self.onSnapshot = onSnapshot
    }

    func start() async -> MediaCompatibilityReport {
      isStarted = true
      await onSnapshot(makeSnapshot())
      return MediaCompatibilityReport(
        status: .available,
        missingMandatorySymbols: [],
        missingOptionalSymbols: [],
        optionalCapabilities: [.seek, .shuffle, .repeatMode]
      )
    }

    func stop() async {
      isStarted = false
      await onSnapshot(nil)
    }

    func send(
      _ action: MediaSurfaceAction,
      to sessionID: String,
      capabilityRevision: UInt64
    ) async -> MediaCommandDispatchResult {
      guard isStarted, sessionID == "fixture:netease",
        capabilityRevision == 1
      else {
        return .rejected
      }
      if action == .next || action == .previous {
        contentRevision &+= 1
        await onSnapshot(makeSnapshot())
      } else if action == .togglePlayPause {
        playbackState = playbackState == .playing ? .paused : .playing
        await onSnapshot(makeSnapshot())
      }
      return .accepted
    }

    private func makeSnapshot() -> MediaAdapterSnapshot {
      MediaAdapterSnapshot(
        session: MediaSession.normalize(
          .init(
            sessionID: "fixture:netease",
            sourceBundleIdentifier: "com.netease.163music",
            title: "Keep3 Fixture \(contentRevision)",
            artist: "Media QA",
            album: "Visual System 2.0",
            applicationName: "网易云音乐",
            duration: 240,
            progress: Double(contentRevision * 12),
            capabilities: MediaCapability.allCases.map(\.rawValue)
          )
        )!,
        playbackState: playbackState,
        capabilityRevision: 1,
        contentRevision: contentRevision
      )
    }
  }
#endif
