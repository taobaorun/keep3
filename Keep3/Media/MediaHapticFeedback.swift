import AppKit

@MainActor
protocol MediaHapticPerforming: AnyObject {
  func performConfirmedTrackChange()
}

@MainActor
final class AppKitMediaHapticFeedback: MediaHapticPerforming {
  func performConfirmedTrackChange() {
    NSHapticFeedbackManager.defaultPerformer.perform(
      .alignment,
      performanceTime: .now
    )
  }
}
