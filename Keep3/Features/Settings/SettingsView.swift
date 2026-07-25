import SwiftUI

struct SettingsView: View {
  @ObservedObject var preferences: AppPreferences
  @ObservedObject var launchAtLoginController: LaunchAtLoginController
  @State private var selection: SettingsCategory = .general

  var body: some View {
    NavigationSplitView {
      SettingsSidebarView(selection: $selection)
        .navigationSplitViewColumnWidth(min: 180, ideal: 210)
    } detail: {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          Label(selection.title, systemImage: selection.symbol)
            .font(.largeTitle.weight(.semibold))
          selectedSettings
        }
        .padding(28)
      }
    }
    .frame(minWidth: 760, minHeight: 560)
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
      mediaSettings
    }
  }

  private var generalSettings: some View {
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
    GroupBox("展开") {
      Picker(
        "展开方式",
        selection: Binding(
          get: { preferences.expansionTrigger },
          set: { preferences.setExpansionTrigger($0) }
        )
      ) {
        Text("悬停").tag(SurfaceExpansionTrigger.hover)
        Text("点击").tag(SurfaceExpansionTrigger.click)
      }
      .pickerStyle(.segmented)
      .accessibilityIdentifier("settings.expansionTrigger")
    }
  }

  private var accessibilitySettings: some View {
    GroupBox("系统辅助功能") {
      Text("减少动态效果和减少透明度会在运行时覆盖预览，而不会改写你的设置。")
    }
  }

  private var mediaSettings: some View {
    GroupBox("Media") {
      Text("Media-First Mode 将在此处提供控制与外观选项。")
        .foregroundStyle(.secondary)
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
