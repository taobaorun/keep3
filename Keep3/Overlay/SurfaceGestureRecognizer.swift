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

struct SurfaceGestureRecognition: Equatable, Sendable {
  let feedbackIntent: SurfaceGestureIntent?
  let committedIntent: SurfaceGestureIntent?

  static let none = SurfaceGestureRecognition(
    feedbackIntent: nil,
    committedIntent: nil
  )
}

struct SurfaceGestureContext: Equatable, Sendable {
  let component: SurfaceComponentID
  let level: SurfaceLevel
  let generation: UInt64
  let mediaSessionID: String?
  let interactionFrameInScreen: CGRect

  init(
    component: SurfaceComponentID,
    level: SurfaceLevel,
    generation: UInt64,
    mediaSessionID: String? = nil,
    interactionFrameInScreen: CGRect = .infinite
  ) {
    self.component = component
    self.level = level
    self.generation = generation
    self.mediaSessionID = mediaSessionID
    self.interactionFrameInScreen = interactionFrameInScreen
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
  private var capturedInteractionFrame: CGRect?

  mutating func updateContext(_ context: SurfaceGestureContext?) {
    guard self.context != context else {
      return
    }
    self.context = context
    resetGesture()
  }

  mutating func handle(_ event: SurfaceScrollEvent) -> SurfaceGestureIntent? {
    recognize(event).committedIntent
  }

  mutating func recognize(
    _ event: SurfaceScrollEvent
  ) -> SurfaceGestureRecognition {
    guard context != nil, event.isPrecise, event.momentumPhase == .none else {
      if event.momentumPhase != .none {
        resetGesture()
      }
      return .none
    }

    switch event.physicalPhase {
    case .began:
      resetGesture()
      guard let context else {
        return .none
      }
      if let location = event.locationInScreen,
        !contextContains(location: location, context: context)
      {
        return .none
      }
      isTracking = true
      capturedInteractionFrame = context.interactionFrameInScreen
      accumulate(event)
      return SurfaceGestureRecognition(
        feedbackIntent: lockAndArmIfEligible(),
        committedIntent: nil
      )
    case .changed:
      guard isTracking else {
        return .none
      }
      guard isInsideCapturedFrame(event.locationInScreen) else {
        resetGesture()
        return .none
      }
      accumulate(event)
      return SurfaceGestureRecognition(
        feedbackIntent: lockAndArmIfEligible(),
        committedIntent: nil
      )
    case .ended:
      guard isTracking else {
        return .none
      }
      guard isInsideCapturedFrame(event.locationInScreen) else {
        resetGesture()
        return .none
      }
      let intent = armedIntent
      resetGesture()
      return SurfaceGestureRecognition(
        feedbackIntent: nil,
        committedIntent: intent
      )
    case .cancelled, .none:
      resetGesture()
      return .none
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

  private mutating func lockAndArmIfEligible() -> SurfaceGestureIntent? {
    if lockedAxis == nil {
      let horizontalMagnitude = abs(accumulatedX)
      let verticalMagnitude = abs(accumulatedY)
      guard max(horizontalMagnitude, verticalMagnitude) >= Self.lockThreshold else {
        return nil
      }
      lockedAxis =
        horizontalMagnitude > verticalMagnitude ? .horizontal : .vertical
    }

    guard armedIntent == nil, let context else {
      return nil
    }
    switch lockedAxis {
    case .horizontal:
      guard context.component == .media, context.mediaSessionID != nil else {
        return nil
      }
      armedIntent = accumulatedX < 0 ? .previousTrack : .nextTrack
    case .vertical:
      if context.level == .expanded {
        if context.component == .media, accumulatedY < 0 {
          armedIntent = .retreatDepth
        } else {
          armedIntent =
            accumulatedY < 0 ? .previousComponent : .nextComponent
        }
      } else {
        armedIntent = accumulatedY < 0 ? .retreatDepth : .advanceDepth
      }
    case nil:
      break
    }
    return armedIntent
  }

  private mutating func resetGesture() {
    accumulatedX = 0
    accumulatedY = 0
    lockedAxis = nil
    armedIntent = nil
    isTracking = false
    capturedInteractionFrame = nil
  }

  private func contextContains(
    location: CGPoint,
    context: SurfaceGestureContext
  ) -> Bool {
    context.interactionFrameInScreen.contains(location)
  }

  private func isInsideCapturedFrame(_ location: CGPoint?) -> Bool {
    guard let location, let capturedInteractionFrame else {
      return true
    }
    return capturedInteractionFrame.contains(location)
  }
}
