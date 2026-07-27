import AppKit
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
  let progressSampleDate: Date?
  let canSeek: Bool
  let elapsedLabel: String?
  let remainingLabel: String?
  let canHideSource: Bool
  let primaryActions: [MediaSurfaceAction]
  let secondaryAction: MediaSurfaceAction?
  let appearance: MediaSurfaceAppearance
  let trackChangeDirection: MediaTrackDirection?
  let trackPeek: MediaTrackPeek?

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
    trackChangeDirection = payload.trackChangeDirection
    trackPeek = payload.trackPeek
    progress = session?.progress
    duration = session?.duration
    progressSampleDate = session?.progressSampleDate
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

  func resolvedProgress(at date: Date) -> TimeInterval? {
    guard let progress, let duration else {
      return nil
    }
    guard isPlaying, let progressSampleDate else {
      return progress
    }
    let elapsedSinceSample = max(
      0,
      date.timeIntervalSince(progressSampleDate)
    )
    return min(progress + elapsedSinceSample, duration)
  }

  func resolvedProgressFraction(at date: Date) -> Double? {
    guard let progress = resolvedProgress(at: date),
      let duration,
      duration > 0
    else {
      return nil
    }
    return min(max(progress / duration, 0), 1)
  }

  func resolvedElapsedLabel(at date: Date) -> String? {
    resolvedProgress(at: date).map(Self.timeLabel)
  }

  func resolvedRemainingLabel(at date: Date) -> String? {
    guard let progress = resolvedProgress(at: date), let duration else {
      return nil
    }
    return "-\(Self.timeLabel(max(0, duration - progress)))"
  }

  static func timeLabel(_ interval: TimeInterval) -> String {
    let seconds = max(0, Int(interval.rounded(.down)))
    return String(format: "%d:%02d", seconds / 60, seconds % 60)
  }
}

struct MediaExpandedLayoutMetrics: Equatable {
  let surfaceWidth: CGFloat

  let horizontalInset: CGFloat = 22
  let progressSpacing: CGFloat = 9
  let elapsedLabelWidth: CGFloat = 27
  let remainingLabelWidth: CGFloat = 32
  let progressTrackHeight: CGFloat = 4
  let progressHitTargetHeight: CGFloat = 14
  let controlsHorizontalInset: CGFloat = 8
  let bottomInset: CGFloat = 22

  var progressTrackLeadingEdge: CGFloat {
    horizontalInset + elapsedLabelWidth + progressSpacing
  }

  var controlCenters: [CGFloat] {
    let availableWidth = max(
      0,
      surfaceWidth - (2 * controlsHorizontalInset)
    )
    let slotWidth = availableWidth / 5
    return (0..<5).map {
      controlsHorizontalInset + ((CGFloat($0) + 0.5) * slotWidth)
    }
  }
}

struct MediaSurfaceView: View {
  let payload: MediaSurfacePayload
  let presentationStyle: TopSurfacePresentationStyle
  let surfaceSize: CGSize
  let onAction: (MediaSurfaceAction) -> Void
  let onActivateSurface: () -> Void
  let onRequestKeyboardNavigation: () -> Void
  let onSurfaceNavigation: (SurfaceGestureIntent) -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @AccessibilityFocusState private var isCompactMediaAccessibilityFocused: Bool

  private var presentation: MediaSurfacePresentation {
    MediaSurfacePresentation(payload: payload)
  }

