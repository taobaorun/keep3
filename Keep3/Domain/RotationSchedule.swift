import Foundation

struct RotationDurations: Equatable, Sendable {
  static let currentFocusRange: ClosedRange<TimeInterval> = 30...600
  static let secondaryRange: ClosedRange<TimeInterval> = 4...30
  static let `default` = RotationDurations(
    currentFocus: 30,
    secondary: 8
  )

  let currentFocus: TimeInterval
  let secondary: TimeInterval

  init(currentFocus: TimeInterval, secondary: TimeInterval) {
    self.currentFocus = currentFocus.clamped(to: Self.currentFocusRange)
    self.secondary = secondary.clamped(to: Self.secondaryRange)
  }
}

struct RotationSchedule: Equatable, Sendable {
  struct Entry: Equatable, Sendable {
    let itemID: UUID
    let duration: TimeInterval
  }

  private let entries: [Entry]
  private var currentIndex = 0

  init(
    itemIDs: [UUID],
    currentFocusID: UUID?,
    durations: RotationDurations = .default
  ) {
    guard let currentFocusID,
      itemIDs.contains(currentFocusID)
    else {
      entries = []
      return
    }

    let currentEntry = Entry(
      itemID: currentFocusID,
      duration: durations.currentFocus
    )
    let secondaryIDs = itemIDs.filter { $0 != currentFocusID }

    if secondaryIDs.isEmpty {
      entries = [currentEntry]
    } else {
      entries = secondaryIDs.flatMap { secondaryID in
        [
          currentEntry,
          Entry(itemID: secondaryID, duration: durations.secondary),
        ]
      }
    }
  }

  var currentEntry: Entry? {
    guard entries.indices.contains(currentIndex) else {
      return nil
    }
    return entries[currentIndex]
  }

  var canRotate: Bool {
    entries.count > 1
  }

  mutating func advance() -> Entry? {
    guard canRotate else {
      return currentEntry
    }
    currentIndex = (currentIndex + 1) % entries.count
    return currentEntry
  }

  mutating func reset() -> Entry? {
    currentIndex = 0
    return currentEntry
  }
}

extension Comparable {
  fileprivate func clamped(to range: ClosedRange<Self>) -> Self {
    min(max(self, range.lowerBound), range.upperBound)
  }
}
