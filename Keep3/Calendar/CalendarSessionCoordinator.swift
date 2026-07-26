import Foundation

@MainActor
final class CalendarSessionCoordinator: ObservableObject {
  typealias StateDelivery = (CalendarSessionState) -> Void

  private static let queryDuration: TimeInterval = 24 * 60 * 60
  nonisolated private static let maximumEventCount = 5

  private let provider: any CalendarEventProviding
  private let now: () -> Date
  private let onStateChange: StateDelivery

  private var generation: UInt64 = 0
  private var refreshTask: Task<Void, Never>?
  private var lastEvents: [CalendarEvent] = []
  @Published private(set) var state: CalendarSessionState = .disabled
  private(set) var isEnabled = false

  init(
    provider: any CalendarEventProviding,
    now: @escaping () -> Date = Date.init,
    onStateChange: @escaping StateDelivery = { _ in }
  ) {
    self.provider = provider
    self.now = now
    self.onStateChange = onStateChange
  }

  func setEnabled(_ isEnabled: Bool) {
    guard self.isEnabled != isEnabled else {
      return
    }
    self.isEnabled = isEnabled
    invalidateWork()

    guard isEnabled else {
      lastEvents = []
      publish(.disabled)
      return
    }
    startRefresh(requestAccess: false)
  }

  func requestAccessFromSettings() {
    guard isEnabled else {
      return
    }
    invalidateWork()
    startRefresh(requestAccess: true)
  }

  func refresh() {
    guard isEnabled else {
      return
    }
    invalidateWork()
    startRefresh(requestAccess: false)
  }

  func invalidateAndClear() {
    invalidateWork()
    lastEvents = []
    publish(.disabled)
  }

  private func startRefresh(requestAccess: Bool) {
    let candidateGeneration = generation
    refreshTask = Task { @MainActor [weak self] in
      await self?.refresh(
        requestAccess: requestAccess,
        generation: candidateGeneration
      )
    }
  }

  private func refresh(
    requestAccess: Bool,
    generation candidateGeneration: UInt64
  ) async {
    var authorization = provider.authorizationStatus()

    if authorization == .notDetermined, requestAccess {
      publish(.requestingPermission)
      do {
        _ = try await provider.requestFullAccess()
      } catch {
        guard accepts(candidateGeneration) else {
          return
        }
        lastEvents = []
        publish(.failed(.authorizationRequestFailed))
        return
      }
      guard accepts(candidateGeneration) else {
        return
      }
      authorization = provider.authorizationStatus()
    }

    guard accepts(candidateGeneration) else {
      return
    }
    switch authorization {
    case .notDetermined:
      lastEvents = []
      publish(.needsPermission)
      return
    case .restricted:
      lastEvents = []
      publish(.restricted)
      return
    case .denied:
      lastEvents = []
      publish(.denied)
      return
    case .fullAccess:
      break
    }

    if lastEvents.isEmpty {
      publish(.loading)
    } else {
      publish(
        .content(
          events: lastEvents,
          isRefreshing: true,
          refreshFailure: nil
        )
      )
    }

    let startDate = now()
    let endDate = startDate.addingTimeInterval(Self.queryDuration)
    do {
      let events = try await provider.events(
        from: startDate,
        through: endDate
      )
      guard accepts(candidateGeneration) else {
        return
      }
      let currentAuthorization = provider.authorizationStatus()
      guard currentAuthorization == .fullAccess else {
        clearAndPublishAuthorization(currentAuthorization)
        return
      }
      lastEvents = Self.relevantEvents(
        events,
        from: startDate,
        through: endDate
      )
      publish(
        .content(
          events: lastEvents,
          isRefreshing: false,
          refreshFailure: nil
        )
      )
    } catch {
      guard accepts(candidateGeneration) else {
        return
      }
      let currentAuthorization = provider.authorizationStatus()
      guard currentAuthorization == .fullAccess else {
        clearAndPublishAuthorization(currentAuthorization)
        return
      }
      if lastEvents.isEmpty {
        publish(.failed(.queryFailed))
      } else {
        publish(
          .content(
            events: lastEvents,
            isRefreshing: false,
            refreshFailure: .queryFailed
          )
        )
      }
    }
  }

  nonisolated static func relevantEvents(
    _ events: [CalendarEvent],
    from startDate: Date,
    through endDate: Date
  ) -> [CalendarEvent] {
    let overlapping = events.filter {
      $0.endDate > startDate && $0.startDate < endDate
    }
    let ongoingTimed =
      overlapping
      .filter {
        !$0.isAllDay
          && $0.startDate <= startDate
          && $0.endDate > startDate
      }
      .sorted(by: chronological)
    let upcomingTimed =
      overlapping
      .filter { !$0.isAllDay && $0.startDate > startDate }
      .sorted(by: chronological)
    let allDay =
      overlapping
      .filter(\.isAllDay)
      .sorted(by: chronological)
    return Array(
      (ongoingTimed + upcomingTimed + allDay)
        .prefix(Self.maximumEventCount)
    )
  }

  nonisolated private static func chronological(
    _ lhs: CalendarEvent,
    _ rhs: CalendarEvent
  ) -> Bool {
    if lhs.startDate == rhs.startDate {
      return lhs.endDate < rhs.endDate
    }
    return lhs.startDate < rhs.startDate
  }

  private func invalidateWork() {
    generation &+= 1
    refreshTask?.cancel()
    refreshTask = nil
  }

  private func clearAndPublishAuthorization(
    _ authorization: CalendarAuthorizationState
  ) {
    lastEvents = []
    switch authorization {
    case .notDetermined:
      publish(.needsPermission)
    case .restricted:
      publish(.restricted)
    case .denied:
      publish(.denied)
    case .fullAccess:
      break
    }
  }

  private func accepts(_ candidateGeneration: UInt64) -> Bool {
    isEnabled
      && generation == candidateGeneration
      && !Task.isCancelled
  }

  private func publish(_ state: CalendarSessionState) {
    guard self.state != state else {
      return
    }
    self.state = state
    onStateChange(state)
  }
}
