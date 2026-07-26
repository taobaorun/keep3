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
    XCTAssertTrue(presentation.rows[0].isOngoing)
    XCTAssertTrue(presentation.rows[0].timeLabel.hasPrefix("进行中"))
    XCTAssertEqual(presentation.rows[2].timeLabel, "全天")
    XCTAssertEqual(presentation.compactTitle, "ongoing")
    XCTAssertFalse(
      presentation.accessibilitySummary.contains("must-not-render")
    )
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
