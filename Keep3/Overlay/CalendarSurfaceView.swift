import SwiftUI

struct CalendarEventRowPresentation: Equatable, Identifiable, Sendable {
  let id: String
  let timeLabel: String
  let statusLabel: String
  let dayLabel: String
  let startsNewDayGroup: Bool
  let title: String
  let isOngoing: Bool
  let isAllDay: Bool

  var compactMetadata: String {
    "\(statusLabel) \(timeLabel)"
  }

  /// The physical-notch layout has only one narrow wing for metadata. Keep
  /// day context when it changes, while avoiding a redundant "today" or
  /// "ongoing" label that would crowd the icon and time.
  var notchedCompactMetadata: String {
    if isOngoing {
      return timeLabel
    }
    if isAllDay || dayLabel != "今天" {
      return "\(dayLabel) \(timeLabel)"
    }
    return timeLabel
  }

  var accessibilityLabel: String {
    "\(statusLabel)，\(timeLabel)，\(title)"
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
    var previousDay: Date?
    rows = events.map { event in
      let day = calendar.startOfDay(for: max(event.startDate, now))
      let row = Self.row(
        for: event,
        day: day,
        startsNewDayGroup: previousDay != day,
        now: now,
        calendar: calendar,
        locale: locale
      )
      previousDay = day
      return row
    }
    compactTime = rows.first?.compactMetadata
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

  var primaryRow: CalendarEventRowPresentation? {
    rows.first
  }

  var secondaryRows: [CalendarEventRowPresentation] {
    Array(rows.dropFirst())
  }

  var accessibilitySummary: String {
    if rows.isEmpty {
      return statusMessage ?? compactTitle
    }
    return rows.map(\.accessibilityLabel).joined(separator: "；")
  }

  private static func row(
    for event: CalendarEvent,
    day: Date,
    startsNewDayGroup: Bool,
    now: Date,
    calendar: Calendar,
    locale: Locale
  ) -> CalendarEventRowPresentation {
    let isOngoing =
      !event.isAllDay
      && event.startDate <= now
      && event.endDate > now
    let timeLabel: String
    let dayLabel = formattedDay(
      day,
      now: now,
      calendar: calendar,
      locale: locale
    )
    let statusLabel: String
    if event.isAllDay {
      timeLabel = "全天"
      statusLabel = dayLabel
    } else if isOngoing {
      timeLabel =
        "至 "
        + formattedTime(
          event.endDate,
          calendar: calendar,
          locale: locale
        )
      statusLabel = "进行中"
    } else {
      timeLabel = formattedTime(
        event.startDate,
        calendar: calendar,
        locale: locale
      )
      statusLabel = dayLabel
    }
    return CalendarEventRowPresentation(
      id: event.id,
      timeLabel: timeLabel,
      statusLabel: statusLabel,
      dayLabel: dayLabel,
      startsNewDayGroup: startsNewDayGroup,
      title: event.title,
      isOngoing: isOngoing,
      isAllDay: event.isAllDay
    )
  }

  private static func formattedDay(
    _ date: Date,
    now: Date,
    calendar: Calendar,
    locale: Locale
  ) -> String {
    if calendar.isDate(date, inSameDayAs: now) {
      return "今天"
    }
    if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
      calendar.isDate(date, inSameDayAs: tomorrow)
    {
      return "明天"
    }

    var format = Date.FormatStyle()
      .month(.abbreviated)
      .day()
      .locale(locale)
    format.calendar = calendar
    return date.formatted(format)
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

  var body: some View {
    let presentation = CalendarSurfacePresentation(payload: payload)

    Group {
      switch payload.level {
      case .hardware:
        Color.clear
      case .compact:
        compactContent(presentation)
      case .expanded:
        expandedContent(presentation)
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
  private func compactContent(
    _ presentation: CalendarSurfacePresentation
  ) -> some View {
    switch presentationStyle {
    case .floatingCapsule:
      compactButton {
        HStack(spacing: 8) {
          calendarSymbolBadge(size: 22)
          if let time = presentation.compactTime {
            Text(time)
              .font(.system(size: 10.5, weight: .semibold))
              .monospacedDigit()
              .foregroundStyle(.white.opacity(0.72))
              .lineLimit(1)
              .minimumScaleFactor(0.78)
          }
          Rectangle()
            .fill(.white.opacity(0.14))
            .frame(width: 0.5, height: 13)
            .accessibilityHidden(true)
          Text(presentation.compactTitle)
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1)
            .truncationMode(.tail)
          Spacer(minLength: 0)
          refreshIndicator(isRefreshing: presentation.isRefreshing)
        }
        .padding(.horizontal, 11)
      }
    case .notchAttached(let notchSize):
      let layout = NotchCompactContentLayout(
        surfaceSize: surfaceSize,
        obstructionSize: notchSize
      )
      compactButton {
        HStack(spacing: 0) {
          HStack(spacing: 5) {
            notchedCalendarSymbol(
              isOngoing: presentation.primaryRow?.isOngoing == true
            )
            if let row = presentation.primaryRow {
              Text(row.notchedCompactMetadata)
                .font(.system(size: 10, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .foregroundStyle(.white.opacity(0.74))
            }
          }
          .padding(.leading, 7)
          .padding(.trailing, 9)
          .frame(
            width: layout.leftWingFrame.width,
            alignment: .trailing
          )

          Color.clear
            .frame(width: layout.obstructionFrame.width)
            .accessibilityHidden(true)

          Text(presentation.compactTitle)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.92))
            .lineLimit(1)
            .truncationMode(.tail)
            .minimumScaleFactor(0.78)
            .padding(.leading, 9)
            .padding(.trailing, 7)
            .frame(
              width: layout.rightWingFrame.width,
              alignment: .leading
            )
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
    .buttonStyle(SurfacePressButtonStyle())
    .accessibilityIdentifier("calendar.compact")
  }

  private func expandedContent(
    _ presentation: CalendarSurfacePresentation
  ) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 7) {
        calendarSymbolBadge(size: 20)
        Text("接下来")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(.white.opacity(0.76))
        Spacer()
        if !presentation.rows.isEmpty {
          Text("\(presentation.rows.count) 项")
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(.white.opacity(0.42))
        }
        refreshIndicator(isRefreshing: presentation.isRefreshing)
      }
      .frame(height: 20)
      .padding(.bottom, 5)

      if presentation.rows.isEmpty {
        VStack(spacing: 7) {
          ZStack {
            Circle()
              .fill(.white.opacity(0.065))
              .frame(width: 38, height: 38)
            if showsStateProgress {
              ProgressView()
                .controlSize(.small)
                .tint(.white.opacity(0.62))
            } else {
              Image(systemName: emptyStateSymbolName)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.48))
            }
          }
          Text(presentation.statusMessage ?? "未来 24 小时没有安排")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white.opacity(0.72))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(.white.opacity(0.035))
            .overlay {
              RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.white.opacity(0.06), lineWidth: 0.5)
            }
        }
        .accessibilityIdentifier("calendar.empty")
      } else if let primaryRow = presentation.primaryRow {
        VStack(spacing: 0) {
          primaryEventCard(primaryRow)

          if !presentation.secondaryRows.isEmpty {
            VStack(spacing: 0) {
              ForEach(presentation.secondaryRows) { row in
                secondaryEventRow(row)
              }
            }
            .padding(.top, 4)
            .accessibilityIdentifier("calendar.timeline")
          }
        }
        .accessibilityIdentifier("calendar.events")
      }

      if presentation.hasRefreshFailure {
        Label("暂时无法刷新，显示上次读取结果", systemImage: "exclamationmark.circle.fill")
          .font(.system(size: 9, weight: .medium))
          .foregroundStyle(.orange.opacity(0.74))
          .lineLimit(1)
          .padding(.top, 3)
      }
    }
    .padding(.horizontal, 16)
    .padding(.top, expandedTopInset + 8)
    .padding(.bottom, 8)
    .accessibilityIdentifier("calendar.expanded")
  }

