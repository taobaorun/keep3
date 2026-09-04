import Foundation

struct Keep3State: Equatable, Sendable {
  enum ValidationError: Error, Equatable {
    case tooManyItems
    case duplicateItemID
    case archiveOrderInvalid
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
  private(set) var archivedItems: [ArchivedFocusItem]

  init() {
    items = []
    currentFocusID = nil
    archivedItems = []
  }

  init(
    items: [FocusItem],
    currentFocusID: UUID?,
    archivedItems: [ArchivedFocusItem] = []
  ) throws {
    try Self.validate(
      items: items,
      currentFocusID: currentFocusID,
      archivedItems: archivedItems
    )
    self.items = items
    self.currentFocusID = currentFocusID
    self.archivedItems = archivedItems
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
    guard
      !items.contains(where: { $0.id == item.id }),
      !archivedItems.contains(where: { $0.id == item.id })
    else {
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

  @discardableResult
  mutating func archive(id: UUID, at archivedAt: Date) throws
    -> ArchivedFocusItem
  {
    guard let index = items.firstIndex(where: { $0.id == id }) else {
      throw MutationError.itemNotFound
    }

    let archivedItem = ArchivedFocusItem(
      item: items[index],
      archivedAt: archivedAt
    )
    try remove(id: id)
    let archiveIndex =
      archivedItems.firstIndex {
        $0.archivedAt <= archivedAt
      } ?? archivedItems.endIndex
    archivedItems.insert(archivedItem, at: archiveIndex)
    return archivedItem
  }

  mutating func removeArchived(id: UUID) throws {
    guard let index = archivedItems.firstIndex(where: { $0.id == id }) else {
      throw MutationError.itemNotFound
    }
    archivedItems.remove(at: index)
  }

  mutating func undoArchive(
    id: UUID,
    to destinationIndex: Int,
    restoringCurrentFocus: Bool
  ) throws {
    guard items.count < Self.maximumItemCount else {
      throw MutationError.itemLimitReached
    }
    guard let archiveIndex = archivedItems.firstIndex(where: { $0.id == id })
    else {
      throw MutationError.itemNotFound
    }
    guard !items.contains(where: { $0.id == id }) else {
      throw MutationError.duplicateItemID
    }
    guard (0...items.count).contains(destinationIndex) else {
      throw MutationError.invalidDestinationIndex
    }

    let archivedItem = archivedItems.remove(at: archiveIndex)
    items.insert(archivedItem.item, at: destinationIndex)
    if restoringCurrentFocus || currentFocusID == nil {
      currentFocusID = archivedItem.id
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
    currentFocusID: UUID?,
    archivedItems: [ArchivedFocusItem]
  ) throws {
    guard items.count <= maximumItemCount else {
      throw ValidationError.tooManyItems
    }
    let allIDs = items.map(\.id) + archivedItems.map(\.id)
    guard Set(allIDs).count == allIDs.count else {
      throw ValidationError.duplicateItemID
    }
    guard
      zip(archivedItems, archivedItems.dropFirst()).allSatisfy({
        $0.archivedAt >= $1.archivedAt
      })
    else {
      throw ValidationError.archiveOrderInvalid
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
