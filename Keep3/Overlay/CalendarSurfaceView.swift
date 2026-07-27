import SwiftUI

struct CalendarEventRowPresentation: Equatable, Identifiable, Sendable {
  let id: String
  let timeLabel: String
  let title: String
  let isOngoing: Bool
  let isAllDay: Bool

  var accessibilityLabel: String {
    "\(timeLabel)，\(title)"
  }
}

struct CalendarSurfacePresentation: Equatable, Sendable {
  let level: SurfaceLevel
  let rows: [CalendarEventRowPresentation]
  let compactTime: String?
  let compactTitle: String
  let statusMessage: String?
  let isRefreshing: Bool
  let hasRefreshFailure: Bool

  init(
    payload: CalendarSurfacePayload,
    now: Date = Date(),
    calendar: Calendar = .current,
    locale: Locale = .current
  ) {
    level = payload.level

    let events = Array(payload.state.events.prefix(5))
    rows = events.map {
      Self.row(for: $0, now: now, calendar: calendar, locale: locale)
    }
    compactTime = rows.first?.timeLabel
    compactTitle = rows.first?.title ?? Self.message(for: payload.state)

    switch payload.state {
    case .content(let events, let isRefreshing, let refreshFailure):
      statusMessage = events.isEmpty ? "未来 24 小时没有安排" : nil
      self.isRefreshing = isRefreshing
      hasRefreshFailure = refreshFailure != nil
    default:
      statusMessage = Self.message(for: payload.state)
      isRefreshing = false
      hasRefreshFailure = false
    }
  }

  var isExpanded: Bool {
    level == .expanded
  }

  var accessibilitySummary: String {
    if rows.isEmpty {
      return statusMessage ?? compactTitle
    }
    return rows.map(\.accessibilityLabel).joined(separator: "；")
  }

  private static func row(
    for event: CalendarEvent,
    now: Date,
    calendar: Calendar,
    locale: Locale
  ) -> CalendarEventRowPresentation {
    let isOngoing =
      !event.isAllDay
      && event.startDate <= now
      && event.endDate > now
    let timeLabel: String
    if event.isAllDay {
      timeLabel = "全天"
    } else if isOngoing {
      timeLabel =
        "进行中 · 到 "
        + formattedTime(
          event.endDate,
          calendar: calendar,
          locale: locale
        )
    } else {
      timeLabel = formattedTime(
        event.startDate,
        calendar: calendar,
        locale: locale
      )
    }
    return CalendarEventRowPresentation(
      id: event.id,
      timeLabel: timeLabel,
      title: event.title,
      isOngoing: isOngoing,
      isAllDay: event.isAllDay
    )
  }

  private static func formattedTime(
    _ date: Date,
    calendar: Calendar,
    locale: Locale
  ) -> String {
    var format = Date.FormatStyle()
      .hour(.twoDigits(amPM: .abbreviated))
      .minute(.twoDigits)
      .locale(locale)
    format.calendar = calendar
    return date.formatted(format)
  }

  private static func message(
    for state: CalendarSessionState
  ) -> String {
    switch state {
    case .disabled:
      "日历未开启"
    case .needsPermission:
      "在设置中允许日历"
    case .requestingPermission:
      "正在请求日历权限"
    case .restricted:
      "日历访问受限"
    case .denied:
      "日历权限已关闭"
    case .loading:
      "正在读取日历"
    case .content(let events, _, _):
      events.isEmpty ? "未来 24 小时没有安排" : events[0].title
    case .failed:
      "暂时无法读取日历"
    }
  }
}

struct CalendarSurfaceView: View {
  let payload: CalendarSurfacePayload
  let presentationStyle: TopSurfacePresentationStyle
  let surfaceSize: CGSize
  let onActivateSurface: () -> Void
  let onRequestKeyboardNavigation: () -> Void
  let onSurfaceNavigation: (SurfaceGestureIntent) -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  private var presentation: CalendarSurfacePresentation {
    CalendarSurfacePresentation(payload: payload)
  }

