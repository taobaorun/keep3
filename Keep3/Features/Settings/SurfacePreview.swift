import SwiftUI

struct SurfacePreview: View {
  let preferences: AppPreferences

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  var body: some View {
    let transition = SignatureSurfaceTransition.resolve(
      intent: .content,
      reduceMotion: reduceMotion,
      reduceTransparency: reduceTransparency,
      increaseContrast: false,
      differentiateWithoutColor: false,
      backgroundOpacity: preferences.backgroundOpacity
    )
    VStack(alignment: .leading, spacing: 12) {
      Text("实时预览").font(.headline)
      ZStack {
        TopSurfaceShape(presentationStyle: .floatingCapsule, isExpanded: false)
          .fill(.black.opacity(transition.backgroundOpacity))
        HStack(spacing: 8) {
          Capsule().fill(.white).frame(width: 15, height: 6)
          Text("保持最重要的一件事可见")
            .font(.subheadline.weight(.medium))
          Spacer()
        }
        .padding(.horizontal, 16)
        .foregroundStyle(.white)
      }
      .frame(width: preferences.capsuleWidth, height: 44)
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
  }
}
