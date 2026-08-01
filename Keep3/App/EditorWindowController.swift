import AppKit
import SwiftUI

@MainActor
final class EditorWindowController: NSWindowController {
  private let destinationState: MainWindowDestinationState

  var destination: MainWindowDestination {
    destinationState.destination
  }

  init(
    model: AppModel,
    preferences: AppPreferences,
    mediaPreferences: MediaPreferences = MediaPreferences.live(),
    calendarPreferences: CalendarPreferences = CalendarPreferences.live(),
    calendarCoordinator: CalendarSessionCoordinator = CalendarSessionCoordinator(
      provider: EventKitCalendarAdapter()
    ),
    launchAtLoginController: LaunchAtLoginController =
      LaunchAtLoginController.live(),
    updateController: SparkleUpdateController = .inactive()
  ) {
    let destinationState = MainWindowDestinationState()
    self.destinationState = destinationState

    let window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 720, height: 520),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = "Keep3"
    window.center()
    window.isReleasedWhenClosed = false
    window.contentMinSize = CGSize(width: 720, height: 520)
    window.contentView = NSHostingView(
      rootView: RootView(
        model: model,
        preferences: preferences,
        mediaPreferences: mediaPreferences,
        calendarPreferences: calendarPreferences,
        calendarCoordinator: calendarCoordinator,
        launchAtLoginController: launchAtLoginController,
        updateController: updateController,
        destinationState: destinationState
      )
    )

    super.init(window: window)
    shouldCascadeWindows = false
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func showEditor(activate: Bool = true) {
    show(.editor, activate: activate)
  }

  func showSettings(activate: Bool = true) {
    show(.settings, activate: activate)
  }

  private func show(
    _ destination: MainWindowDestination,
    activate: Bool
  ) {
    if destinationState.destination != destination {
      destinationState.destination = destination
    }
    if activate {
      NSApp.activate()
    }
    if ProcessInfo.processInfo.environment["KEEP3_UI_TEST_STATE_PATH"] != nil,
      let screen = NSScreen.screens.first,
      let window
    {
      window.setFrameOrigin(
        CGPoint(
          x: screen.visibleFrame.midX - (window.frame.width / 2),
          y: screen.visibleFrame.midY - (window.frame.height / 2)
        )
      )
    }
    showWindow(nil)
    window?.makeKeyAndOrderFront(nil)
  }
}