  var body: some View {
    Group {
      switch payload.level {
      case .hardware:
        Color.clear
      case .compact:
        compactContent
      case .expanded:
        expandedContent
      }
    }
    .foregroundStyle(.white)
    .frame(width: surfaceSize.width, height: surfaceSize.height)
    .background {
      surfaceShape.fill(
        .black.opacity(reduceTransparency ? 1 : 0.96)
      )
    }
    .clipShape(surfaceShape)
    .animation(
      reduceMotion ? nil : .easeInOut(duration: 0.2),
      value: payload.revision
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .accessibilityElement(children: .contain)
    .accessibilityLabel(presentation.accessibilitySummary)
    .modifier(
      SurfaceAccessibilityNavigationModifier(
        component: .calendar,
        level: payload.level,
        onNavigate: onSurfaceNavigation
      )
    )
  }

  @ViewBuilder
  private var compactContent: some View {
    switch presentationStyle {
    case .floatingCapsule:
      compactButton {
        HStack(spacing: 9) {
          calendarSymbol
          if let time = presentation.compactTime {
            Text(time)
              .font(.caption.monospacedDigit().weight(.semibold))
              .foregroundStyle(.white.opacity(0.68))
          }
          Text(presentation.compactTitle)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
          Spacer(minLength: 0)
          refreshIndicator
        }
        .padding(.horizontal, 14)
      }
    case .notchAttached(let notchSize):
      let layout = NotchCompactContentLayout(
        surfaceSize: surfaceSize,
        obstructionSize: notchSize
      )
      compactButton {
        HStack(spacing: 0) {
          HStack(spacing: 5) {
            calendarSymbol
            if let time = presentation.compactTime {
              Text(time)
                .font(.system(size: 9.5, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
            }
          }
          .frame(width: layout.leftWingFrame.width)

          Color.clear
            .frame(width: layout.obstructionFrame.width)
            .accessibilityHidden(true)

          Text(presentation.compactTitle)
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: layout.rightWingFrame.width)
        }
      }
    }
  }

  private func compactButton<Label: View>(
    @ViewBuilder label: () -> Label
  ) -> some View {
    Button(action: onActivateSurface) {
      label()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("calendar.compact")
  }

  private var expandedContent: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 8) {
        calendarSymbol
        Text("接下来")
          .font(.caption.weight(.bold))
          .foregroundStyle(.white.opacity(0.72))
        Spacer()
        refreshIndicator
        TopSurfaceKeyboardNavigationButton(
          guidance: .calendar,
          onActivate: onRequestKeyboardNavigation
        )
        .accessibilityIdentifier("calendar.keyboard")
      }
      .padding(.bottom, 10)

      if presentation.rows.isEmpty {
        VStack(spacing: 8) {
          Image(systemName: "calendar.badge.clock")
            .font(.system(size: 24, weight: .medium))
            .foregroundStyle(.white.opacity(0.38))
          Text(presentation.statusMessage ?? "未来 24 小时没有安排")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white.opacity(0.68))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("calendar.empty")
      } else {
        VStack(spacing: 0) {
          ForEach(presentation.rows) { row in
            HStack(spacing: 10) {
              Text(row.timeLabel)
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(
                  row.isOngoing
                    ? Color.orange.opacity(0.9)
                    : Color.white.opacity(0.5)
                )
                .frame(width: 82, alignment: .leading)
              Text(row.title)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
              Spacer(minLength: 0)
            }
            .frame(height: 27)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(row.accessibilityLabel)
          }
        }
        .accessibilityIdentifier("calendar.events")
      }

      if presentation.hasRefreshFailure {
        Text("暂时无法刷新，显示上次读取结果")
          .font(.caption2)
          .foregroundStyle(.orange.opacity(0.72))
          .padding(.top, 6)
      }
    }
    .padding(.horizontal, 18)
    .padding(.top, expandedTopInset + 12)
    .padding(.bottom, 14)
    .accessibilityIdentifier("calendar.expanded")
  }

  private var calendarSymbol: some View {
    Image(systemName: "calendar")
      .font(.system(size: 11, weight: .semibold))
      .foregroundStyle(.white.opacity(0.76))
  }

  @ViewBuilder
  private var refreshIndicator: some View {
    if presentation.isRefreshing {
      ProgressView()
        .controlSize(.mini)
        .tint(.white.opacity(0.62))
        .accessibilityLabel("正在刷新")
    }
  }

  private var expandedTopInset: CGFloat {
    guard case .notchAttached(let notchSize) = presentationStyle else {
      return 0
    }
    return notchSize.height
  }

  private var surfaceShape: TopSurfaceShape {
    TopSurfaceShape(
      presentationStyle: presentationStyle,
      isExpanded: payload.level == .expanded
    )
  }
}
