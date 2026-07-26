import XCTest

@testable import Keep3

@MainActor
final class CalendarSessionCoordinatorTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 2_000_000_000)

  func testEnablingNeverRequestsPermissionWithoutSettingsAction() async {
    let provider = CalendarFixtureProvider(status: .notDetermined)
    var states: [CalendarSessionState] = []
    let coordinator = CalendarSessionCoordinator(
      provider: provider,
      now: { self.now },
      onStateChange: { states.append($0) }
    )

    coordinator.setEnabled(true)
    await settle()

    XCTAssertEqual(provider.requestCount, 0)
    XCTAssertEqual(provider.queryCount, 0)
    XCTAssertEqual(states.last, .needsPermission)
  }

  func testExplicitAccessRanksBoundsAndProjectsOnlyGlanceableFields() async {
    let provider = CalendarFixtureProvider(status: .notDetermined)
    provider.statusAfterRequest = .fullAccess
    provider.eventsResult = .success([
      event("all-day", start: -3_600, end: 86_400, isAllDay: true),
      event("late", start: 7_200, end: 8_000),
      event("ongoing", start: -900, end: 900),
      event("soon", start: 600, end: 1_200),
      event("middle", start: 3_600, end: 4_000),
      event("fifth-timed", start: 5_400, end: 6_000),
      event("outside-cap", start: 8_000, end: 9_000),
    ])
    var states: [CalendarSessionState] = []
    let coordinator = CalendarSessionCoordinator(
      provider: provider,
      now: { self.now },
      onStateChange: { states.append($0) }
    )
    coordinator.setEnabled(true)
    await settle()

    coordinator.requestAccessFromSettings()
    await settle()

    XCTAssertEqual(provider.requestCount, 1)
    XCTAssertEqual(provider.queryCount, 1)
    XCTAssertEqual(
      states.last?.events.map(\.id),
      ["ongoing", "soon", "middle", "fifth-timed", "late"]
    )
    XCTAssertTrue(states.last?.isComponentAvailable == true)
  }

  func testRefreshKeepsSnapshotButRevocationClearsIt() async {
    let provider = CalendarFixtureProvider(status: .fullAccess)
    provider.eventsResult = .success([
      event("first", start: 600, end: 1_200)
    ])
    var states: [CalendarSessionState] = []
    let coordinator = CalendarSessionCoordinator(
      provider: provider,
      now: { self.now },
      onStateChange: { states.append($0) }
    )
    coordinator.setEnabled(true)
    await settle()

    provider.eventsResult = .failure(CalendarFixtureError.query)
    coordinator.refresh()
    await settle()

    XCTAssertEqual(states.last?.events.map(\.id), ["first"])
    guard case .content(_, false, .queryFailed) = states.last else {
      return XCTFail("Refresh failure should retain the authorized snapshot")
    }

    provider.status = .denied
    coordinator.refresh()
    await settle()

    XCTAssertEqual(states.last, .denied)
    XCTAssertTrue(states.last?.events.isEmpty == true)
  }

  func testDisableRejectsSuspendedQueryAndClearsTitlesImmediately() async {
    let provider = CalendarFixtureProvider(status: .fullAccess)
    provider.suspendsQueries = true
    var states: [CalendarSessionState] = []
    let coordinator = CalendarSessionCoordinator(
      provider: provider,
      now: { self.now },
      onStateChange: { states.append($0) }
    )

    coordinator.setEnabled(true)
    await provider.waitUntilQueryStarts()
    coordinator.setEnabled(false)

    XCTAssertEqual(states.last, .disabled)
    XCTAssertTrue(states.last?.events.isEmpty == true)

    provider.resumeQuery(
      with: [event("stale-title", start: 300, end: 600)]
    )
    await settle()

    XCTAssertEqual(states.last, .disabled)
    XCTAssertTrue(states.last?.events.isEmpty == true)
  }

  func testEventKitProjectionDropsCancelledAndBoundsText() {
    let longTitle = String(repeating: "长", count: 300)

    XCTAssertNil(
      EventKitCalendarAdapter.project(
        .init(
          identifier: "cancelled",
          title: "Secret",
          startDate: now,
          endDate: now.addingTimeInterval(60),
          isAllDay: false,
          isCancelled: true
        )
      )
    )

    let projected = EventKitCalendarAdapter.project(
      .init(
        identifier: String(repeating: "i", count: 400),
        title: longTitle,
        startDate: now,
        endDate: now.addingTimeInterval(60),
        isAllDay: false,
        isCancelled: false
      )
    )

    XCTAssertEqual(projected?.title.count, CalendarEvent.maximumTitleLength)
    XCTAssertEqual(projected?.id.count, CalendarEvent.maximumIdentifierLength)
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

  private func settle() async {
    for _ in 0..<8 {
      await Task.yield()
    }
  }
}

private enum CalendarFixtureError: Error {
  case query
}

@MainActor
private final class CalendarFixtureProvider: CalendarEventProviding {
  var status: CalendarAuthorizationState
  var statusAfterRequest: CalendarAuthorizationState?
  var eventsResult: Result<[CalendarEvent], Error> = .success([])
  var suspendsQueries = false

  private(set) var requestCount = 0
  private(set) var queryCount = 0
  private var queryStartContinuation: CheckedContinuation<Void, Never>?
  private var suspendedQueryContinuation: CheckedContinuation<[CalendarEvent], Error>?
  private var hasStartedQuery = false

  init(status: CalendarAuthorizationState) {
    self.status = status
  }

  func authorizationStatus() -> CalendarAuthorizationState {
    status
  }

  func requestFullAccess() async throws -> Bool {
    requestCount += 1
    if let statusAfterRequest {
      status = statusAfterRequest
    }
    return status == .fullAccess
  }

  func events(
    from _: Date,
    through _: Date
  ) async throws -> [CalendarEvent] {
    queryCount += 1
    hasStartedQuery = true
    queryStartContinuation?.resume()
    queryStartContinuation = nil
    if suspendsQueries {
      return try await withCheckedThrowingContinuation { continuation in
        suspendedQueryContinuation = continuation
      }
    }
    return try eventsResult.get()
  }

  func waitUntilQueryStarts() async {
    guard !hasStartedQuery else {
      return
    }
    await withCheckedContinuation { continuation in
      queryStartContinuation = continuation
    }
  }

  func resumeQuery(with events: [CalendarEvent]) {
    suspendedQueryContinuation?.resume(returning: events)
    suspendedQueryContinuation = nil
  }
}
