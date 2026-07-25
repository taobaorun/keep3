import Foundation

struct SurfaceAppearance: Equatable, Sendable {
  static let `default` = SurfaceAppearance(
    motionPreset: .fade,
    motionSpeed: 1,
    backgroundOpacity: 0.94
  )

  let motionPreset: SurfaceMotionPreset
  let motionSpeed: Double
  let backgroundOpacity: Double

  func resolved(
    reduceMotion: Bool,
    reduceTransparency: Bool
  ) -> ResolvedSurfaceAppearance {
    ResolvedSurfaceAppearance(
      motionPreset: reduceMotion ? nil : motionPreset,
      animationDuration: reduceMotion ? 0.12 : 0.45 / motionSpeed,
      backgroundOpacity: reduceTransparency ? 1 : backgroundOpacity
    )
  }
}

struct ResolvedSurfaceAppearance: Equatable, Sendable {
  let motionPreset: SurfaceMotionPreset?
  let animationDuration: TimeInterval
  let backgroundOpacity: Double
}

struct TopSurfaceContent: Equatable, Sendable {
  let item: FocusItem
  let position: Int
  let itemCount: Int
  let isCurrentFocus: Bool
  let isExpanded: Bool
  var appearance: SurfaceAppearance = .default

  var transitionIdentity: UUID {
    item.id
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
    appearance: SurfaceAppearance = .default
  ) {
    self.item = item
    self.position = position
    self.itemCount = itemCount
    self.isCurrentFocus = isCurrentFocus
    self.isExpanded = isExpanded
    self.appearance = appearance
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
    self.appearance = appearance
  }

  private func nonempty(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
