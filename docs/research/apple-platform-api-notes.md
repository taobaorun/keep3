# Apple Platform API Notes

## Task 7: Local persistence

- `FileManager.url(for:in:appropriateFor:create:)` locates and can create the
  standard Application Support directory:
  https://developer.apple.com/documentation/Foundation/FileManager/url%28for%3Ain%3AappropriateFor%3Acreate%3A%29
- `Data.WritingOptions.atomic` writes to an auxiliary file first and replaces
  the destination only after the write completes:
  https://developer.apple.com/documentation/foundation/nsdata/writingoptions
- `JSONEncoder.encode(_:)` and `JSONDecoder.decode(_:from:)` provide the
  Codable JSON boundary used by the versioned state envelope:
  https://developer.apple.com/documentation/foundation/jsonencoder/encode%28_%3A%29
  and https://developer.apple.com/documentation/foundation/jsondecoder

This file records the official Apple documentation checked before implementing
platform-sensitive Keep3 behavior. Product behavior that cannot be supported by
these public APIs must degrade gracefully rather than use a private framework.

## Tasks 12–13: Preferences and accessibility appearance

- [`UserDefaults`](https://developer.apple.com/documentation/foundation/userdefaults)
  is the documented local key-value store for app preferences. Keep3 stores only
  bounded behavior and appearance values there; priority content remains in the
  versioned JSON store.
- SwiftUI's
  [`accessibilityReduceMotion`](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducemotion)
  environment value reflects the system Reduce Motion preference.
- SwiftUI's
  [`accessibilityReduceTransparency`](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducetransparency)
  environment value reflects the system Reduce Transparency preference.

Implementation inference: stored values are clamped again when read, so an old
or manually altered preference cannot create an unsafe frame, interval, or
opacity. System accessibility values take precedence at render time rather
than overwriting the user's selected preset.

## Task 14: Launch at login

- [`SMAppService.mainApp`](https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp)
  is the documented login-item service for the containing app.
- [`SMAppService.status`](https://developer.apple.com/documentation/servicemanagement/smappservice/status-swift.property)
  reports whether the service is enabled, not registered, requires user
  approval, or is not found.
- [`SMAppService.register()`](https://developer.apple.com/documentation/servicemanagement/smappservice/register())
  and
  [`SMAppService.unregister()`](https://developer.apple.com/documentation/servicemanagement/smappservice/unregister())
  are the documented mutation APIs and can throw.

Implementation inference: the system-reported service status is the source of
truth. Keep3 never persists an optimistic Boolean that could claim launch at
login succeeded after registration failed or still requires approval.

## Tasks 15–16: Keyboard and accessibility automation

- SwiftUI's
  [`accessibilityLabel(_:)`](https://developer.apple.com/documentation/swiftui/view/accessibilitylabel(_:))
  supplies a meaningful assistive label, while
  [`accessibilityIdentifier(_:)`](https://developer.apple.com/documentation/swiftui/view/accessibilityidentifier(_:))
  supplies stable automation identity without changing the visible UI.
- [`NSWindow.canBecomeKey`](https://developer.apple.com/documentation/appkit/nswindow/canbecomekey)
  and
  [`NSWindow.makeFirstResponder(_:)`](https://developer.apple.com/documentation/appkit/nswindow/makefirstresponder(_:))
  provide the documented boundary for explicit keyboard interaction.
- [`NSEvent.addLocalMonitorForEvents(matching:handler:)`](https://developer.apple.com/documentation/appkit/nsevent/addlocalmonitorforevents(matching:handler:))
  observes keyboard events only inside Keep3 after the user explicitly enters
  keyboard-navigation mode.

Implementation inference: the top panel remains unable to become key during
normal hover or browsing. The user-visible keyboard button temporarily enables
key status, and Escape, Return, and unmodified arrow keys are handled locally;
the monitor is removed again when keyboard mode ends or the panel is removed.

## Task 11: Display and session lifecycle

- [`NSApplication.didChangeScreenParametersNotification`](https://developer.apple.com/documentation/appkit/nsapplication/didchangescreenparametersnotification)
  is posted on the main actor when attached-display configuration changes.
- [`NSWorkspace.notificationCenter`](https://developer.apple.com/documentation/appkit/nsworkspace)
  is the required center for workspace lifecycle notifications, including
  active-Space changes, session resign/become-active, device sleep/wake, and
  screen sleep/wake.
- [`NSWorkspace.sessionDidResignActiveNotification`](https://developer.apple.com/documentation/appkit/nsworkspace/sessiondidresignactivenotification)
  explicitly exists so apps can suspend processing when the user session
  switches out and resume when it switches back in.
- [`NSWorkspace.didWakeNotification`](https://developer.apple.com/documentation/appkit/nsworkspace/didwakenotification)
  must be registered through the workspace notification center.

Implementation inference: Keep3 treats session inactivity, system sleep, and
screen sleep as independent unavailability reasons. The panel is restored only
after all active reasons clear, preventing wake/unlock event bursts from
creating duplicate panels or timers. Screen-sleep and session notifications
cover the documented lock/screen-saver lifecycle without relying on
undocumented distributed-notification names.

## Tasks 9–10: Pointer, gesture, and editor-window interaction

- [`NSTrackingArea`](https://developer.apple.com/documentation/appkit/nstrackingarea)
  delivers pointer enter/exit events to its owner. The `.activeAlways` and
  `.inVisibleRect` options allow Keep3's non-activating view to track its
  current visible bounds even while another app remains active.
- [`NSEvent.phase`](https://developer.apple.com/documentation/appkit/nsevent/phase-swift.property)
  identifies began, changed, ended, and cancelled phases for fluid scroll
  gestures. Apple documents that legacy wheel and momentum events can have no
  phase, so Keep3 treats a phase-less physical wheel event as one bounded
  gesture and ignores phase-less momentum.
- [`NSEvent`](https://developer.apple.com/documentation/appkit/nsevent)
  exposes documented scrolling deltas and swipe deltas to AppKit responders.
- [`NSWindowController.showWindow(_:)`](https://developer.apple.com/documentation/appkit/nswindowcontroller/showwindow(_:))
  presents the window owned by a controller, while
  [`NSWindow.isReleasedWhenClosed`](https://developer.apple.com/documentation/appkit/nswindow/isreleasedwhenclosed)
  controls whether closing releases its backing window.
- The application-delegate
  [`applicationShouldHandleReopen(_:hasVisibleWindows:)`](https://developer.apple.com/documentation/appkit/nsapplicationdelegate/applicationshouldhandlereopen(_:hasvisiblewindows:))
  hook lets a Dock reopen request present Keep3's retained editor window.

Implementation inference: input events are translated into the testable
interaction model at the panel boundary. Pointer tracking pauses rotation but
does not change the panel's non-activating/key-window rules. The editor uses one
retained AppKit window backed by SwiftUI, so close/reopen and item routing do
not depend on a scene action captured from a window that no longer exists.
Opening an item is the sole path that explicitly activates the app and
presents the editor.

## Task 2: Display and Notch Geometry

Verified on 2026-07-25 against the macOS 15.5 SDK documentation:

- [`NSScreen.frame`](https://developer.apple.com/documentation/appkit/nsscreen/frame)
  is the display's full rectangle in global screen coordinates, including the
  menu bar and Dock.
- [`NSScreen.visibleFrame`](https://developer.apple.com/documentation/appkit/nsscreen/visibleframe)
  is the currently safe drawable portion after the menu bar and Dock are
  removed. On a Mac with a camera housing, Apple also excludes the housing and
  its two visible side areas from this rectangle.
- [`NSScreen.safeAreaInsets`](https://developer.apple.com/documentation/appkit/nsscreen/safeareainsets)
  describes edge distances that keep content unobscured. Apple explicitly notes
  that the top inset can represent the camera housing.
- [`NSScreen.auxiliaryTopLeftArea`](https://developer.apple.com/documentation/appkit/nsscreen/auxiliarytopleftarea)
  and
  [`NSScreen.auxiliaryTopRightArea`](https://developer.apple.com/documentation/appkit/nsscreen/auxiliarytoprightarea)
  return the unobscured top corners outside the safe area, in global screen
  coordinates. They are `nil` when the top is not obscured.
- [`NSScreen.screens`](https://developer.apple.com/documentation/appkit/nsscreen/screens)
  must not be cached because displays can be added, removed, or reconfigured.

Implementation inference: Keep3 may classify a display as notched only when the
top safe-area inset is positive and both auxiliary top areas form a valid gap
inside the display frame. Missing or contradictory data is not enough evidence
of a notch and must use the non-notched, top-center fallback.

## Task 3: Non-Activating Panel

Verified on 2026-07-25 against the macOS 15.5 SDK documentation:

- [`NSWindow.StyleMask.nonactivatingPanel`](https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/nonactivatingpanel)
  defines a panel that does not activate its owning app.
- [`NSPanel.becomesKeyOnlyIfNeeded`](https://developer.apple.com/documentation/appkit/nspanel/becomeskeyonlyifneeded)
  keeps a non-activating panel from becoming key unless the hit view explicitly
  requires keyboard input. Keep3's spike contains no keyboard-input view.
- [`NSWindow.canBecomeKey`](https://developer.apple.com/documentation/appkit/nswindow/canbecomekey)
  controls whether attempts to make the window key can succeed. The Keep3 panel
  overrides this to `false` because hover and compact-surface clicks must not
  take keyboard focus.
- [`NSWindow.CollectionBehavior.canJoinAllSpaces`](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/canjoinallspaces)
  makes a window appear in all Spaces, while
  [`fullScreenAuxiliary`](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/fullscreenauxiliary)
  allows it to share a Space with a full-screen window.
- [`NSWindow.orderFrontRegardless()`](https://developer.apple.com/documentation/appkit/nswindow/orderfrontregardless())
  orders a window to the front of its level even while another app is active,
  without changing the key or main window.
- [`NSWindow.Level.statusBar`](https://developer.apple.com/documentation/appkit/nswindow/level-swift.struct/statusbar)
  is the documented level for a status window.
- [`NSHostingView`](https://developer.apple.com/documentation/swiftui/nshostingview)
  is Apple's bridge for embedding a SwiftUI hierarchy in an AppKit view
  hierarchy.

Implementation inference: a borderless `NSPanel` using the non-activating style,
an explicit non-key subclass, status-window level, all-Spaces/full-screen
collection behavior, and an `NSHostingView` is sufficient for the platform
spike. The runtime focus test remains authoritative because window-manager
behavior cannot be proven by type-level tests alone.
