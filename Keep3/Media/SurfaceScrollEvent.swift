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
  let locationInScreen: CGPoint?

  init(
    deltaX: CGFloat,
    deltaY: CGFloat,
    isPrecise: Bool,
    physicalPhase: TopSurfaceGesturePhase,
    momentumPhase: SurfaceScrollMomentumPhase,
    locationInScreen: CGPoint? = nil
  ) {
    self.deltaX = deltaX
    self.deltaY = deltaY
    self.isPrecise = isPrecise
    self.physicalPhase = physicalPhase
    self.momentumPhase = momentumPhase
    self.locationInScreen = locationInScreen
  }
}

enum MediaTrackDirection: Hashable, Sendable {
  case previous
  case next
}
