import AppKit

@MainActor
protocol SurfaceHapticPerforming: AnyObject {
  func performNavigationGesture()
  func performTrackGesture()
}

@MainActor
final class AppKitSurfaceHapticFeedback: SurfaceHapticPerforming {
  private let performFeedback:
    (
      NSHapticFeedbackManager.FeedbackPattern,
      NSHapticFeedbackManager.PerformanceTime
    ) -> Void

  init(
    performFeedback: @escaping (
      NSHapticFeedbackManager.FeedbackPattern,
      NSHapticFeedbackManager.PerformanceTime
    ) -> Void = { pattern, time in
      NSHapticFeedbackManager.defaultPerformer.perform(
        pattern,
        performanceTime: time
      )
    }
  ) {
    self.performFeedback = performFeedback
  }

  func performNavigationGesture() {
    performFeedback(.levelChange, .now)
  }

  func performTrackGesture() {
    performFeedback(.generic, .now)
  }
}
