import SwiftUI

struct MediaSurfacePresentation: Equatable, Sendable {
  let sessionID: String
  let title: String
  let artist: String?
  let album: String?
  let applicationName: String?
  let artworkData: Data?
  let isPlaying: Bool
  let isExpanded: Bool
  let isTemporaryExpansion: Bool
  let areControlsEnabled: Bool
  let progressFraction: Double?
  let progress: TimeInterval?
  let duration: TimeInterval?
  let canSeek: Bool
  let elapsedLabel: String?
  let remainingLabel: String?
  let canHideSource: Bool
  let primaryActions: [MediaSurfaceAction]
  let secondaryAction: MediaSurfaceAction?
  let appearance: MediaSurfaceAppearance

  init(payload: MediaSurfacePayload) {
    let session = payload.session
    sessionID = payload.sessionID
    title = session?.title ?? "正在播放"
    artist = session?.artist
    album =
      payload.appearance.showsMediaTitleExtras ? session?.album : nil
    applicationName =
      payload.appearance.showsMediaTitleExtras
      ? session?.applicationName : nil
    artworkData = session?.artworkData
    isPlaying = payload.playbackState == .playing
    isExpanded = payload.isExpanded
    isTemporaryExpansion = payload.isTemporaryExpansion
    areControlsEnabled = payload.areControlsEnabled
    appearance = payload.appearance
    progress = session?.progress
    duration = session?.duration
    canSeek = session?.capabilities.contains(.seek) == true
    canHideSource =
      session?.sourceBundleIdentifier.map(
        MediaPreferences.isPersistableBundleIdentifier
      ) == true

    if let progress,
      let duration,
      duration > 0
    {
      progressFraction = min(max(progress / duration, 0), 1)
      elapsedLabel = Self.timeLabel(progress)
      remainingLabel = "-\(Self.timeLabel(max(0, duration - progress)))"
    } else {
      progressFraction = nil
      elapsedLabel = nil
      remainingLabel = nil
    }

    var actions: [MediaSurfaceAction] = []
    let capabilities = session?.capabilities ?? []
    if capabilities.contains(.previous) {
      actions.append(.previous)
    }
    if capabilities.contains(.playPause) {
      actions.append(.togglePlayPause)
    }
    if capabilities.contains(.next) {
      actions.append(.next)
    }
    primaryActions = actions

    switch payload.appearance.secondaryAction {
    case .favorite where capabilities.contains(.favorite):
      secondaryAction = .favorite
    case .shuffle where capabilities.contains(.shuffle):
      secondaryAction = .shuffle
    case .repeatMode where capabilities.contains(.repeatMode):
      secondaryAction = .repeatMode
    case .repeatOne where capabilities.contains(.repeatOne):
      secondaryAction = .repeatOne
    case .copySource:
      if let publicShareURL = session?.publicShareURL {
        secondaryAction = .copySource(publicShareURL)
      } else {
        secondaryAction = nil
      }
    default:
      secondaryAction = nil
    }
  }

  private static func timeLabel(_ interval: TimeInterval) -> String {
    let seconds = max(0, Int(interval.rounded(.down)))
    return String(format: "%d:%02d", seconds / 60, seconds % 60)
  }
}

struct MediaSurfaceView: View {
  let payload: MediaSurfacePayload
  let presentationStyle: TopSurfacePresentationStyle
  let surfaceSize: CGSize
  let onAction: (MediaSurfaceAction) -> Void
  let onActivateSurface: () -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  private var presentation: MediaSurfacePresentation {
    MediaSurfacePresentation(payload: payload)
  }

