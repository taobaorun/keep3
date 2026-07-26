import Foundation

struct CalendarEvent: Identifiable, Equatable, Sendable {
  static let maximumTitleLength = 160
  static let maximumIdentifierLength = 255

  let id: String
  let title: String
  let startDate: Date
  let endDate: Date
  let isAllDay: Bool

  init(
    id: String,
    title: String,
    startDate: Date,
    endDate: Date,
    isAllDay: Bool
  ) {
    let normalizedID = String(id.prefix(Self.maximumIdentifierLength))
    self.id = normalizedID.isEmpty ? UUID().uuidString : normalizedID

    let normalizedTitle = title.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    self.title =
      normalizedTitle.isEmpty
      ? "未命名日程"
      : String(normalizedTitle.prefix(Self.maximumTitleLength))
    self.startDate = startDate
    self.endDate = max(endDate, startDate)
    self.isAllDay = isAllDay
  }
}

enum CalendarAuthorizationState: Equatable, Sendable {
  case notDetermined
  case restricted
  case denied
  case fullAccess
}

enum CalendarSessionFailure: Equatable, Sendable {
  case authorizationRequestFailed
  case queryFailed
}

enum CalendarSessionState: Equatable, Sendable {
  case disabled
  case needsPermission
  case requestingPermission
  case restricted
  case denied
  case loading
  case content(
    events: [CalendarEvent],
    isRefreshing: Bool,
    refreshFailure: CalendarSessionFailure?
  )
  case failed(CalendarSessionFailure)

  var events: [CalendarEvent] {
    guard case .content(let events, _, _) = self else {
      return []
    }
    return events
  }

  var isComponentAvailable: Bool {
    switch self {
    case .loading, .content, .failed:
      true
    case .disabled, .needsPermission, .requestingPermission, .restricted,
      .denied:
      false
    }
  }
}
