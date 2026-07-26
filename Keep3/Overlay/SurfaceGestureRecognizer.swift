import CoreGraphics
import Foundation

enum SurfaceGestureIntent: Equatable, Sendable {
  case advanceDepth
  case retreatDepth
  case previousComponent
  case nextComponent
  case previousTrack
  case nextTrack
}

struct SurfaceGestureContext: Equatable, Sendable {
  let component: SurfaceComponentID
  let level: SurfaceLevel
  let generation: UInt64
  let mediaSessionID: String?

  init(
    component: SurfaceComponentID,
    level: SurfaceLevel,
    generation: UInt64,
    mediaSessionID: String? = nil
  ) {
    self.component = component
    self.level = level
    self.generation = generation
    self.mediaSessionID = mediaSessionID
  }
}

struct SurfaceGestureRecognizer {
  static let lockThreshold: CGFloat = 24

  private enum Axis {
    case horizontal
    case vertical
  }

  private var context: SurfaceGestureContext?
  private var accumulatedX: CGFloat = 0
  private var accumulatedY: CGFloat = 0
  private var lockedAxis: Axis?
  private var armedIntent: SurfaceGestureIntent?
  private var isTracking = false

  mutating func updateContext(_ context: SurfaceGestureContext?) {
    guard self.context != context else {
      return
    }
    self.context = context
    resetGesture()
  }

  mutating func handle(_ event: SurfaceScrollEvent) -> SurfaceGestureIntent? {
    guard context != nil, event.isPrecise, event.momentumPhase == .none else {
      if event.momentumPhase != .none {
        resetGesture()
      }
      return nil
    }

    switch event.physicalPhase {
    case .began:
      resetGesture()
      isTracking = true
      accumulate(event)
      lockAndArmIfEligible()
      return nil
    case .changed:
      guard isTracking else {
        return nil
      }
      accumulate(event)
      lockAndArmIfEligible()
      return nil
    case .ended:
      guard isTracking else {
        return nil
      }
      let intent = armedIntent
      resetGesture()
      return intent
    case .cancelled, .none:
      resetGesture()
      return nil
    }
  }

  mutating func cancel() {
    context = nil
    resetGesture()
  }

  private mutating func accumulate(_ event: SurfaceScrollEvent) {
    accumulatedX += event.deltaX
    accumulatedY += event.deltaY
  }

  private mutating func lockAndArmIfEligible() {
    if lockedAxis == nil {
      let horizontalMagnitude = abs(accumulatedX)
      let verticalMagnitude = abs(accumulatedY)
      guard max(horizontalMagnitude, verticalMagnitude) >= Self.lockThreshold else {
        return
      }
      lockedAxis =
        horizontalMagnitude > verticalMagnitude ? .horizontal : .vertical
    }

    guard armedIntent == nil, let context else {
      return
    }
    switch lockedAxis {
    case .horizontal:
      guard context.component == .media, context.mediaSessionID != nil else {
        return
      }
      armedIntent = accumulatedX < 0 ? .previousTrack : .nextTrack
    case .vertical:
      if context.level == .expanded {
        armedIntent =
          accumulatedY < 0 ? .previousComponent : .nextComponent
      } else {
        armedIntent = accumulatedY < 0 ? .retreatDepth : .advanceDepth
      }
    case nil:
      break
    }
  }

  private mutating func resetGesture() {
    accumulatedX = 0
    accumulatedY = 0
    lockedAxis = nil
    armedIntent = nil
    isTracking = false
  }
}
