import CoreGraphics
import Foundation

enum SurfaceScrollMomentumPhase: Equatable, Sendable {
  case none
  case began
  case changed
  case ended
}

struct SurfaceScrollEvent: Equatable, Sendable {
  let deltaX: CGFloat
  let deltaY: CGFloat
  let isPrecise: Bool
  let physicalPhase: TopSurfaceGesturePhase
  let momentumPhase: SurfaceScrollMomentumPhase
}

enum MediaTrackDirection: Equatable, Sendable {
  case previous
  case next
}