  var body: some View {
    let artwork = MediaArtworkDecoder.resolve(presentation.artworkData)

    Group {
      if payload.level == .hardware && presentation.trackPeek == nil {
        Color.clear
      } else if presentation.isExpanded {
        expandedContent(
          artwork: artwork.image,
          waveformAccent: artwork.accent
        )
      } else if let trackPeek = presentation.trackPeek {
        trackPeekContent(
          trackPeek,
          artwork: artwork.image,
          waveformAccent: artwork.accent
        )
      } else {
        compactContent(
          artwork: artwork.image,
          waveformAccent: artwork.accent
        )
        .accessibilityFocused($isCompactMediaAccessibilityFocused)
      }
    }
    .animation(artworkAnimation, value: payload.contentRevision)
    .foregroundStyle(.white)
    .frame(width: surfaceSize.width, height: surfaceSize.height)
    .background { mediaBackground(artwork: artwork.image) }
    .clipShape(surfaceShape)
    .animation(
      reduceMotion ? nil : .easeInOut(duration: 0.22),
      value: payload.isExpanded
    )
    .animation(
      reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.82),
      value: payload.trackChangeDirection
    )
    .animation(
      reduceMotion
        ? nil : .spring(response: 0.4, dampingFraction: 0.68),
      value: payload.trackPeek
    )
    .opacity(payload.areControlsEnabled ? 1 : 0.72)
    .accessibilityElement(children: .contain)
    .accessibilityLabel(accessibilitySummary)
    .modifier(
      SurfaceAccessibilityNavigationModifier(
        component: .media,
        level: payload.level,
        onNavigate: onSurfaceNavigation,
        onActionPerformed: handleAccessibilityNavigationAction
      )
    )
    .onChange(of: presentation.isExpanded) { _, isExpanded in
      if isExpanded {
        isCompactMediaAccessibilityFocused = false
      }
    }
  }

  private func handleAccessibilityNavigationAction(
    _ action: SurfaceAccessibilityNavigationAction
  ) {
    guard action.focusDestination == .compactMedia else {
      return
    }
    Task { @MainActor in
      isCompactMediaAccessibilityFocused = true
      guard let announcement = action.announcement,
        let application = NSApp
      else {
        return
      }
      NSAccessibility.post(
        element: application,
        notification: .announcementRequested,
        userInfo: [
          .announcement: announcement,
          .priority: NSAccessibilityPriorityLevel.medium.rawValue,
        ]
      )
    }
  }

  @ViewBuilder
  private func compactContent(
    artwork: CGImage?,
    waveformAccent: MediaArtworkAccent
  ) -> some View {
    switch presentationStyle {
    case .floatingCapsule:
      Button(action: onActivateSurface) {
        HStack(spacing: 10) {
          artworkView(artwork: artwork, size: 28, cornerRadius: 7)
          compactMetadata
          Spacer(minLength: 4)
          compactPlaybackIndicator(accent: waveformAccent)
        }
        .padding(.horizontal, 10)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("media.compact")
    case .notchAttached(let notchSize):
      notchedCompactContent(
        notchSize: notchSize,
        artwork: artwork,
        waveformAccent: waveformAccent
      )
    }
  }

  private func notchedCompactContent(
    notchSize: CGSize,
    artwork: CGImage?,
    waveformAccent: MediaArtworkAccent
  ) -> some View {
    let layout = DirectionalMediaNotchLayout(
      surfaceSize: surfaceSize,
      obstructionSize: notchSize,
      baseWingWidth: SurfaceMetrics.mediaNotchedWingWidth,
      extensionDirection: presentation.trackChangeDirection
    )
    return Button(action: onActivateSurface) {
      HStack(spacing: 0) {
        artworkView(artwork: artwork, size: 20, cornerRadius: 6)
          .frame(width: layout.leftWingFrame.width)
        Color.clear
          .frame(width: layout.obstructionFrame.width)
          .accessibilityHidden(true)
        notchedCompactPlaybackIndicator(accent: waveformAccent)
          .frame(width: layout.rightWingFrame.width)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("media.compact")
  }

  @ViewBuilder
  private func trackPeekContent(
    _ peek: MediaTrackPeek,
    artwork: CGImage?,
    waveformAccent: MediaArtworkAccent
  ) -> some View {
    switch presentationStyle {
    case .floatingCapsule:
      trackPeekButton(
        peek,
        artwork: artwork,
        waveformAccent: waveformAccent
      )
    case .notchAttached(let notchSize):
      notchedTrackPeekContent(
        peek,
        notchSize: notchSize,
        artwork: artwork,
        waveformAccent: waveformAccent
      )
    }
  }

  private func trackPeekButton(
    _ peek: MediaTrackPeek,
    artwork: CGImage?,
    waveformAccent: MediaArtworkAccent
  ) -> some View {
    Button(action: onActivateSurface) {
      HStack(spacing: 9) {
        if artwork != nil {
          artworkView(artwork: artwork, size: 34, cornerRadius: 9)
        }
        trackPeekMetadata(peek)
        Spacer(minLength: 4)
        compactPlaybackIndicator(accent: waveformAccent)
      }
      .padding(.horizontal, 14)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("media.track-peek")
  }

  private func notchedTrackPeekContent(
    _ peek: MediaTrackPeek,
    notchSize: CGSize,
    artwork: CGImage?,
    waveformAccent: MediaArtworkAccent
  ) -> some View {
    let layout = MediaNotchQuickPeekLayout(
      surfaceSize: surfaceSize,
      obstructionSize: notchSize
    )

    return Button(action: onActivateSurface) {
      ZStack(alignment: .topLeading) {
        artworkView(artwork: artwork, size: 20, cornerRadius: 6)
          .frame(
            width: layout.leftWingFrame.width,
            height: layout.leftWingFrame.height
          )
          .clipped()
          .position(
            x: layout.leftWingFrame.midX,
            y: layout.leftWingFrame.midY
          )
        notchedCompactPlaybackIndicator(accent: waveformAccent)
          .frame(
            width: layout.rightWingFrame.width,
            height: layout.rightWingFrame.height
          )
          .clipped()
          .position(
            x: layout.rightWingFrame.midX,
            y: layout.rightWingFrame.midY
          )
        notchedTrackPeekMetadata(peek)
          .frame(
            width: layout.metadataFrame.width,
            height: layout.metadataFrame.height,
            alignment: .center
          )
          .position(
            x: layout.metadataFrame.midX,
            y: layout.metadataFrame.midY
          )
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("media.track-peek")
  }

  private func trackPeekMetadata(
    _ peek: MediaTrackPeek
  ) -> some View {
    VStack(alignment: .leading, spacing: 1) {
      Text(peek.title)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.white.opacity(0.92))
        .lineLimit(1)
        .truncationMode(.tail)
      if let artist = peek.artist {
        Text(artist)
          .font(.system(size: 10.5))
          .foregroundStyle(.white.opacity(0.58))
          .lineLimit(1)
          .truncationMode(.tail)
      }
    }
    .id(peek)
    .transition(trackPeekTextTransition)
  }

  private func notchedTrackPeekMetadata(
    _ peek: MediaTrackPeek
  ) -> some View {
    HStack(spacing: 4) {
      Image(systemName: "music.note")
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(.white.opacity(0.38))
      notchedTrackPeekLabel(peek)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.white.opacity(0.82))
        .lineLimit(1)
        .truncationMode(.tail)
    }
    .id(peek)
    .transition(trackPeekTextTransition)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      [peek.title, peek.artist].compactMap { $0 }.joined(separator: "，")
    )
  }

  private func notchedTrackPeekLabel(_ peek: MediaTrackPeek) -> Text {
    guard let artist = peek.artist, !artist.isEmpty else {
      return Text(peek.title)
    }
    return Text(peek.title)
      + Text(" · ").foregroundColor(.white.opacity(0.34))
      + Text(artist).foregroundColor(.white.opacity(0.58))
  }

  private func artworkView(
    artwork: CGImage?,
    size: CGFloat,
    cornerRadius: CGFloat
  ) -> some View {
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
          .font(.system(size: max(8, size * 0.42), weight: .semibold))
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(.white.opacity(0.1))
      }
    }
    .frame(width: size, height: size)
    .clipShape(
      RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    )
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
  private func compactPlaybackIndicator(
    accent: MediaArtworkAccent
  ) -> some View {
    if presentation.appearance.showsWaveform {
      MediaWaveformView(
        seed: presentation.sessionID,
        isPlaying: presentation.isPlaying,
        accent: accent
      )
      .frame(width: 34, height: 22)
    } else {
      Image(systemName: presentation.isPlaying ? "pause.fill" : "play.fill")
        .font(.system(size: 10, weight: .bold))
        .frame(width: 28, height: 28)
    }
  }

  @ViewBuilder
  private func notchedCompactPlaybackIndicator(
    accent: MediaArtworkAccent
  ) -> some View {
    if presentation.appearance.showsWaveform {
      MediaWaveformView(
        seed: presentation.sessionID,
        isPlaying: presentation.isPlaying,
        style: .notchedCompact,
        accent: accent
      )
      .frame(
        width: MediaWaveformStyle.notchedCompact.intrinsicWidth,
        height: MediaWaveformStyle.notchedCompact.maximumHeight
      )
    } else {
      Image(systemName: presentation.isPlaying ? "pause.fill" : "play.fill")
        .font(.system(size: 9, weight: .bold))
        .frame(width: 18, height: 18)
    }
  }

  private func expandedContent(
    artwork: CGImage?,
    waveformAccent: MediaArtworkAccent
  ) -> some View {
    let metrics = MediaExpandedLayoutMetrics(
      surfaceWidth: surfaceSize.width
    )

    return VStack(spacing: 0) {
      HStack(alignment: .bottom, spacing: 16) {
        expandedArtwork(artwork: artwork)
        VStack(alignment: .leading, spacing: 2) {
          Text(presentation.title)
            .font(.system(size: 15, weight: .semibold))
            .lineLimit(1)
          if let artist = presentation.artist {
            Text(artist)
              .font(.system(size: 13))
              .foregroundStyle(.white.opacity(0.58))
              .lineLimit(1)
          }
        }
        .padding(.bottom, 4)
        Spacer(minLength: 0)
        if presentation.appearance.showsWaveform {
          MediaWaveformView(
            seed: presentation.sessionID,
            isPlaying: presentation.isPlaying,
            style: .expanded,
            accent: waveformAccent
          )
          .frame(
            width: MediaWaveformStyle.expanded.intrinsicWidth,
            height: MediaWaveformStyle.expanded.maximumHeight
          )
          .padding(.bottom, 22)
        }
      }
      .frame(height: 56)
      .padding(.horizontal, metrics.horizontalInset)

      if presentation.progressFraction != nil {
        TimelineView(
          .animation(
            minimumInterval: 1,
            paused: !presentation.isPlaying
          )
        ) { context in
          if let progress = presentation.resolvedProgressFraction(
            at: context.date
          ) {
            progressView(
              progress,
              elapsedLabel:
                presentation.resolvedElapsedLabel(at: context.date)
                ?? "",
              remainingLabel:
                presentation.resolvedRemainingLabel(at: context.date)
                ?? "",
              metrics: metrics
            )
          }
        }
        .padding(.top, 13)
        .padding(.horizontal, metrics.horizontalInset)
      }

      Spacer(minLength: 10)

      expandedControls
        .padding(.horizontal, metrics.controlsHorizontalInset)
    }
    .padding(.top, 14)
    .padding(.bottom, metrics.bottomInset)
  }

  private func expandedArtwork(artwork: CGImage?) -> some View {
    artworkView(artwork: artwork, size: 56, cornerRadius: 14)
  }

  private func progressView(
    _ progress: Double,
    elapsedLabel: String,
    remainingLabel: String,
    metrics: MediaExpandedLayoutMetrics
  ) -> some View {
    HStack(spacing: metrics.progressSpacing) {
      Text(elapsedLabel)
        .frame(
          width: metrics.elapsedLabelWidth,
          alignment: .trailing
        )
      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          Capsule().fill(.white.opacity(0.18))
          Capsule()
            .fill(.white.opacity(0.54))
            .frame(width: proxy.size.width * progress)
        }
        .frame(height: metrics.progressTrackHeight)
        .frame(maxHeight: .infinity)
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
      .frame(height: metrics.progressHitTargetHeight)
      Text(remainingLabel)
        .frame(
          width: metrics.remainingLabelWidth,
          alignment: .leading
        )
    }
    .frame(height: metrics.progressHitTargetHeight)
    .font(.caption2.monospacedDigit())
    .foregroundStyle(.white.opacity(0.48))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("播放进度")
    .accessibilityValue(
      "\(elapsedLabel)，剩余 \(remainingLabel.dropFirst())"
    )
    .accessibilityAdjustableAction { direction in
      let delta: Double = direction == .increment ? 10 : -10
      guard let progress = presentation.resolvedProgress(at: Date()),
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

  private var expandedControls: some View {
    HStack(spacing: 0) {
      actionSlot(presentation.secondaryAction)
      actionSlot(
        presentation.primaryActions.contains(.previous) ? .previous : nil
      )
      actionSlot(
        presentation.primaryActions.contains(.togglePlayPause)
          ? .togglePlayPause : nil
      )
      actionSlot(
        presentation.primaryActions.contains(.next) ? .next : nil
      )
      Color.clear
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }
    .frame(height: 32)
  }

  @ViewBuilder
  private func actionSlot(_ action: MediaSurfaceAction?) -> some View {
    Group {
      if let action {
        controlButton(for: action)
      } else {
        Color.clear.accessibilityHidden(true)
      }
    }
    .frame(maxWidth: .infinity)
  }

  private func controlButton(for action: MediaSurfaceAction) -> some View {
    Button {
      onAction(action)
    } label: {
      Image(systemName: symbol(for: action))
        .font(
          .system(
            size: controlSymbolSize(for: action),
            weight: .semibold
          )
        )
        .frame(width: 32, height: 32)
        .foregroundStyle(.white)
    }
    .buttonStyle(.plain)
    .disabled(!presentation.areControlsEnabled)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(label(for: action))
    .accessibilityIdentifier("media.action.\(identifier(for: action))")
  }

  private func symbol(for action: MediaSurfaceAction) -> String {
    switch action {
    case .previous: "backward.end.fill"
    case .togglePlayPause: presentation.isPlaying ? "pause.fill" : "play.fill"
    case .next: "forward.end.fill"
    case .seek: "slider.horizontal.3"
    case .hideSource: "xmark"
    case .favorite: "heart"
    case .shuffle: "shuffle"
    case .repeatMode: "repeat"
    case .repeatOne: "repeat.1"
    case .copySource: "doc.on.doc"
    }
  }

  private func controlSymbolSize(for action: MediaSurfaceAction) -> CGFloat {
    switch action {
    case .previous, .next:
      22
    case .togglePlayPause:
      25
    default:
      13
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

  @ViewBuilder
  private func mediaBackground(artwork: CGImage?) -> some View {
    switch presentationStyle {
    case .notchAttached:
      Color.black
    case .floatingCapsule:
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
  }

  private var surfaceShape: TopSurfaceShape {
    TopSurfaceShape(
      presentationStyle: presentationStyle,
      isExpanded: presentation.isExpanded,
      isQuickPeek: presentation.trackPeek != nil
    )
  }

  private var trackPeekTextTransition: AnyTransition {
    guard !reduceMotion else {
      return .opacity
    }
    return .asymmetric(
      insertion: .offset(x: 34).combined(with: .opacity),
      removal: .offset(x: -34).combined(with: .opacity)
    )
  }

  private var accessibilitySummary: String {
    [presentation.title, presentation.artist, presentation.applicationName]
      .compactMap { $0 }
      .joined(separator: "，")
  }
}

struct DirectionalMediaNotchLayout: Equatable {
  let surfaceSize: CGSize
  let obstructionSize: CGSize
  let baseWingWidth: CGFloat
  let extensionDirection: MediaTrackDirection?

  var leftWingFrame: CGRect {
    CGRect(
      x: 0,
      y: 0,
      width: leftWingWidth,
      height: topRowHeight
    )
  }

  var obstructionFrame: CGRect {
    CGRect(
      x: leftWingFrame.maxX,
      y: 0,
      width: obstructionWidth,
      height: min(obstructionSize.height, surfaceSize.height)
    )
  }

  var rightWingFrame: CGRect {
    CGRect(
      x: obstructionFrame.maxX,
      y: 0,
      width: rightWingWidth,
      height: topRowHeight
    )
  }

  var oppositeWingFrame: CGRect {
    switch extensionDirection {
    case .previous:
      rightWingFrame
    case .next:
      leftWingFrame
    case nil:
      .zero
    }
  }

  var changingWingFrame: CGRect {
    switch extensionDirection {
    case .previous:
      leftWingFrame
    case .next:
      rightWingFrame
    case nil:
      .zero
    }
  }

  private var topRowHeight: CGFloat {
    min(max(0, obstructionSize.height), surfaceSize.height)
  }

  private var obstructionWidth: CGFloat {
    min(max(0, obstructionSize.width), surfaceSize.width)
  }

  private var availableWingWidth: CGFloat {
    max(0, surfaceSize.width - obstructionWidth)
  }

  private var resolvedBaseWingWidth: CGFloat {
    min(max(0, baseWingWidth), availableWingWidth / 2)
  }

  private var directionalExtensionWidth: CGFloat {
    max(0, availableWingWidth - (2 * resolvedBaseWingWidth))
  }

  private var leftWingWidth: CGFloat {
    switch extensionDirection {
    case .previous:
      resolvedBaseWingWidth + directionalExtensionWidth
    case .next:
      resolvedBaseWingWidth
    case nil:
      availableWingWidth / 2
    }
  }

  private var rightWingWidth: CGFloat {
    max(0, availableWingWidth - leftWingWidth)
  }
}

struct MediaNotchQuickPeekLayout: Equatable {
  private static let metadataHorizontalInset: CGFloat = 8

  let surfaceSize: CGSize
  let obstructionSize: CGSize

  var leftWingFrame: CGRect {
    CGRect(x: 0, y: 0, width: wingWidth, height: topRowHeight)
  }

  var obstructionFrame: CGRect {
    CGRect(
      x: leftWingFrame.maxX,
      y: 0,
      width: obstructionWidth,
      height: topRowHeight
    )
  }

  var rightWingFrame: CGRect {
    CGRect(
      x: obstructionFrame.maxX,
      y: 0,
      width: wingWidth,
      height: topRowHeight
    )
  }

  var metadataFrame: CGRect {
    let inset = min(
      Self.metadataHorizontalInset,
      max(0, obstructionFrame.width / 2)
    )
    return CGRect(
      x: obstructionFrame.minX + inset,
      y: topRowHeight,
      width: max(0, obstructionFrame.width - (2 * inset)),
      height: max(0, surfaceSize.height - topRowHeight)
    )
  }

  private var topRowHeight: CGFloat {
    min(max(0, obstructionSize.height), surfaceSize.height)
  }

  private var obstructionWidth: CGFloat {
    min(max(0, obstructionSize.width), surfaceSize.width)
  }

  private var wingWidth: CGFloat {
    max(0, (surfaceSize.width - obstructionWidth) / 2)
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
