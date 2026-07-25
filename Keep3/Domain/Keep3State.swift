import Foundation

struct Keep3State: Equatable, Sendable {
  enum ValidationError: Error, Equatable {
    case tooManyItems
    case duplicateItemID
    case unexpectedCurrentFocus
    case missingCurrentFocus
    case unknownCurrentFocus
  }

  enum MutationError: Error, Equatable {
    case itemLimitReached
    case duplicateItemID
    case itemNotFound
    case invalidDestinationIndex
  }

  static let maximumItemCount = 3

  private(set) var items: [FocusItem]
  private(set) var currentFocusID: UUID?

  init() {
    items = []
    currentFocusID = nil
  }

  init(items: [FocusItem], currentFocusID: UUID?) throws {
    try Self.validate(items: items, currentFocusID: currentFocusID)
    self.items = items
    self.currentFocusID = currentFocusID
  }

  var currentFocus: FocusItem? {
    guard let currentFocusID else {
      return nil
    }
    return items.first { $0.id == currentFocusID }
  }

  mutating func add(_ item: FocusItem) throws {
    guard items.count < Self.maximumItemCount else {
      throw MutationError.itemLimitReached
    }
    guard !items.contains(where: { $0.id == item.id }) else {
      throw MutationError.duplicateItemID
    }

    items.append(item)
    if currentFocusID == nil {
      currentFocusID = item.id
    }
  }

  mutating func remove(id: UUID) throws {
    guard let index = items.firstIndex(where: { $0.id == id }) else {
      throw MutationError.itemNotFound
    }

    let removedCurrentFocus = currentFocusID == id
    items.remove(at: index)

    if items.isEmpty {
      currentFocusID = nil
    } else if removedCurrentFocus {
      currentFocusID = items[0].id
    }
  }

  mutating func setCurrentFocus(id: UUID) throws {
    guard items.contains(where: { $0.id == id }) else {
      throw MutationError.itemNotFound
    }
    currentFocusID = id
  }

  mutating func updateItem(
    id: UUID,
    title: String,
    details: String,
    subitems: [String]
  ) throws {
    guard let index = items.firstIndex(where: { $0.id == id }) else {
      throw MutationError.itemNotFound
    }

    let updatedItem = try FocusItem(
      id: id,
      title: title,
      details: details,
      subitems: subitems
    )
    items[index] = updatedItem
  }

  mutating func moveItem(id: UUID, to destinationIndex: Int) throws {
    guard let sourceIndex = items.firstIndex(where: { $0.id == id }) else {
      throw MutationError.itemNotFound
    }
    guard items.indices.contains(destinationIndex) else {
      throw MutationError.invalidDestinationIndex
    }
    guard sourceIndex != destinationIndex else {
      return
    }

    let item = items.remove(at: sourceIndex)
    items.insert(item, at: destinationIndex)
  }

  private static func validate(
    items: [FocusItem],
    currentFocusID: UUID?
  ) throws {
    guard items.count <= maximumItemCount else {
      throw ValidationError.tooManyItems
    }
    guard Set(items.map(\.id)).count == items.count else {
      throw ValidationError.duplicateItemID
    }

    if items.isEmpty {
      guard currentFocusID == nil else {
        throw ValidationError.unexpectedCurrentFocus
      }
      return
    }

    guard let currentFocusID else {
      throw ValidationError.missingCurrentFocus
    }
    guard items.contains(where: { $0.id == currentFocusID }) else {
      throw ValidationError.unknownCurrentFocus
    }
  }
}
