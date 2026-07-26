import Foundation

@MainActor
protocol CalendarEventProviding: AnyObject {
  func authorizationStatus() -> CalendarAuthorizationState
  func requestFullAccess() async throws -> Bool
  func events(from startDate: Date, through endDate: Date) async throws
    -> [CalendarEvent]
}
