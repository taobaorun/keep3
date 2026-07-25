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
  let revision: UInt64
  let expansionReason: SurfaceExpansionReason
}

struct MediaSurfacePayload: Equatable, Sendable {
  let sessionID: String
  let contentRevision: UInt64
  let isExpanded: Bool
  let areControlsEnabled: Bool
}

enum TopSurfacePresentation: Equatable, Sendable {
  case hidden
  case focus(FocusSurfacePayload)
  case media(MediaSurfacePayload)
}

enum TopSurfaceInteractionIntent: Equatable, Sendable {
  case focus(visibleItemID: UUID?, isExpanded: Bool)
}
