import SwiftUI

enum SettingsCategory: String, CaseIterable, Identifiable, Sendable {
  case general
  case focusSurface
  case rotation
  case interaction
  case accessibility
  case media
  case calendar

  var id: String { rawValue }

  var title: String {
    switch self {
    case .general: "通用"
    case .focusSurface: "Focus Surface"
    case .rotation: "轮播"
    case .interaction: "交互"
    case .accessibility: "辅助功能"
    case .media: "Media"
    case .calendar: "Calendar"
    }
  }

  var symbol: String {
    switch self {
    case .general: "gearshape"
    case .focusSurface: "rectangle.topthird.inset.filled"
    case .rotation: "arrow.triangle.2.circlepath"
    case .interaction: "hand.tap"
    case .accessibility: "accessibility"
    case .media: "music.note"
    case .calendar: "calendar"
    }
  }
}

struct SettingsSidebarView: View {
  @Binding var selection: SettingsCategory

  var body: some View {
    List(selection: $selection) {
      ForEach(SettingsCategory.allCases) { category in
        Label(category.title, systemImage: category.symbol)
          .tag(category)
          .accessibilityIdentifier("settings.category.\(category.rawValue)")
      }
    }
    .listStyle(.sidebar)
    .accessibilityLabel("设置分类")
  }
}
