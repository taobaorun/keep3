import SwiftUI

struct SurfacePreview: View {
  let preferences: AppPreferences

  @State private var sampleIndex = 0
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  private static let samples = [
    sample(
      id: "8E7A5871-E676-43DC-B5E0-1B26258F09CE",
      title: "保持最重要的一件事可见"
    ),
    sample(
      id: "249381EC-5754-48D7-86D8-2FE37787B86F",
      title: "让注意力回到此刻"
    ),
  ]

  var body: some View {
    let item = Self.samples[sampleIndex]
    let content = TopSurfaceContent(
      item: item,
      position: 1,
      itemCount: Self.samples.count,
      isCurrentFocus: true,
      isExpanded: false,
      appearance: SurfaceAppearance(
        backgroundOpacity: preferences.backgroundOpacity,
        itemSwitchEffect: preferences.itemSwitchEffect
      )
    )
    VStack(alignment: .leading, spacing: 12) {
      Text("实时预览").font(.headline)
      TopSurfaceView(
        content: content,
        presentationStyle: .floatingCapsule,
        surfaceSize: CGSize(width: preferences.capsuleWidth, height: 44),
        onActivateSurface: {},
        onRequestKeyboardNavigation: {},
        onSurfaceNavigation: { _ in },
        onNavigate: { _ in },
        onOpenItem: {},
        onOpenKeep3: {}
      )
      .frame(width: preferences.capsuleWidth, height: 44)
      .allowsHitTesting(false)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("重点胶囊外观预览：\(item.title)")
      .accessibilityIdentifier("settings.surfacePreview")
      Text(
        reduceMotion || reduceTransparency
          ? "系统辅助功能设置正在覆盖预览效果。"
          : "预览与运行中的 Focus Surface 使用相同视觉 token。"
      )
      .font(.caption)
      .foregroundStyle(.secondary)
    }
    .padding(18)
    .background(
      .quaternary,
      in: RoundedRectangle(cornerRadius: 16, style: .continuous)
    )
    .onChange(of: preferences.itemSwitchEffect) {
      sampleIndex = (sampleIndex + 1) % Self.samples.count
    }
  }

  private static func sample(id: String, title: String) -> FocusItem {
    guard let id = UUID(uuidString: id),
      let item = try? FocusItem(id: id, title: title)
    else {
      preconditionFailure("Static Focus Surface preview fixture is invalid")
    }
    return item
  }
}
