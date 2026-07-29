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

        Divider()

        VStack(alignment: .leading, spacing: 8) {
          Text("三件事切换")
            .font(.headline)
          Picker(
            "最小化切换效果",
            selection: Binding(
              get: { preferences.itemSwitchEffect },
              set: { preferences.setItemSwitchEffect($0) }
            )
          ) {
            ForEach(FocusItemSwitchEffect.allCases, id: \.self) { effect in
              Text(effect.title).tag(effect)
            }
          }
          .pickerStyle(.segmented)
          .accessibilityIdentifier("settings.itemSwitchEffect")
          Text(preferences.itemSwitchEffect.detail)
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Text("系统“减少动态效果”开启时，卡片折叠会自动改为短交叉淡入。")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }
}

extension FocusItemSwitchEffect {
  fileprivate var title: String {
    switch self {
    case .instant: "即时"
    case .cardFlip: "卡片折叠"
    }
  }

  fileprivate var detail: String {
    switch self {
    case .instant:
      "最小化时直接显示下一件事，保持现在的切换方式。"
    case .cardFlip:
      "仅在最小化状态下，右侧标题显示槽像翻页时钟一样折叠到下一件事。"
    }
  }
}