  var body: some View {
    let artwork = MediaArtworkDecoder.decode(presentation.artworkData)

    Group {
      if presentation.isExpanded {
        expandedContent(artwork: artwork)
      } else {
        compactContent(artwork: artwork)
      }
    }
    .animation(artworkAnimation, value: payload.contentRevision)
    .foregroundStyle(.white)
    .frame(width: surfaceSize.width, height: surfaceSize.height)
    .background { mediaBackground(artwork: artwork) }
    .clipShape(surfaceShape)
    .overlay(alignment: .top) {
      if case .notchAttached = presentationStyle {
        Rectangle().fill(.black).frame(height: 1)
      }
    }
    .animation(
      reduceMotion ? nil : .easeInOut(duration: 0.22),
      value: payload.isExpanded
    )
    .opacity(payload.areControlsEnabled ? 1 : 0.72)
    .accessibilityElement(children: .contain)
    .accessibilityLabel(accessibilitySummary)
  }

  @ViewBuilder
  private func compactContent(artwork: CGImage?) -> some View {
    switch presentationStyle {
    case .floatingCapsule:
      Button(action: onActivateSurface) {
        HStack(spacing: 10) {
          compactArtwork(artwork: artwork)
          compactMetadata
          Spacer(minLength: 4)
          compactPlaybackIndicator
        }
        .padding(.horizontal, 10)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("media.compact")
    case .notchAttached(let notchSize):
      notchedCompactContent(notchSize: notchSize)
    }
  }

  private func notchedCompactContent(notchSize: CGSize) -> some View {
    let layout = NotchCompactContentLayout(
      surfaceSize: surfaceSize,
      obstructionSize: notchSize
    )
    return Button(action: onActivateSurface) {
      HStack(spacing: 0) {
        compactPlaybackIndicator
          .frame(width: layout.leftWingFrame.width)
        Color.clear
          .frame(width: layout.obstructionFrame.width)
          .accessibilityHidden(true)
        compactMetadata
          .frame(width: layout.rightWingFrame.width)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("media.compact")
  }

  private func compactArtwork(artwork: CGImage?) -> some View {
    Group {
      if let artwork,
        presentation.appearance.artworkTreatment != .gradient
      {
        Image(decorative: artwork, scale: 1)
          .resizable()
          .scaledToFill()
          .grayscale(
            presentation.appearance.artworkTreatment == .monochrome ? 1 : 0
          )
      } else {
        Image(systemName: "music.note")
          .font(.system(size: 12, weight: .semibold))
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(.white.opacity(0.1))
      }
    }
    .frame(width: 28, height: 28)
    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    .id(payload.contentRevision)
    .transition(artworkTransition)
  }

  private var compactMetadata: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text(presentation.title)
        .font(.caption.weight(.semibold))
        .lineLimit(1)
      if let artist = presentation.artist {
        Text(
          [artist, presentation.album]
            .compactMap { $0 }
            .joined(separator: " · ")
        )
        .font(.caption2)
        .foregroundStyle(.white.opacity(0.58))
        .lineLimit(1)
      }
    }
  }

  @ViewBuilder
  private var compactPlaybackIndicator: some View {
    if presentation.appearance.showsWaveform {
      MediaWaveformView(
        seed: presentation.sessionID,
        isPlaying: presentation.isPlaying
      )
      .frame(width: 34, height: 22)
    } else {
      Image(systemName: presentation.isPlaying ? "pause.fill" : "play.fill")
        .font(.system(size: 10, weight: .bold))
        .frame(width: 28, height: 28)
    }
  }

  private func expandedContent(artwork: CGImage?) -> some View {
    VStack(spacing: 0) {
      HStack(alignment: .top, spacing: 14) {
        expandedArtwork(artwork: artwork)
        VStack(alignment: .leading, spacing: 5) {
          if let applicationName = presentation.applicationName {
            Text(applicationName.uppercased())
              .font(.caption2.weight(.bold))
              .tracking(0.7)
              .foregroundStyle(.white.opacity(0.44))
          }
          Text(presentation.title)
            .font(.system(size: 17, weight: .semibold))
            .lineLimit(2)
          if let artist = presentation.artist {
            Text(artist)
              .font(.subheadline)
              .foregroundStyle(.white.opacity(0.64))
              .lineLimit(1)
          }
          if let album = presentation.album {
            Text(album)
              .font(.caption)
              .foregroundStyle(.white.opacity(0.44))
              .lineLimit(1)
          }
        }
        Spacer(minLength: 0)
        if presentation.canHideSource {
          Button {
            onAction(.hideSource)
          } label: {
            Image(systemName: "xmark")
              .font(.system(size: 9, weight: .bold))
              .frame(width: 24, height: 24)
              .background(.white.opacity(0.08), in: Circle())
          }
          .buttonStyle(.plain)
          .accessibilityLabel("隐藏当前媒体来源")
        }
      }

      if let progress = presentation.progressFraction {
        progressView(progress)
          .padding(.top, 14)
      }

      Spacer(minLength: 10)

      HStack(spacing: 15) {
        if let secondaryAction = presentation.secondaryAction {
          controlButton(for: secondaryAction, emphasized: false)
        }
        Spacer(minLength: 0)
        ForEach(
          Array(presentation.primaryActions.enumerated()),
          id: \.offset
        ) { _, action in
          controlButton(
            for: action,
            emphasized: action == .togglePlayPause
          )
        }
        Spacer(minLength: 0)
        if presentation.appearance.showsWaveform {
          MediaWaveformView(
            seed: presentation.sessionID,
            isPlaying: presentation.isPlaying
          )
          .frame(width: 38, height: 26)
        }
      }
    }
    .padding(.horizontal, 18)
    .padding(.top, expandedTopInset + 14)
    .padding(.bottom, 16)
    .accessibilityIdentifier("media.expanded")
  }

  private func expandedArtwork(artwork: CGImage?) -> some View {
    compactArtwork(artwork: artwork)
      .frame(width: 68, height: 68)
  }

  private func progressView(_ progress: Double) -> some View {
    VStack(spacing: 5) {
      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          Capsule().fill(.white.opacity(0.12))
          Capsule()
            .fill(.white.opacity(0.88))
            .frame(width: proxy.size.width * progress)
        }
        .contentShape(Rectangle())
        .gesture(
          DragGesture(minimumDistance: 0)
            .onEnded { value in
              seek(
                toFraction: value.location.x / max(proxy.size.width, 1)
              )
            }
        )
      }
      .frame(height: 3)
      HStack {
        Text(presentation.elapsedLabel ?? "")
        Spacer()
        Text(presentation.remainingLabel ?? "")
      }
      .font(.caption2.monospacedDigit())
      .foregroundStyle(.white.opacity(0.48))
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("播放进度")
    .accessibilityValue(
      "\(presentation.elapsedLabel ?? "")，剩余 \(presentation.remainingLabel?.dropFirst() ?? "")"
    )
    .accessibilityAdjustableAction { direction in
      let delta: Double = direction == .increment ? 10 : -10
      guard let progress = presentation.progress,
        let duration = presentation.duration,
        presentation.canSeek,
        presentation.areControlsEnabled
      else {
        return
      }
      onAction(.seek(to: min(max(progress + delta, 0), duration)))
    }
  }

