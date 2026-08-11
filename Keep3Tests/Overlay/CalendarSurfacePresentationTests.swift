import AppKit
import SwiftUI
import XCTest

@testable import Keep3

final class CalendarSurfacePresentationTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 2_000_000_000)

  func testTimedOngoingAndAllDayLabelsStayBounded() {
    let events = [
      event("ongoing", start: -300, end: 900),
      event("upcoming", start: 3_600, end: 4_200),
      event("all-day", start: -3_600, end: 86_400, isAllDay: true),
      event("four", start: 5_000, end: 5_500),
      event("five", start: 6_000, end: 6_500),
      event("must-not-render", start: 7_000, end: 7_500),
    ]
    let presentation = makePresentation(
      state: .content(
        events: events,
        isRefreshing: false,
        refreshFailure: nil
      )
    )

    XCTAssertEqual(presentation.rows.count, 5)
    XCTAssertEqual(presentation.primaryRow?.id, "ongoing")
    XCTAssertEqual(
      presentation.secondaryRows.map(\.id),
      ["upcoming", "all-day", "four", "five"]
    )
    XCTAssertTrue(presentation.rows[0].isOngoing)
    XCTAssertEqual(presentation.rows[0].statusLabel, "进行中")
    XCTAssertTrue(presentation.rows[0].timeLabel.hasPrefix("至 "))
    XCTAssertEqual(presentation.rows[2].timeLabel, "全天")
    XCTAssertEqual(presentation.compactTitle, "ongoing")
    XCTAssertFalse(
      presentation.accessibilitySummary.contains("must-not-render")
    )
  }

  func testRowsExposeLightweightDayGroupsAcrossMidnight() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let lateToday = try XCTUnwrap(
      calendar.date(
        from: DateComponents(
          year: 2033,
          month: 5,
          day: 18,
          hour: 23,
          minute: 30
        )
      )
    )
    let events = [
      CalendarEvent(
        id: "today",
        title: "today",
        startDate: lateToday.addingTimeInterval(15 * 60),
        endDate: lateToday.addingTimeInterval(45 * 60),
        isAllDay: false
      ),
      CalendarEvent(
        id: "tomorrow-first",
        title: "tomorrow-first",
        startDate: lateToday.addingTimeInterval(2 * 60 * 60),
        endDate: lateToday.addingTimeInterval(3 * 60 * 60),
        isAllDay: false
      ),
      CalendarEvent(
        id: "tomorrow-second",
        title: "tomorrow-second",
        startDate: lateToday.addingTimeInterval(4 * 60 * 60),
        endDate: lateToday.addingTimeInterval(5 * 60 * 60),
        isAllDay: false
      ),
    ]

    let presentation = CalendarSurfacePresentation(
      payload: CalendarSurfacePayload(
        state: .content(
          events: events,
          isRefreshing: false,
          refreshFailure: nil
        ),
        level: .expanded,
        revision: 1
      ),
      now: lateToday,
      calendar: calendar,
      locale: Locale(identifier: "zh_CN")
    )

    XCTAssertEqual(presentation.rows.map(\.dayLabel), ["今天", "明天", "明天"])
    XCTAssertEqual(
      presentation.rows.map(\.startsNewDayGroup),
      [true, true, false]
    )
    XCTAssertTrue(presentation.rows[0].compactMetadata.hasPrefix("今天 "))
    XCTAssertTrue(presentation.rows[1].compactMetadata.hasPrefix("明天 "))
  }

  func testLoadingEmptyFailureAndDeniedNeverCarryEventTitles() {
    let fixtures: [(CalendarSessionState, String)] = [
      (.loading, "正在读取日历"),
      (
        .content(events: [], isRefreshing: false, refreshFailure: nil),
        "未来 24 小时没有安排"
      ),
      (.failed(.queryFailed), "暂时无法读取日历"),
      (.denied, "日历权限已关闭"),
    ]

    for (state, expected) in fixtures {
      let presentation = makePresentation(state: state)

      XCTAssertTrue(presentation.rows.isEmpty)
      XCTAssertEqual(presentation.compactTitle, expected)
      XCTAssertEqual(presentation.accessibilitySummary, expected)
    }
  }

  func testRefreshFailureKeepsOnlyTheBoundedAuthorizedSnapshot() {
    let presentation = makePresentation(
      state: .content(
        events: [event("retained", start: 600, end: 900)],
        isRefreshing: false,
        refreshFailure: .queryFailed
      ),
      level: .expanded
    )

    XCTAssertTrue(presentation.isExpanded)
    XCTAssertTrue(presentation.hasRefreshFailure)
    XCTAssertEqual(presentation.rows.map(\.title), ["retained"])
  }

  @MainActor
  func testCalendarVisualFixturesRenderAtSurfaceBounds() throws {
    let current = Date()
    let calendar = Calendar.current
    let tomorrow = try XCTUnwrap(
      calendar.date(
        byAdding: .day,
        value: 1,
        to: calendar.startOfDay(for: current)
      )
    )
    let events = [
      CalendarEvent(
        id: "ongoing",
        title: "整理本周发布说明与最终检查清单",
        startDate: current.addingTimeInterval(-10 * 60),
        endDate: current.addingTimeInterval(35 * 60),
        isAllDay: false
      ),
      CalendarEvent(
        id: "next",
        title: "产品设计同步",
        startDate: current.addingTimeInterval(75 * 60),
        endDate: current.addingTimeInterval(105 * 60),
        isAllDay: false
      ),
      CalendarEvent(
        id: "tomorrow-one",
        title: "设计走查",
        startDate: tomorrow.addingTimeInterval(9 * 60 * 60),
        endDate: tomorrow.addingTimeInterval(10 * 60 * 60),
        isAllDay: false
      ),
      CalendarEvent(
        id: "tomorrow-two",
        title: "发布复盘",
        startDate: tomorrow.addingTimeInterval(11 * 60 * 60),
        endDate: tomorrow.addingTimeInterval(12 * 60 * 60),
        isAllDay: false
      ),
      CalendarEvent(
        id: "all-day",
        title: "Keep3 里程碑",
        startDate: current,
        endDate: tomorrow,
        isAllDay: true
      ),
    ]
    let state = CalendarSessionState.content(
      events: events,
      isRefreshing: false,
      refreshFailure: nil
    )

    try attachRenderedSurface(
      named: "calendar-expanded",
      state: state,
      level: .expanded,
      size: CGSize(width: 312, height: 216)
    )
    try attachRenderedSurface(
      named: "calendar-compact",
      state: state,
      level: .compact,
      size: CGSize(width: 280, height: 44)
    )
    try attachRenderedSurface(
      named: "calendar-empty",
      state: .content(
        events: [],
        isRefreshing: false,
        refreshFailure: nil
      ),
      level: .expanded,
      size: CGSize(width: 312, height: 216)
    )
    let notchStyle = TopSurfacePresentationStyle.notchAttached(
      notchSize: CGSize(width: 185, height: 32)
    )
    try attachRenderedSurface(
      named: "calendar-notch-expanded",
      state: state,
      level: .expanded,
      size: CGSize(width: 360, height: 216),
      presentationStyle: notchStyle
    )
    try attachRenderedSurface(
      named: "calendar-notch-refresh-failure",
      state: .content(
        events: events,
        isRefreshing: false,
        refreshFailure: .queryFailed
      ),
      level: .expanded,
      size: CGSize(width: 360, height: 216),
      presentationStyle: notchStyle
    )
    try attachRenderedSurface(
      named: "calendar-notch-compact",
      state: state,
      level: .compact,
      size: CGSize(width: 377, height: 32),
      presentationStyle: notchStyle
    )
  }

  @MainActor
  private func attachRenderedSurface(
    named name: String,
    state: CalendarSessionState,
    level: SurfaceLevel,
    size: CGSize,
    presentationStyle: TopSurfacePresentationStyle = .floatingCapsule
  ) throws {
    let payload = CalendarSurfacePayload(
      state: state,
      level: level,
      revision: 1
    )
    let view = CalendarSurfaceView(
      payload: payload,
      presentationStyle: presentationStyle,
      surfaceSize: size,
      onActivateSurface: {},
      onRequestKeyboardNavigation: {},
      onSurfaceNavigation: { _ in }
    )
    let hostingView = NSHostingView(rootView: view)
    hostingView.frame = CGRect(origin: .zero, size: size)
    hostingView.layoutSubtreeIfNeeded()
    hostingView.displayIfNeeded()

    let representation = try XCTUnwrap(
      hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)
    )
    hostingView.cacheDisplay(in: hostingView.bounds, to: representation)
    XCTAssertGreaterThan(representation.pixelsWide, 0)
    XCTAssertGreaterThan(representation.pixelsHigh, 0)

    let image = NSImage(size: size)
    image.addRepresentation(representation)
    let attachment = XCTAttachment(image: image)
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  private func makePresentation(
    state: CalendarSessionState,
    level: SurfaceLevel = .compact
  ) -> CalendarSurfacePresentation {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return CalendarSurfacePresentation(
      payload: CalendarSurfacePayload(
        state: state,
        level: level,
        revision: 1
      ),
      now: now,
      calendar: calendar,
      locale: Locale(identifier: "zh_CN")
    )
  }

  private func event(
    _ id: String,
    start: TimeInterval,
    end: TimeInterval,
    isAllDay: Bool = false
  ) -> CalendarEvent {
    CalendarEvent(
      id: id,
      title: id,
      startDate: now.addingTimeInterval(start),
      endDate: now.addingTimeInterval(end),
      isAllDay: isAllDay
    )
  }
}
