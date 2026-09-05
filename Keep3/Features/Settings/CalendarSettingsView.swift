import AppKit
import SwiftUI

struct CalendarSettingsView: View {
  @ObservedObject var preferences: CalendarPreferences
  @ObservedObject var coordinator: CalendarSessionCoordinator

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      preview

      GroupBox("日历事件") {
        VStack(alignment: .leading, spacing: 12) {
          Toggle(
            "在顶部表面显示即将到来的事件",
            isOn: Binding(
              get: { preferences.isEnabled },
              set: { isEnabled in
                setEnabled(isEnabled)
              }
            )
          )
          .accessibilityIdentifier("settings.calendar.enabled")

          Label(statusMessage, systemImage: statusSymbol)
            .font(.caption)
            .foregroundStyle(.secondary)

          if coordinator.state == .needsPermission {
            Button("允许访问日历") {
              coordinator.requestAccessFromSettings()
            }
            .accessibilityIdentifier("settings.calendar.requestAccess")
          } else if coordinator.state == .denied {
            Button("打开系统隐私设置") {
              openSystemCalendarPrivacy()
            }
          } else if coordinator.state.isComponentAvailable {
            Button("刷新事件") {
              coordinator.refresh()
            }
          }

          Text("Keep3 只读取未来 24 小时内最多 5 个事件的标题与时间；不会读取备注、参与人、位置，也不会上传或持久化日历内容。")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
  }

  private var preview: some View {
    let payload = CalendarSurfacePayload(
      state: previewState,
      level: .compact,
      revision: 1
    )
    let presentation = CalendarSurfacePresentation(payload: payload)

    return VStack(alignment: .leading, spacing: 10) {
      Text("实时预览")
        .font(.headline)
      CalendarSurfaceView(
        payload: payload,
        presentationStyle: .floatingCapsule,
        surfaceSize: CGSize(width: 310, height: 44),
        onActivateSurface: {},
        onRequestKeyboardNavigation: {},
        onSurfaceNavigation: { _ in }
      )
      .allowsHitTesting(false)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(
        "日历胶囊外观预览：\(presentation.accessibilitySummary)"
      )
      .accessibilityIdentifier("settings.calendar.preview")
      Text("实际顶部表面支持纵向手势：显示、展开或切换组件；此处仅展示外观。")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 16))
  }

  private var previewState: CalendarSessionState {
    if case .content = coordinator.state {
      return coordinator.state
    }
    let now = Date()
    return .content(
      events: [
        CalendarEvent(
          id: "settings-preview",
          title: "产品设计评审",
          startDate: now.addingTimeInterval(45 * 60),
          endDate: now.addingTimeInterval(75 * 60),
          isAllDay: false
        )
      ],
      isRefreshing: false,
      refreshFailure: nil
    )
  }

  private var statusMessage: String {
    switch coordinator.state {
    case .disabled:
      "Calendar 组件已关闭，启动时不会请求权限。"
    case .needsPermission:
      "需要你的明确授权后才能读取事件。"
    case .requestingPermission:
      "正在等待系统日历权限。"
    case .restricted:
      "此 Mac 限制了日历访问。"
    case .denied:
      "日历权限已关闭，可在系统隐私设置中恢复。"
    case .loading:
      "正在读取未来 24 小时的事件。"
    case .content(_, let isRefreshing, let failure):
      if isRefreshing {
        "正在刷新日历事件。"
      } else if failure != nil {
        "刷新失败，暂时显示本次运行中最近的结果。"
      } else {
        "Calendar 组件可用。"
      }
    case .failed:
      "暂时无法读取日历，可稍后重试。"
    }
  }

  private var statusSymbol: String {
    switch coordinator.state {
    case .content:
      "checkmark.circle"
    case .loading, .requestingPermission:
      "clock"
    case .denied, .restricted, .failed:
      "exclamationmark.triangle"
    case .disabled, .needsPermission:
      "calendar.badge.plus"
    }
  }

  private func setEnabled(_ isEnabled: Bool) {
    preferences.setEnabled(isEnabled)
    coordinator.setEnabled(isEnabled)
    if isEnabled {
      coordinator.requestAccessFromSettings()
    }
  }

  private func openSystemCalendarPrivacy() {
    guard
      let url = URL(
        string:
          "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
      )
    else {
      return
    }
    NSWorkspace.shared.open(url)
  }
}
