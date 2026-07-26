import Foundation

struct SurfaceAppearance: Equatable, Sendable {
  static let `default` = SurfaceAppearance(backgroundOpacity: 0.94)

  let backgroundOpacity: Double
}

struct TopSurfaceContent: Equatable, Sendable {
  let item: FocusItem
  let position: Int
  let itemCount: Int
  let isCurrentFocus: Bool
  let isExpanded: Bool
  let level: SurfaceLevel
  var appearance: SurfaceAppearance = .default

  let presentationRevision: UInt64

  var transitionIdentity: SurfaceTransitionIdentity {
    SurfaceTransitionIdentity(itemID: item.id, revision: presentationRevision)
  }

  var displayDetails: String? {
    nonempty(item.details)
  }

  var displaySubitems: [String] {
    item.subitems.compactMap(nonempty)
  }

  init(
    item: FocusItem,
    position: Int,
    itemCount: Int,
    isCurrentFocus: Bool,
    isExpanded: Bool,
    level: SurfaceLevel? = nil,
    appearance: SurfaceAppearance = .default
  ) {
    self.item = item
    self.position = position
    self.itemCount = itemCount
    self.isCurrentFocus = isCurrentFocus
    self.isExpanded = isExpanded
    self.level = level ?? (isExpanded ? .expanded : .compact)
    self.appearance = appearance
    presentationRevision = 0
  }

  init(
    item: FocusItem,
    position: Int,
    itemCount: Int,
    isCurrentFocus: Bool,
    presentation: FocusSurfacePayload,
    appearance: SurfaceAppearance = .default
  ) {
    self.item = item
    self.position = position
    self.itemCount = itemCount
    self.isCurrentFocus = isCurrentFocus
    isExpanded = presentation.isExpanded
    level = presentation.level
    self.appearance = appearance
    presentationRevision = presentation.revision
  }

  private func nonempty(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}

struct SurfaceTransitionIdentity: Hashable, Sendable {
  let itemID: UUID
  let revision: UInt64
}
