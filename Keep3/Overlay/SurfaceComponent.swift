import Foundation

enum SurfaceComponentID: String, CaseIterable, Codable, Hashable, Sendable {
  case priorities
  case media
  case calendar
}

enum SurfaceLevel: String, CaseIterable, Codable, Hashable, Sendable {
  case hardware
  case compact
  case expanded
}

enum SurfaceComponentAction: Hashable, Sendable {
  case activate
  case dismiss
  case previousItem
  case nextItem
  case togglePlayback
}

struct SurfaceComponentDescriptor: Equatable, Sendable {
  let id: SurfaceComponentID
  let supportedLevels: Set<SurfaceLevel>
  let supportedActions: Set<SurfaceComponentAction>

  static let priorities = SurfaceComponentDescriptor(
    id: .priorities,
    supportedLevels: Set(SurfaceLevel.allCases),
    supportedActions: [.activate, .dismiss, .previousItem, .nextItem]
  )

  static let media = SurfaceComponentDescriptor(
    id: .media,
    supportedLevels: Set(SurfaceLevel.allCases),
    supportedActions: [
      .activate,
      .dismiss,
      .previousItem,
      .nextItem,
      .togglePlayback,
    ]
  )

  static let calendar = SurfaceComponentDescriptor(
    id: .calendar,
    supportedLevels: Set(SurfaceLevel.allCases),
    supportedActions: [.activate, .dismiss, .previousItem, .nextItem]
  )

  static let initialOrder: [SurfaceComponentDescriptor] = [
    .priorities,
    .media,
    .calendar,
  ]
}

enum SurfaceNavigationDirection: Equatable, Sendable {
  case previous
  case next
}

enum SurfaceSelectionSource: Equatable, Sendable {
  case fallback
  case automaticMedia
  case manual
  case mediaExit
}

enum SurfaceTransitionCause: Equatable, Sendable {
  case initial
  case availability
  case pointer
  case gesture
  case keyboard
  case automaticMedia
  case mediaExit
  case displayLifecycle
  case contentUpdate
}

struct SurfaceNavigationContext: Equatable, Sendable {
  let availableComponents: Set<SurfaceComponentID>
  let transitionCause: SurfaceTransitionCause

  func hasAlternative(to component: SurfaceComponentID) -> Bool {
    availableComponents.contains(where: { $0 != component })
  }

  static func isolated(_ component: SurfaceComponentID) -> Self {
    Self(
      availableComponents: [component],
      transitionCause: .contentUpdate
    )
  }
}

struct SurfaceNavigationState: Equatable, Sendable {
  let selectedComponent: SurfaceComponentID
  let selectionSource: SurfaceSelectionSource
  let level: SurfaceLevel
  let isHovering: Bool
  let isHoverPreviewed: Bool
  let isPresented: Bool
  let generation: UInt64
  let availableComponents: Set<SurfaceComponentID>
  let transitionCause: SurfaceTransitionCause

  var effectiveLevel: SurfaceLevel {
    level == .hardware && isHoverPreviewed ? .compact : level
  }

  var navigationContext: SurfaceNavigationContext {
    SurfaceNavigationContext(
      availableComponents: availableComponents,
      transitionCause: transitionCause
    )
  }
}