  private func seek(toFraction rawFraction: CGFloat) {
    guard let duration = presentation.duration,
      presentation.canSeek,
      presentation.areControlsEnabled
    else {
      return
    }
    let fraction = min(max(Double(rawFraction), 0), 1)
    onAction(.seek(to: duration * fraction))
  }

  private func controlButton(
    for action: MediaSurfaceAction,
    emphasized: Bool
  ) -> some View {
    Button {
      onAction(action)
    } label: {
      Image(systemName: symbol(for: action))
        .font(.system(size: emphasized ? 15 : 11, weight: .bold))
        .frame(
          width: emphasized ? 42 : 32,
          height: emphasized ? 42 : 32
        )
        .background(
          emphasized ? Color.white : Color.white.opacity(0.08),
          in: Circle()
        )
        .foregroundStyle(emphasized ? .black : .white)
    }
    .buttonStyle(.plain)
    .disabled(!presentation.areControlsEnabled)
    .accessibilityLabel(label(for: action))
    .accessibilityIdentifier("media.action.\(identifier(for: action))")
  }

  private func symbol(for action: MediaSurfaceAction) -> String {
    switch action {
    case .previous: "backward.fill"
    case .togglePlayPause: presentation.isPlaying ? "pause.fill" : "play.fill"
    case .next: "forward.fill"
    case .seek: "slider.horizontal.3"
    case .hideSource: "xmark"
    case .favorite: "heart"
    case .shuffle: "shuffle"
    case .repeatMode: "repeat"
    case .repeatOne: "repeat.1"
    case .copySource: "doc.on.doc"
    }
  }

