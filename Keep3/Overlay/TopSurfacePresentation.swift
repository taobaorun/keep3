import Foundation

enum SurfaceExpansionReason: Equatable, Sendable {
  case none
  case hover
  case click
  case quickPeek
  case manual
}

struct FocusSurfacePayload: Equatable, Sendable {
  let visibleItemID: UUID?
  let isExpanded: Bool
  let level: SurfaceLevel
  let revision: UInt64
  let expansionReason: SurfaceExpansionReason
  let isHovered: Bool

  init(
    visibleItemID: UUID?,
    isExpanded: Bool,
    level: SurfaceLevel? = nil,
    revision: UInt64,
    expansionReason: SurfaceExpansionReason,
    isHovered: Bool = false
  ) {
    self.visibleItemID = visibleItemID
    self.isExpanded = isExpanded
    self.level = level ?? (isExpanded ? .expanded : .compact)
    self.revision = revision
    self.expansionReason = expansionReason
    self.isHovered = isHovered
  }
}

enum MediaArtworkTreatment: String, CaseIterable, Codable, Equatable, Sendable {
  case artwork
  case monochrome
  case gradient
}

enum MediaSecondaryAction: String, CaseIterable, Codable, Equatable, Sendable {
  case none
  case favorite
  case shuffle
  case repeatMode
  case repeatOne
  case copySource
}

enum MediaSurfaceAction: Equatable, Sendable {
  case previous
  case togglePlayPause
  case next
  case seek(to: TimeInterval)
  case hideSource
  case favorite
  case shuffle
  case repeatMode
  case repeatOne
  case copySource(URL)
}

struct MediaSurfaceAppearance: Equatable, Sendable {
  let artworkTreatment: MediaArtworkTreatment
  let showsWaveform: Bool
  let showsArtworkFlip: Bool
  let showsMediaTitleExtras: Bool
  let secondaryAction: MediaSecondaryAction
  let backgroundOpacity: Double

  static let standard = MediaSurfaceAppearance(
    artworkTreatment: .artwork,
    showsWaveform: true,
    showsArtworkFlip: false,
    showsMediaTitleExtras: false,
    secondaryAction: .none,
    backgroundOpacity: 0.94
  )
}

struct MediaTrackPeek: Hashable, Sendable {
  let direction: MediaTrackDirection
  let title: String
  let artist: String?
}

struct MediaSurfacePayload: Equatable, Sendable {
  let sessionID: String
  let contentRevision: UInt64
  let isExpanded: Bool
  let level: SurfaceLevel
  let areControlsEnabled: Bool
  let session: MediaSession?
  let playbackState: MediaPlaybackState
  let capabilityRevision: UInt64
  let expansionReason: SurfaceExpansionReason
  let appearance: MediaSurfaceAppearance
  let trackChangeDirection: MediaTrackDirection?
  let trackPeek: MediaTrackPeek?
  let isHovered: Bool

  init(
    sessionID: String,
    contentRevision: UInt64,
    isExpanded: Bool,
    level: SurfaceLevel? = nil,
    areControlsEnabled: Bool,
    session: MediaSession? = nil,
    playbackState: MediaPlaybackState = .unknown,
    capabilityRevision: UInt64 = 0,
    expansionReason: SurfaceExpansionReason = .none,
    appearance: MediaSurfaceAppearance = .standard,
    trackChangeDirection: MediaTrackDirection? = nil,
    trackPeek: MediaTrackPeek? = nil,
    isHovered: Bool = false
  ) {
    self.sessionID = sessionID
    self.contentRevision = contentRevision
    self.isExpanded = isExpanded
    self.level = level ?? (isExpanded ? .expanded : .compact)
    self.areControlsEnabled = areControlsEnabled
    self.session = session
    self.playbackState = playbackState
    self.capabilityRevision = capabilityRevision
    self.expansionReason = expansionReason
    self.appearance = appearance
    self.trackChangeDirection = trackChangeDirection
    self.trackPeek = trackPeek
    self.isHovered = isHovered
  }

  var isTemporaryExpansion: Bool {
    expansionReason == .quickPeek
  }
}

struct CalendarSurfacePayload: Equatable, Sendable {
  let state: CalendarSessionState
  let level: SurfaceLevel
  let revision: UInt64
  let isHovered: Bool

  init(
    state: CalendarSessionState,
    level: SurfaceLevel,
    revision: UInt64,
    isHovered: Bool = false
  ) {
    self.state = state
    self.level = level
    self.revision = revision
    self.isHovered = isHovered
  }

  var isExpanded: Bool {
    level == .expanded
  }
}

enum TopSurfacePresentation: Equatable, Sendable {
  case hidden
  case focus(FocusSurfacePayload)
  case media(MediaSurfacePayload)
  case calendar(CalendarSurfacePayload)
}

extension TopSurfacePresentation {
  var componentID: SurfaceComponentID? {
    switch self {
    case .hidden:
      nil
    case .focus:
      .priorities
    case .media:
      .media
    case .calendar:
      .calendar
    }
  }

