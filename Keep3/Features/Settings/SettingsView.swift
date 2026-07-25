import SwiftUI

struct SettingsView: View {
  @ObservedObject var preferences: AppPreferences
  @ObservedObject var launchAtLoginController: LaunchAtLoginController

  var body: some View {
    Form {
      Section("启动") {
        Toggle(
          "登录时启动 Keep3",
          isOn: binding(
            get: { launchAtLoginController.isOn },
            set: launchAtLoginController.setEnabled
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

      Section("轮播") {
        Toggle(
          "自动轮播",
          isOn: binding(
            get: { preferences.isAutomaticRotationEnabled },
            set: preferences.setAutomaticRotationEnabled
          )
        )
        .accessibilityIdentifier("settings.autoRotation")

        durationControl(
          title: "当前重点",
          identifier: "settings.currentDuration",
          value: preferences.currentFocusDuration,
          range: RotationDurations.currentFocusRange,
          step: 10,
          setter: preferences.setCurrentFocusDuration
        )

        durationControl(
          title: "其他重点",
          identifier: "settings.secondaryDuration",
          value: preferences.secondaryDuration,
          range: RotationDurations.secondaryRange,
          step: 1,
          setter: preferences.setSecondaryDuration
        )
      }

      Section("展开") {
        Picker(
          "展开方式",
          selection: binding(
            get: { preferences.expansionTrigger },
            set: preferences.setExpansionTrigger
          )
        ) {
          Text("悬停").tag(SurfaceExpansionTrigger.hover)
          Text("点击").tag(SurfaceExpansionTrigger.click)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("settings.expansionTrigger")

        Text(
          preferences.expansionTrigger == .hover
            ? "停留 0.4 秒后展开，移开后收起。"
            : "点击顶部重点展开，点击标题打开详情。"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      Section("外观") {
        Text("Keep3 使用统一的 0.76 秒形状与内容交接；“减少动态效果”时改为 0.12 秒交叉淡入。")
          .font(.caption)
          .foregroundStyle(.secondary)

        valueSlider(
          title: "收起宽度",
          identifier: "settings.capsuleWidth",
          value: preferences.capsuleWidth,
          range: AppPreferences.capsuleWidthRange,
          step: 10,
          valueLabel: "\(Int(preferences.capsuleWidth)) pt",
          setter: preferences.setCapsuleWidth
        )

        valueSlider(
          title: "背景不透明度",
          identifier: "settings.backgroundOpacity",
          value: preferences.backgroundOpacity,
          range: AppPreferences.backgroundOpacityRange,
          step: 0.01,
          valueLabel: "\(Int(preferences.backgroundOpacity * 100))%",
          setter: preferences.setBackgroundOpacity
        )

        Text("系统的“减少动态效果”和“减少透明度”设置始终优先。")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .padding(20)
    .frame(minWidth: 720, minHeight: 520)
    .accessibilityIdentifier("settings.root")
  }

  private func durationControl(
    title: String,
    identifier: String,
    value: TimeInterval,
    range: ClosedRange<TimeInterval>,
    step: TimeInterval,
    setter: @escaping @MainActor @Sendable (TimeInterval) -> Void
  ) -> some View {
    valueSlider(
      title: title,
      identifier: identifier,
      value: value,
      range: range,
      step: step,
      valueLabel: "\(Int(value)) 秒",
      setter: setter
    )
    .disabled(!preferences.isAutomaticRotationEnabled)
  }

  private func valueSlider(
    title: String,
    identifier: String,
    value: Double,
    range: ClosedRange<Double>,
    step: Double,
    valueLabel: String,
    setter: @escaping @MainActor @Sendable (Double) -> Void
  ) -> some View {
    HStack(spacing: 12) {
      Text(title)
        .frame(width: 100, alignment: .leading)

      Slider(
        value: binding(get: { value }, set: setter),
        in: range,
        step: step
      )
      .accessibilityLabel(title)
      .accessibilityValue(valueLabel)
      .accessibilityIdentifier(identifier)

      Text(valueLabel)
        .font(.system(.body, design: .monospaced))
        .foregroundStyle(.secondary)
        .frame(width: 72, alignment: .trailing)
    }
  }

  private func binding<Value: Sendable>(
    get: @escaping @MainActor @Sendable () -> Value,
    set: @escaping @MainActor @Sendable (Value) -> Void
  ) -> Binding<Value> {
    Binding(get: get, set: set)
  }
}
