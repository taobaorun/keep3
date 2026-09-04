import Foundation

struct ArchivedFocusItem: Identifiable, Codable, Equatable, Sendable {
  let item: FocusItem
  let archivedAt: Date

  var id: UUID {
    item.id
  }
}
