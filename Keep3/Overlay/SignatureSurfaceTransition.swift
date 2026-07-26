import Foundation

enum SurfaceMarkerStyle: Equatable, Sendable {
  case filledLozenge
  case outlinedOrdinal
}

struct SignatureSurfaceTransition: Equatable, Sendable {
  let duration: TimeInterval
  let animatesShape: Bool
  let usesProgressiveTitleBlur: Bool
  let outgoingTitleBlurRadius: Double
  let backgroundOpacity: Double
  let usesHighContrastMarkers: Bool

  static func resolve(
    reduceMotion: Bool,
    reduceTransparency: Bool,
    increaseContrast: Bool,
    differentiateWithoutColor: Bool,
    backgroundOpacity: Double = 0.94
  ) -> SignatureSurfaceTransition {
    SignatureSurfaceTransition(
      duration: reduceMotion ? 0.12 : 0.76,
      animatesShape: !reduceMotion,
      usesProgressiveTitleBlur: !reduceMotion,
      outgoingTitleBlurRadius: reduceMotion ? 0 : 7,
      backgroundOpacity: reduceTransparency ? 1 : backgroundOpacity,
      usesHighContrastMarkers: increaseContrast || differentiateWithoutColor
    )
  }

  func markerStyle(isCurrentFocus: Bool) -> SurfaceMarkerStyle {
    isCurrentFocus ? .filledLozenge : .outlinedOrdinal
  }
}