  private func primaryEventCard(
    _ row: CalendarEventRowPresentation
  ) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack(spacing: 6) {
        Text(row.statusLabel)
          .font(.system(size: 9, weight: .bold))
          .foregroundStyle(row.isOngoing ? Color.orange : Color.white.opacity(0.74))
          .padding(.horizontal, 6)
          .frame(height: 17)
          .background(
            row.isOngoing
              ? Color.orange.opacity(0.12)
              : Color.white.opacity(0.07),
            in: Capsule()
          )
        Text(row.timeLabel)
          .font(.system(size: 10.5, weight: .semibold))
          .monospacedDigit()
          .foregroundStyle(.white.opacity(0.58))
        Spacer(minLength: 0)
      }

      Text(row.title)
        .font(.system(size: 15, weight: .semibold))
        .lineLimit(1)
        .truncationMode(.tail)
        .minimumScaleFactor(0.82)
    }
    .padding(.horizontal, 10)
    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
    .background {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(.white.opacity(0.065))
        .overlay {
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(
              row.isOngoing
                ? Color.orange.opacity(0.22)
                : Color.white.opacity(0.075),
              lineWidth: 0.5
            )
        }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(row.accessibilityLabel)
    .accessibilityIdentifier("calendar.primary")
  }

  private func secondaryEventRow(
    _ row: CalendarEventRowPresentation
  ) -> some View {
    HStack(spacing: 6) {
      Text(row.startsNewDayGroup ? row.dayLabel : "")
        .font(.system(size: 8.5, weight: .semibold))
        .foregroundStyle(.white.opacity(0.4))
        .frame(width: 28, alignment: .leading)

      ZStack {
        Rectangle()
          .fill(.white.opacity(0.11))
          .frame(width: 0.5)
        Circle()
          .fill(
            row.isOngoing
              ? Color.orange.opacity(0.9)
              : Color.white.opacity(0.32)
          )
          .frame(width: 4, height: 4)
      }
      .frame(width: 7, height: 18)
      .accessibilityHidden(true)

      Text(row.timeLabel)
        .font(.system(size: 9.5, weight: .semibold))
        .monospacedDigit()
        .foregroundStyle(
          row.isOngoing
            ? Color.orange.opacity(0.86)
            : Color.white.opacity(0.5)
        )
        .lineLimit(1)
        .minimumScaleFactor(0.78)
        .frame(width: 50, alignment: .leading)

      Text(row.title)
        .font(.system(size: 10.5, weight: .medium))
        .foregroundStyle(.white.opacity(0.82))
        .lineLimit(1)
        .truncationMode(.tail)
      Spacer(minLength: 0)
    }
    .frame(height: 18)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(row.accessibilityLabel)
  }

  private var calendarSymbol: some View {
    Image(systemName: "calendar")
      .font(.system(size: 11, weight: .semibold))
      .foregroundStyle(.white.opacity(0.76))
  }

  private func notchedCalendarSymbol(isOngoing: Bool) -> some View {
    Image(systemName: "calendar")
      .font(.system(size: 11, weight: .semibold))
      .foregroundStyle(
        isOngoing
          ? Color.orange.opacity(0.9)
          : Color.white.opacity(0.7)
      )
      .accessibilityHidden(true)
  }

  private func calendarSymbolBadge(size: CGFloat) -> some View {
    ZStack {
      RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
        .fill(.white.opacity(0.075))
      calendarSymbol
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }

  private var showsStateProgress: Bool {
    switch payload.state {
    case .requestingPermission, .loading:
      true
    default:
      false
    }
  }

  private var emptyStateSymbolName: String {
    switch payload.state {
    case .disabled:
      "calendar.badge.minus"
    case .needsPermission, .restricted, .denied, .failed:
      "calendar.badge.exclamationmark"
    default:
      "calendar.badge.clock"
    }
  }

  @ViewBuilder
  private func refreshIndicator(isRefreshing: Bool) -> some View {
    if isRefreshing {
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
