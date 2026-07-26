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

  init(
    visibleItemID: UUID?,
    isExpanded: Bool,
    level: SurfaceLevel? = nil,
    revision: UInt64,
    expansionReason: SurfaceExpansionReason
  ) {
    self.visibleItemID = visibleItemID
    self.isExpanded = isExpanded
    self.level = level ?? (isExpanded ? .expanded : .compact)
    self.revision = revision
    self.expansionReason = expansionReason
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
    trackPeek: MediaTrackPeek? = nil
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
  }

  var isTemporaryExpansion: Bool {
    expansionReason == .quickPeek
  }
}

struct CalendarSurfacePayload: Equatable, Sendable {
  let state: CalendarSessionState
  let level: SurfaceLevel
  let revision: UInt64

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
}

enum TopSurfaceInteractionIntent: Equatable, Sendable {
  case focus(visibleItemID: UUID?, isExpanded: Bool)
}