  var level: SurfaceLevel? {
    switch self {
    case .hidden:
      nil
    case .focus(let payload):
      payload.level
    case .media(let payload):
      payload.level
    case .calendar(let payload):
      payload.level
    }
  }

  func sharesSurfaceIdentity(
    with other: TopSurfacePresentation
  ) -> Bool {
    guard componentID != nil else {
      return false
    }
    return componentID == other.componentID && level == other.level
  }
}

enum TopSurfaceInteractionIntent: Equatable, Sendable {
  case focus(visibleItemID: UUID?, isExpanded: Bool)
}

enum SurfaceTransitionPhase: Equatable, Sendable {
  case hidden
  case transitioning
  case settled
}

struct SurfaceTransitionContext: Equatable, Sendable {
  let source: TopSurfacePresentation
  let target: TopSurfacePresentation
  let trigger: SurfaceTransitionTrigger
  let direction: SurfaceTransitionDirection
  let phase: SurfaceTransitionPhase
  let generation: UInt64
  let motion: SignatureSurfaceTransition
}

@MainActor
final class SurfaceTransitionCoordinator {
  private(set) var context: SurfaceTransitionContext
  private var generation: UInt64 = 0

  init(
    initialTarget: TopSurfacePresentation = .hidden,
    reduceMotion: Bool = false
  ) {
    context = SurfaceTransitionContext(
      source: initialTarget,
      target: initialTarget,
      trigger: .initial,
      direction: .neutral,
      phase: initialTarget == .hidden ? .hidden : .settled,
      generation: generation,
      motion: Self.resolveMotion(
        intent: .initial,
        reduceMotion: reduceMotion
      )
    )
  }

  @discardableResult
  func transition(
    to target: TopSurfacePresentation,
    intent: SurfaceTransitionIntent,
    reduceMotion: Bool
  ) -> SurfaceTransitionContext {
    guard target != context.target else {
      return context
    }

    generation &+= 1

    if context.phase == .transitioning,
      context.target.sharesSurfaceIdentity(with: target)
    {
      let resolvedMotion =
        context.motion.motionPolicy == (reduceMotion ? .crossfade : .standard)
        ? context.motion
        : Self.resolveMotion(
          intent: SurfaceTransitionIntent(
            trigger: context.trigger,
            direction: context.direction
          ),
          reduceMotion: reduceMotion
        )
      context = SurfaceTransitionContext(
        source: context.source,
        target: target,
        trigger: context.trigger,
        direction: context.direction,
        phase: .transitioning,
        generation: generation,
        motion: resolvedMotion
      )
      return context
    }

    let isContentUpdate = context.target.sharesSurfaceIdentity(with: target)
    let resolvedIntent = isContentUpdate ? .content : intent
    let source = context.target
    let phase: SurfaceTransitionPhase
    if target == .hidden {
      phase = .hidden
    } else if source == .hidden {
      phase = .settled
    } else {
      phase = .transitioning
    }
    context = SurfaceTransitionContext(
      source: source,
      target: target,
      trigger: resolvedIntent.trigger,
      direction: resolvedIntent.direction,
      phase: phase,
      generation: generation,
      motion: Self.resolveMotion(
        intent: resolvedIntent,
        reduceMotion: reduceMotion
      )
    )
    return context
  }

  @discardableResult
  func complete(generation: UInt64) -> Bool {
    guard context.phase == .transitioning,
      context.generation == generation
    else {
      return false
    }
    context = SurfaceTransitionContext(
      source: context.target,
      target: context.target,
      trigger: context.trigger,
      direction: context.direction,
      phase: .settled,
      generation: generation,
      motion: context.motion
    )
    return true
  }

  @discardableResult
  func cancelForLifecycle() -> SurfaceTransitionContext {
    generation &+= 1
    let intent = SurfaceTransitionIntent.lifecycleHide
    let reduceMotion = context.motion.motionPolicy == .crossfade
    context = SurfaceTransitionContext(
      source: context.target,
      target: .hidden,
      trigger: intent.trigger,
      direction: intent.direction,
      phase: .hidden,
      generation: generation,
      motion: Self.resolveMotion(
        intent: intent,
        reduceMotion: reduceMotion
      )
    )
    return context
  }

  @discardableResult
  func reconcile(
    to target: TopSurfacePresentation,
    reduceMotion: Bool
  ) -> SurfaceTransitionContext {
    generation &+= 1
    let intent = SurfaceTransitionIntent.lifecycleRestore
    context = SurfaceTransitionContext(
      source: target,
      target: target,
      trigger: intent.trigger,
      direction: intent.direction,
      phase: target == .hidden ? .hidden : .settled,
      generation: generation,
      motion: Self.resolveMotion(
        intent: intent,
        reduceMotion: reduceMotion
      )
    )
    return context
  }

  private static func resolveMotion(
    intent: SurfaceTransitionIntent,
    reduceMotion: Bool
  ) -> SignatureSurfaceTransition {
    SignatureSurfaceTransition.resolve(
      intent: intent,
      reduceMotion: reduceMotion,
      reduceTransparency: false,
      increaseContrast: false,
      differentiateWithoutColor: false
    )
  }
}