  private func label(for action: MediaSurfaceAction) -> String {
    switch action {
    case .previous: "上一首"
    case .togglePlayPause: presentation.isPlaying ? "暂停" : "播放"
    case .next: "下一首"
    case .seek: "调整播放进度"
    case .hideSource: "隐藏来源"
    case .favorite: "收藏"
    case .shuffle: "随机播放"
    case .repeatMode: "循环模式"
    case .repeatOne: "单曲循环"
    case .copySource: "复制来源链接"
    }
  }

  private func identifier(for action: MediaSurfaceAction) -> String {
    switch action {
    case .previous: "previous"
    case .togglePlayPause: "playPause"
    case .next: "next"
    case .seek: "seek"
    case .hideSource: "hideSource"
    case .favorite: "favorite"
    case .shuffle: "shuffle"
    case .repeatMode: "repeat"
    case .repeatOne: "repeatOne"
    case .copySource: "copySource"
    }
  }

  private var artworkAnimation: Animation? {
    guard presentation.appearance.showsArtworkFlip, !reduceMotion else {
      return .easeInOut(duration: 0.12)
    }
    return .easeInOut(duration: 0.46)
  }

  private var artworkTransition: AnyTransition {
    guard presentation.appearance.showsArtworkFlip, !reduceMotion else {
      return .opacity
    }
    return .asymmetric(
      insertion: .modifier(
        active: ArtworkFlipModifier(angle: -88, opacity: 0.25),
        identity: ArtworkFlipModifier(angle: 0, opacity: 1)
      ),
      removal: .modifier(
        active: ArtworkFlipModifier(angle: 88, opacity: 0),
        identity: ArtworkFlipModifier(angle: 0, opacity: 1)
      )
    )
  }

  private func mediaBackground(artwork: CGImage?) -> some View {
    ZStack {
      Color.black.opacity(
        reduceTransparency ? 1 : payload.appearance.backgroundOpacity
      )
      if payload.appearance.artworkTreatment == .gradient {
        LinearGradient(
          colors: [.purple.opacity(0.42), .blue.opacity(0.2), .clear],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      } else if let artwork {
        Image(decorative: artwork, scale: 1)
          .resizable()
          .scaledToFill()
          .grayscale(
            payload.appearance.artworkTreatment == .monochrome ? 1 : 0
          )
          .blur(radius: 28)
          .opacity(reduceTransparency ? 0 : 0.28)
      }
      LinearGradient(
        colors: [.black.opacity(0.06), .black.opacity(0.58)],
        startPoint: .top,
        endPoint: .bottom
      )
    }
  }

  private var surfaceShape: TopSurfaceShape {
    TopSurfaceShape(
      presentationStyle: presentationStyle,
      isExpanded: presentation.isExpanded
    )
  }

  private var expandedTopInset: CGFloat {
    guard case .notchAttached(let notchSize) = presentationStyle else {
      return 0
    }
    return notchSize.height
  }

  private var accessibilitySummary: String {
    [presentation.title, presentation.artist, presentation.applicationName]
      .compactMap { $0 }
      .joined(separator: "，")
  }
}

private struct ArtworkFlipModifier: ViewModifier {
  let angle: Double
  let opacity: Double

  func body(content: Content) -> some View {
    content
      .rotation3DEffect(
        .degrees(angle),
        axis: (x: 0, y: 1, z: 0),
        perspective: 0.72
      )
      .opacity(opacity)
  }
}
