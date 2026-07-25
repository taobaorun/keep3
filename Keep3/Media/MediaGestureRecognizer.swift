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

  var focusNavigationDelta: CGFloat {
    abs(deltaX) > abs(deltaY) ? -deltaX : deltaY
  }
}

enum MediaTrackDirection: Equatable, Sendable {
  case previous
  case next

  var action: MediaSurfaceAction {
    switch self {
    case .previous:
      .previous
    case .next:
      .next
    }
  }
}

struct MediaGestureRecognizer {
  static let verticalThreshold: CGFloat = 24

  private(set) var sessionID: String?
  private var accumulatedX: CGFloat = 0
  private var accumulatedY: CGFloat = 0
  private var armedDirection: MediaTrackDirection?

  mutating func updateSession(_ sessionID: String?) {
    guard self.sessionID != sessionID else {
      return
    }
    self.sessionID = sessionID
    resetGesture()
  }

  mutating func handle(
    _ event: SurfaceScrollEvent
  ) -> MediaTrackDirection? {
    guard sessionID != nil, event.isPrecise,
      event.momentumPhase == .none
    else {
      return nil
    }

    switch event.physicalPhase {
    case .began:
      resetGesture()
      accumulatedX = event.deltaX
      accumulatedY = event.deltaY
      armIfEligible()
      return nil
    case .changed:
      accumulatedX += event.deltaX
      accumulatedY += event.deltaY
      armIfEligible()
      return nil
    case .ended:
      defer { resetGesture() }
      return armedDirection
    case .cancelled, .none:
      resetGesture()
      return nil
    }
  }

  mutating func cancel() {
    sessionID = nil
    resetGesture()
  }

  private mutating func armIfEligible() {
    guard armedDirection == nil,
      abs(accumulatedY) >= Self.verticalThreshold,
      abs(accumulatedY) > abs(accumulatedX)
    else {
      return
    }
    armedDirection = accumulatedY > 0 ? .next : .previous
  }

  private mutating func resetGesture() {
    accumulatedX = 0
    accumulatedY = 0
    armedDirection = nil
  }
}
