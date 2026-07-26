import EventKit
import Foundation

struct EventKitCalendarProjectionInput {
  let identifier: String?
  let title: String?
  let startDate: Date
  let endDate: Date
  let isAllDay: Bool
  let isCancelled: Bool
}

@MainActor
final class EventKitCalendarAdapter: CalendarEventProviding {
  private let eventStore: EKEventStore

  init(eventStore: EKEventStore = EKEventStore()) {
    self.eventStore = eventStore
  }

  func authorizationStatus() -> CalendarAuthorizationState {
    switch EKEventStore.authorizationStatus(for: .event) {
    case .notDetermined:
      .notDetermined
    case .restricted:
      .restricted
    case .denied, .writeOnly:
      .denied
    case .authorized, .fullAccess:
      .fullAccess
    @unknown default:
      .denied
    }
  }

  func requestFullAccess() async throws -> Bool {
    try await withCheckedThrowingContinuation { continuation in
      eventStore.requestFullAccessToEvents { granted, error in
        if let error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume(returning: granted)
        }
      }
    }
  }

  func events(
    from startDate: Date,
    through endDate: Date
  ) async throws -> [CalendarEvent] {
    let predicate = eventStore.predicateForEvents(
      withStart: startDate,
      end: endDate,
      calendars: nil
    )
    return eventStore.events(matching: predicate).compactMap { event in
      Self.project(
        EventKitCalendarProjectionInput(
          identifier: event.eventIdentifier,
          title: event.title,
          startDate: event.startDate,
          endDate: event.endDate,
          isAllDay: event.isAllDay,
          isCancelled: event.status == .canceled
        )
      )
    }
  }

  static func project(
    _ input: EventKitCalendarProjectionInput
  ) -> CalendarEvent? {
    guard !input.isCancelled else {
      return nil
    }
    return CalendarEvent(
      id: input.identifier ?? "",
      title: input.title ?? "",
      startDate: input.startDate,
      endDate: input.endDate,
      isAllDay: input.isAllDay
    )
  }
}
