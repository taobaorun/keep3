import Foundation

enum SurfaceMarkerStyle: Equatable, Sendable {
  case filledLozenge
  case outlinedOrdinal
}

enum SurfaceMotionPolicy: Equatable, Sendable {
  case standard
  case crossfade
}

struct SignatureSurfaceTransition: Equatable, Sendable {
  let duration: TimeInterval
  let motionPolicy: SurfaceMotionPolicy
  let direction: SurfaceTransitionDirection
  let directionalContentOffset: Double
  let animatesShape: Bool
  let usesProgressiveTitleBlur: Bool
  let outgoingTitleBlurRadius: Double
  let backgroundOpacity: Double
  let usesHighContrastMarkers: Bool

  static func resolve(
    intent: SurfaceTransitionIntent,
    reduceMotion: Bool,
    reduceTransparency: Bool,
    increaseContrast: Bool,
    differentiateWithoutColor: Bool,
    backgroundOpacity: Double = 0.94
  ) -> SignatureSurfaceTransition {
    let usesShapeAnimation =
      intent.trigger == .expansion
      || intent.trigger == .collapse
      || intent.trigger == .manualComponent
      || intent.trigger == .automaticComponent
    let usesTitleBlur =
      intent.trigger == .content
      || intent.trigger == .manualComponent
    let direction =
      intent.trigger == .manualComponent ? intent.direction : .neutral

    return SignatureSurfaceTransition(
      duration: reduceMotion ? 0.12 : duration(for: intent.trigger),
      motionPolicy: reduceMotion ? .crossfade : .standard,
      direction: direction,
      directionalContentOffset:
        reduceMotion ? 0 : directionalOffset(for: direction),
      animatesShape: !reduceMotion && usesShapeAnimation,
      usesProgressiveTitleBlur: !reduceMotion && usesTitleBlur,
      outgoingTitleBlurRadius: !reduceMotion && usesTitleBlur ? 7 : 0,
      backgroundOpacity: reduceTransparency ? 1 : backgroundOpacity,
      usesHighContrastMarkers: increaseContrast || differentiateWithoutColor
    )
  }

  func markerStyle(isCurrentFocus: Bool) -> SurfaceMarkerStyle {
    isCurrentFocus ? .filledLozenge : .outlinedOrdinal
  }

  private static func duration(
    for trigger: SurfaceTransitionTrigger
  ) -> TimeInterval {
    switch trigger {
    case .expansion:
      0.27
    case .collapse:
      0.20
    case .manualComponent, .automaticComponent:
      0.21
    case .content:
      0.15
    case .initial, .lifecycleHide, .lifecycleRestore:
      0.12
    }
  }

  private static func directionalOffset(
    for direction: SurfaceTransitionDirection
  ) -> Double {
    switch direction {
    case .previous:
      -9
    case .neutral:
      0
    case .next:
      9
    }
  }
}
