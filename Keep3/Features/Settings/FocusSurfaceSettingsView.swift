import SwiftUI

struct FocusSurfaceSettingsView: View {
  @ObservedObject var preferences: AppPreferences

  var body: some View {
    GroupBox("外观") {
      VStack(alignment: .leading, spacing: 16) {
        SurfacePreview(preferences: preferences)
        Text("收起宽度：\(Int(preferences.capsuleWidth)) pt")
        Slider(
          value: Binding(
            get: { preferences.capsuleWidth },
            set: { preferences.setCapsuleWidth($0) }
          ),
          in: AppPreferences.capsuleWidthRange,
          step: 10
        )
        .accessibilityIdentifier("settings.capsuleWidth")
        Text("背景不透明度：\(Int(preferences.backgroundOpacity * 100))%")
        Slider(
          value: Binding(
            get: { preferences.backgroundOpacity },
            set: { preferences.setBackgroundOpacity($0) }
          ),
          in: AppPreferences.backgroundOpacityRange,
          step: 0.01
        )
        .accessibilityIdentifier("settings.backgroundOpacity")
        Text("Keep3 使用统一的 0.76 秒交接；减少动态效果时使用 0.12 秒交叉淡入。")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }
}
