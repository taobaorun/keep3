import AppKit
import SwiftUI

@MainActor
final class EditorWindowController: NSWindowController {
  init(
    model: AppModel,
    preferences: AppPreferences,
    launchAtLoginController: LaunchAtLoginController =
      LaunchAtLoginController.live()
  ) {
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
        launchAtLoginController: launchAtLoginController
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
