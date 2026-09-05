import SwiftUI

struct SettingsView: View {
  @ObservedObject var preferences: AppPreferences
  @ObservedObject var mediaPreferences: MediaPreferences
  @ObservedObject var calendarPreferences: CalendarPreferences
  @ObservedObject var calendarCoordinator: CalendarSessionCoordinator
  @ObservedObject var launchAtLoginController: LaunchAtLoginController
  @ObservedObject var updateController: SparkleUpdateController
  @State private var selection: SettingsCategory = .general

  var body: some View {
    HSplitView {
      SettingsSidebarView(selection: $selection)
        .frame(minWidth: 220, idealWidth: 240, maxWidth: 280)

      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          Label(selection.title, systemImage: selection.symbol)
            .font(.largeTitle.weight(.semibold))
          selectedSettings
        }
        .padding(28)
      }
      .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(minWidth: 720, minHeight: 520)
    .accessibilityIdentifier("settings.root")
  }

  @ViewBuilder
  private var selectedSettings: some View {
    switch selection {
    case .general:
      generalSettings
    case .focusSurface:
      FocusSurfaceSettingsView(preferences: preferences)
    case .rotation:
      rotationSettings
    case .interaction:
      interactionSettings
    case .accessibility:
      accessibilitySettings
    case .media:
      MediaSettingsView(preferences: mediaPreferences)
    case .calendar:
      CalendarSettingsView(
        preferences: calendarPreferences,
        coordinator: calendarCoordinator
      )
    }
  }

  private var generalSettings: some View {
    VStack(alignment: .leading, spacing: 20) {
      GroupBox("启动") {
        VStack(alignment: .leading, spacing: 8) {
          Toggle(
            "登录时启动 Keep3",
            isOn: Binding(
              get: { launchAtLoginController.isOn },
              set: { launchAtLoginController.setEnabled($0) }
            )
          )
          .accessibilityIdentifier("settings.launchAtLogin")

          if let message = launchAtLoginController.message {
            Label(message, systemImage: "info.circle")
              .font(.caption)
              .foregroundStyle(.secondary)
              .accessibilityLabel("登录时启动提示：\(message)")
          }
        }
      }

      UpdateSettingsView(updateController: updateController)
    }
  }

  private var rotationSettings: some View {
    GroupBox("轮播") {
      VStack(alignment: .leading, spacing: 12) {
        Toggle(
          "自动轮播",
          isOn: Binding(
            get: { preferences.isAutomaticRotationEnabled },
            set: { preferences.setAutomaticRotationEnabled($0) }
          )
        )
        .accessibilityIdentifier("settings.autoRotation")

        DurationSettingRow(
          title: "当前重点",
          identifier: "settings.currentDuration",
          value: Binding(
            get: { preferences.currentFocusDuration },
            set: { preferences.setCurrentFocusDuration($0) }
          ),
          range: RotationDurations.currentFocusRange,
          step: 10,
          isEnabled: preferences.isAutomaticRotationEnabled
        )
        DurationSettingRow(
          title: "其他重点",
          identifier: "settings.secondaryDuration",
          value: Binding(
            get: { preferences.secondaryDuration },
            set: { preferences.setSecondaryDuration($0) }
          ),
          range: RotationDurations.secondaryRange,
          step: 1,
          isEnabled: preferences.isAutomaticRotationEnabled
        )
      }
    }
  }

  private var interactionSettings: some View {
    GroupBox("顶部表面") {
      VStack(alignment: .leading, spacing: 10) {
        Label("悬停：从硬件状态轻量预览", systemImage: "cursorarrow.motionlines")
        Label("点击：展开当前组件", systemImage: "hand.tap")
        Label("上下双指：改变层级并切换组件", systemImage: "arrow.up.arrow.down")
        Label("左右双指：播放器切歌", systemImage: "arrow.left.arrow.right")
      }
    }
  }

  private var accessibilitySettings: some View {
    GroupBox("系统辅助功能") {
      Text("减少动态效果和减少透明度会在运行时覆盖预览，而不会改写你的设置。")
    }
  }

}

@MainActor
private struct DurationSettingRow: View {
  let title: String
  let identifier: String
  @Binding var value: TimeInterval
  let range: ClosedRange<TimeInterval>
  let step: TimeInterval
  let isEnabled: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(title)
        Spacer()
        Text("\(Int(value)) 秒")
          .foregroundStyle(.secondary)
      }
      Slider(value: $value, in: range, step: step)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(title)
        .accessibilityValue("\(Int(value)) 秒")
    }
    .disabled(!isEnabled)
  }
}
