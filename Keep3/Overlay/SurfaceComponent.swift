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

  var depth: Int {
    switch self {
    case .hardware:
      0
    case .compact:
      1
    case .expanded:
      2
    }
  }
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

enum SurfaceTransitionTrigger: Equatable, Sendable {
  case initial
  case manualComponent
  case automaticComponent
  case expansion
  case collapse
  case content
  case lifecycleHide
  case lifecycleRestore
}

enum SurfaceTransitionDirection: Equatable, Sendable {
  case previous
  case neutral
  case next
}

struct SurfaceTransitionIntent: Equatable, Sendable {
  let trigger: SurfaceTransitionTrigger
  let direction: SurfaceTransitionDirection

  static let initial = SurfaceTransitionIntent(
    trigger: .initial,
    direction: .neutral
  )
  static let manualSelection = SurfaceTransitionIntent(
    trigger: .manualComponent,
    direction: .neutral
  )
  static let automaticComponent = SurfaceTransitionIntent(
    trigger: .automaticComponent,
    direction: .neutral
  )
  static let expansion = SurfaceTransitionIntent(
    trigger: .expansion,
    direction: .neutral
  )
  static let collapse = SurfaceTransitionIntent(
    trigger: .collapse,
    direction: .neutral
  )
  static let content = SurfaceTransitionIntent(
    trigger: .content,
    direction: .neutral
  )
  static let lifecycleHide = SurfaceTransitionIntent(
    trigger: .lifecycleHide,
    direction: .neutral
  )
  static let lifecycleRestore = SurfaceTransitionIntent(
    trigger: .lifecycleRestore,
    direction: .neutral
  )

  static func manualComponent(
    _ direction: SurfaceNavigationDirection
  ) -> SurfaceTransitionIntent {
    SurfaceTransitionIntent(
      trigger: .manualComponent,
      direction: direction == .previous ? .previous : .next
    )
  }
}

enum SurfaceSelectionSource: Equatable, Sendable {
  case fallback
  case automaticMedia
  case manual
  case mediaExit
}

enum SurfaceAutomaticDeferralReason: Hashable, Sendable {
  case pointerDown
  case keyboardNavigation
  case voiceOver
  case componentCommand
}

struct SurfaceNavigationState: Equatable, Sendable {
  let selectedComponent: SurfaceComponentID
  let selectionSource: SurfaceSelectionSource
  let level: SurfaceLevel
  let isHovering: Bool
  let isHoverPreviewed: Bool
  let isPresented: Bool
  let generation: UInt64
  let transitionIntent: SurfaceTransitionIntent

  var effectiveLevel: SurfaceLevel {
    level == .hardware && isHoverPreviewed ? .compact : level
  }
}
