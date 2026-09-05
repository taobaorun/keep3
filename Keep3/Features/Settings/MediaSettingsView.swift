import SwiftUI

struct MediaSettingsView: View {
  @ObservedObject var preferences: MediaPreferences

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      MediaSettingsPreview(preferences: preferences)
      behaviorSection
      appearanceSection
      sourceSection
    }
  }

  private var behaviorSection: some View {
    GroupBox("播放接管") {
      VStack(alignment: .leading, spacing: 12) {
        Toggle(
          "在顶部表面显示正在播放",
          isOn: binding(
            get: { preferences.isMediaFirstEnabled },
            set: preferences.setMediaFirstEnabled
          )
        )
        .accessibilityIdentifier("settings.media.enabled")

        Toggle(
          "切歌时显示歌曲信息",
          isOn: binding(
            get: { preferences.isQuickPeekEnabled },
            set: preferences.setQuickPeekEnabled
          )
        )
        .accessibilityIdentifier("settings.media.quickPeek")

        if preferences.isQuickPeekEnabled {
          HStack {
            Text("停留时长")
            Slider(
              value: binding(
                get: { preferences.quickPeekDuration },
                set: preferences.setQuickPeekDuration
              ),
              in: MediaPreferences.quickPeekDurationRange,
              step: 0.5
            )
            Text(
              preferences.quickPeekDuration.formatted(
                .number.precision(.fractionLength(1))
              ) + " 秒"
            )
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .frame(width: 52, alignment: .trailing)
          }
          .accessibilityIdentifier("settings.media.quickPeekDuration")
        }

        Text("左右双指滑动切歌；确认成功后以轻量提示显示歌名和歌手，不会打断当前工作。")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var appearanceSection: some View {
    GroupBox("外观与控制") {
      VStack(alignment: .leading, spacing: 12) {
        Picker(
          "封面处理",
          selection: binding(
            get: { preferences.artworkTreatment },
            set: preferences.setArtworkTreatment
          )
        ) {
          Text("原色").tag(MediaArtworkTreatment.artwork)
          Text("单色").tag(MediaArtworkTreatment.monochrome)
          Text("渐变").tag(MediaArtworkTreatment.gradient)
        }

        Toggle(
          "显示动态波形",
          isOn: binding(
            get: { preferences.showsWaveform },
            set: preferences.setShowsWaveform
          )
        )

        Toggle(
          "切歌时翻转封面",
          isOn: binding(
            get: { preferences.showsArtworkFlip },
            set: preferences.setShowsArtworkFlip
          )
        )

        Toggle(
          "显示媒体标题附加信息",
          isOn: binding(
            get: { preferences.showsMediaTitleExtras },
            set: preferences.setShowsMediaTitleExtras
          )
        )

        Picker(
          "辅助按钮",
          selection: binding(
            get: { preferences.secondaryAction },
            set: preferences.setSecondaryAction
          )
        ) {
          Text("自动隐藏").tag(MediaSecondaryAction.none)
          Text("收藏").tag(MediaSecondaryAction.favorite)
          Text("随机播放").tag(MediaSecondaryAction.shuffle)
          Text("循环模式").tag(MediaSecondaryAction.repeatMode)
          Text("单曲循环").tag(MediaSecondaryAction.repeatOne)
          Text("复制来源链接").tag(MediaSecondaryAction.copySource)
        }

        Text("只有当前播放器明确提供对应能力时，辅助按钮才会出现。")
          .font(.caption)
          .foregroundStyle(.secondary)

        HStack {
          Text("背景浓度")
          Slider(
            value: binding(
              get: { preferences.backgroundOpacity },
              set: preferences.setBackgroundOpacity
            ),
            in: MediaPreferences.backgroundOpacityRange
          )
          Text("\(Int(preferences.backgroundOpacity * 100))%")
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .frame(width: 42, alignment: .trailing)
        }
      }
    }
  }

  private var sourceSection: some View {
    GroupBox("来源规则") {
      VStack(alignment: .leading, spacing: 10) {
        Toggle(
          "播放器在最前方时不显示胶囊",
          isOn: binding(
            get: { preferences.hidesFrontmostSource },
            set: preferences.setHidesFrontmostSource
          )
        )
        Text("暂停或停止后仍可手动切回播放器；退出或隐藏来源后移除。")
          .font(.caption)
          .foregroundStyle(.secondary)

        if !preferences.suppressedBundleIdentifiers.isEmpty {
          Divider()
          Text("已隐藏的播放器")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
          ForEach(
            preferences.suppressedBundleIdentifiers.sorted(),
            id: \.self
          ) { identifier in
            HStack {
              Text(identifier)
                .font(.caption.monospaced())
                .lineLimit(1)
              Spacer()
              Button("恢复显示") {
                preferences.setSuppressed(
                  identifier,
                  isSuppressed: false
                )
              }
              .buttonStyle(.link)
            }
          }
        }

        Divider()
        Label(
          permissionDescription,
          systemImage: permissionSymbol
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
    }
  }

  private var permissionDescription: String {
    switch preferences.automationPermissionPosture {
    case .notRequested:
      "增强播放器操作尚未请求自动化权限；基础媒体控制不依赖它。"
    case .granted:
      "增强播放器操作已获授权。"
    case .denied:
      "增强播放器操作未获授权；基础媒体控制仍可使用。"
    }
  }

  private var permissionSymbol: String {
    switch preferences.automationPermissionPosture {
    case .granted:
      "checkmark.shield"
    case .notRequested:
      "shield"
    case .denied:
      "exclamationmark.shield"
    }
  }

  private func binding<Value: Sendable>(
    get: @escaping @MainActor @Sendable () -> Value,
    set: @escaping @MainActor @Sendable (Value) -> Void
  ) -> Binding<Value> {
    Binding(get: get, set: set)
  }
}

private struct MediaSettingsPreview: View {
  let preferences: MediaPreferences

  private var payload: MediaSurfacePayload {
    let session = MediaSession.normalize(
      .init(
        sessionID: "media-settings-preview",
        sourceBundleIdentifier: "com.netease.163music",
        title: "夏夜晚风",
        artist: "Keep3 Radio",
        applicationName: "网易云音乐",
        publicShareURL: "https://music.163.com/song?id=keep3-preview",
        duration: 238,
        progress: 72,
        capabilities: MediaCapability.allCases.map(\.rawValue)
      )
    )
    return MediaSurfacePayload(
      sessionID: "media-settings-preview",
      contentRevision: preferences.showsArtworkFlip ? 2 : 1,
      isExpanded: false,
      areControlsEnabled: true,
      session: session,
      playbackState: .playing,
      capabilityRevision: 1,
      appearance: preferences.appearance
    )
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("实时预览")
        .font(.headline)
      MediaSurfaceView(
        payload: payload,
        presentationStyle: .floatingCapsule,
        surfaceSize: CGSize(width: 310, height: 44),
        onAction: { _ in },
        onActivateSurface: {},
        onRequestKeyboardNavigation: {},
        onSurfaceNavigation: { _ in }
      )
      .allowsHitTesting(false)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("媒体胶囊外观预览：夏夜晚风，Keep3 Radio")
      .accessibilityIdentifier("settings.media.preview.surface")
      Text("预览使用与顶部媒体胶囊相同的外观与辅助功能规则。")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      .quaternary,
      in: RoundedRectangle(cornerRadius: 16, style: .continuous)
    )
    .accessibilityIdentifier("settings.media.preview")
  }
}
