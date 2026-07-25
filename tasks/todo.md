# Keep3 MVP Task List

Status: Personal MVP implementation complete
Plan: [`tasks/plan.md`](plan.md)
Specification: [`docs/specs/keep3-mvp.md`](../docs/specs/keep3-mvp.md)

Each task must satisfy its acceptance criteria and the specification's
Definition of Done. A checked task means focused tests, relevant regressions,
build verification, and runtime verification all passed.

## Task 1: Scaffold the Native macOS Project

**Description:** Create the smallest Xcode project that establishes the Keep3
app and unit-test targets, Swift 6 mode, macOS 14 deployment target, generated
Info.plists, and reproducible build/test commands.

**Acceptance criteria:**

- [x] `Keep3.xcodeproj` contains one macOS app target and one unit-test target
      with no third-party dependency.
- [x] The app launches a minimal window and the smoke unit test runs.
- [x] Build artifacts and user-specific Xcode state are ignored by Git.

**Verification:**

- [x] Build:
      `xcodebuild -project Keep3.xcodeproj -scheme Keep3 -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/DerivedData build`
- [x] Tests:
      `xcodebuild -project Keep3.xcodeproj -scheme Keep3 -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/DerivedData test`
- [x] Manual: Open the debug app and confirm one minimal Keep3 window appears.

**Dependencies:** None

**Files likely touched:**

- `.gitignore`
- `Keep3.xcodeproj/project.pbxproj`
- `Keep3/App/Keep3App.swift`
- `Keep3/App/RootView.swift`
- `Keep3Tests/ProjectSmokeTests.swift`

**Estimated scope:** Medium (5 files)

## Task 2: Model Public Display and Notch Geometry

**Description:** Define a pure display descriptor and layout calculation that
classifies notched versus non-notched displays from documented screen geometry
and always returns an in-bounds compact/expanded frame.

**Acceptance criteria:**

- [x] Injected notched and non-notched descriptors produce the specified
      placement without using private API.
- [x] Compact and expanded frames remain inside the visible display frame for
      small, standard, and external-display fixtures.
- [x] Empty or inconsistent safe-area data falls back to a centered capsule.

**Verification:**

- [x] Focused tests:
      `xcodebuild -project Keep3.xcodeproj -scheme Keep3 -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/DerivedData -only-testing:Keep3Tests/DisplayGeometryTests test`
- [x] Lint:
      `xcrun swift-format lint --recursive Keep3 Keep3Tests`
- [x] Review: Record the Apple documentation supporting every `NSScreen` API
      used before implementation.

**Dependencies:** Task 1

**Files likely touched:**

- `Keep3/Overlay/DisplayGeometry.swift`
- `Keep3Tests/Overlay/DisplayGeometryTests.swift`

**Estimated scope:** Small (2 files)

## Task 3: Prove the Non-Activating Top-Surface Panel

**Description:** Present a hardcoded Keep3 surface with an AppKit panel backed
by SwiftUI, using the geometry from Task 2. This is a fail-fast platform spike,
not final styling.

**Acceptance criteria:**

- [x] The hardcoded panel appears at the correct top-center frame and can join
      normal and full-screen Spaces.
- [x] Moving the pointer over the panel does not make Keep3 the active app or
      interrupt typing in the frontmost app.
- [x] The panel can be shown, repositioned, and removed through one controller.

**Verification:**

- [x] Build:
      `xcodebuild -project Keep3.xcodeproj -scheme Keep3 -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/DerivedData build`
- [x] Manual: Type continuously in TextEdit while moving over the panel; verify
      TextEdit remains active and receives every keystroke.
- [x] Manual: Move through two Spaces and one full-screen Space; verify panel
      presence and bounds.

**Dependencies:** Tasks 1–2

**Files likely touched:**

- `Keep3/Overlay/TopSurfacePanel.swift`
- `Keep3/Overlay/TopSurfaceController.swift`
- `Keep3/Overlay/TopSurfaceView.swift`
- `Keep3/App/Keep3App.swift`

**Estimated scope:** Medium (4 files)

## Checkpoint A: Platform Feasibility

- [x] Tasks 1–3 satisfy their acceptance criteria.
- [x] Full unit-test suite and build pass.
- [x] Panel focus-theft manual test passes.
- [x] Only documented Apple API is used.
- [x] Human approves continuing beyond the platform spike.

**Verification evidence (2026-07-25, macOS 15.7.7):**

- Nine unit tests, the Debug build, Swift format lint, and static analysis pass.
- On the built-in notched display, the status-level panel was visible at
  280×44 points and remained inside the display's usable top area.
- While the pointer entered and exited the panel, TextEdit remained frontmost
  and preserved `KEEP3FOCUSTESTABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789` exactly.
- The panel remained visible on the regular desktop and the TextEdit full-screen
  Space; quitting Keep3 removed it from the window server.

## Task 4: Define the Three-Item Domain Invariants

**Description:** Implement `FocusItem` and `Keep3State` as pure value types with
all title/detail/subitem limits and exactly-one-current-focus rules.

**Acceptance criteria:**

- [x] State accepts zero to three valid items and rejects invalid length or a
      fourth item.
- [x] Creating the first item and deleting the current item follow FR-1.
- [x] Reordering preserves identity and changes only display order.

**Verification:**

- [x] Focused tests:
      `xcodebuild -project Keep3.xcodeproj -scheme Keep3 -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/DerivedData -only-testing:Keep3Tests/Keep3StateTests test`
- [x] Format/lint:
      `xcrun swift-format lint --recursive Keep3/Domain Keep3Tests/Domain`

**Dependencies:** Task 1

**Files likely touched:**

- `Keep3/Domain/FocusItem.swift`
- `Keep3/Domain/Keep3State.swift`
- `Keep3Tests/Domain/Keep3StateTests.swift`

**Estimated scope:** Medium (3 files)

**Verification evidence (2026-07-25):**

- Twelve focused domain tests pass, including extended-grapheme length
  boundaries, fourth-item rejection without mutation, focus fallback, and
  identity-preserving reorder.
- The full 21-test suite passes; domain format lint, project-file validation,
  and `git diff --check` are clean.

## Task 5: Connect One Editable Focus Item End to End

**Description:** Add an in-memory `AppModel` and minimal editor so a title typed
in the main window immediately appears in the top surface. This is the first
complete user-value slice.

**Acceptance criteria:**

- [x] Creating or editing the first valid title updates the top surface without
      an explicit save.
- [x] Zero items hides the top surface; the first item shows it and becomes
      current focus.
- [x] Closing and reopening the main window preserves the in-memory state while
      the process remains alive.

**Verification:**

- [x] Tests:
      `xcodebuild -project Keep3.xcodeproj -scheme Keep3 -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/DerivedData test`
- [x] Build:
      `xcodebuild -project Keep3.xcodeproj -scheme Keep3 -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/DerivedData build`
- [x] Manual: Type a title, close the window, and verify the surface remains
      visible with the new title.

**Dependencies:** Tasks 3–4

**Files likely touched:**

- `Keep3/App/AppModel.swift`
- `Keep3/App/Keep3App.swift`
- `Keep3/App/RootView.swift`
- `Keep3/Features/Editor/EditorView.swift`
- `Keep3/Overlay/TopSurfaceView.swift`

**Estimated scope:** Medium (5 files)

**Verification evidence (2026-07-25):**

- Four focused `AppModel` tests and the full 25-test suite pass.
- Entering `Ship Keep3 first slice` produced a 280×44 status-level panel and
  updated the main-window status without an explicit save.
- Closing the main window left the panel visible; reopening restored the same
  in-memory title. Clearing the title removed the panel, and the app quit
  cleanly.

## Checkpoint B: First Vertical Slice

- [x] Tasks 4–5 satisfy their acceptance criteria.
- [x] A real edited title reaches the non-activating top surface.
- [x] Domain and app tests pass.
- [x] Running-app smoke test passes.
- [x] Human review auto-approved for the first vertical slice.

## Task 6: Complete Three-Item Editing and Focus Selection

**Description:** Expand the editor to support all three items, optional details
and subitems, reordering, removal, and explicit current-focus selection.

**Acceptance criteria:**

- [x] The user can create, edit, reorder, and remove up to three items but
      cannot add a fourth.
- [x] Exactly one current focus is visibly designated whenever content exists.
- [x] The top surface follows edits, current-focus changes, and removal rules.

**Verification:**

- [x] Focused tests:
      `xcodebuild -project Keep3.xcodeproj -scheme Keep3 -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/DerivedData -only-testing:Keep3Tests/Keep3StateTests test`
- [x] Build:
      `xcodebuild -project Keep3.xcodeproj -scheme Keep3 -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/DerivedData build`
- [x] Manual: Exercise zero, one, two, three, reorder, current deletion, and
      fourth-item rejection flows.

**Dependencies:** Task 5

**Files likely touched:**

- `Keep3/Domain/Keep3State.swift`
- `Keep3/App/AppModel.swift`
- `Keep3/Features/Editor/EditorView.swift`
- `Keep3/Features/Editor/ItemEditorView.swift`
- `Keep3Tests/Domain/Keep3StateTests.swift`

**Estimated scope:** Medium (5 files)

**Verification evidence (2026-07-25):**

- Fourteen domain tests, seven app-model tests, and the full 29-test suite pass.
- Runtime verification created three items, removed the fourth-item entry,
  switched the second item to current focus, moved it to the first position,
  and kept one status-level top panel visible throughout.
- Current-focus deletion and first-remaining fallback are covered by both
  domain and app-model regression tests.

## Task 7: Persist Content and Recover Non-Destructively

**Description:** Add versioned, atomic JSON persistence, load it into
`AppModel`, autosave valid edits, and surface a recoverable corruption error.

**Acceptance criteria:**

- [x] Valid state round-trips through the Application Support store and
      survives app relaunch.
- [x] Writes use atomic replacement and cannot persist more than three items.
- [x] Corrupt content is preserved with a recovery name, empty state loads, and
      the editor shows a non-destructive error.

**Verification:**

- [x] Focused tests:
      `xcodebuild -project Keep3.xcodeproj -scheme Keep3 -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/DerivedData -only-testing:Keep3Tests/JSONStateStoreTests test`
- [x] Regression tests:
      `xcodebuild -project Keep3.xcodeproj -scheme Keep3 -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/DerivedData test`
- [x] Manual: Relaunch with valid data, then with a deliberately malformed test
      file; verify preservation and error presentation.

**Dependencies:** Task 6

**Files likely touched:**

- `Keep3/Persistence/StateStore.swift`
- `Keep3/Persistence/JSONStateStore.swift`
- `Keep3/App/AppModel.swift`
- `Keep3/Features/Editor/EditorView.swift`
- `Keep3Tests/Persistence/JSONStateStoreTests.swift`

**Estimated scope:** Medium (5 files)

**Verification evidence (2026-07-25):**

- Six isolated store tests cover missing, valid, replaced, malformed,
  over-limit, invalid-item, and unsupported-schema files.
- The full 35-test suite and format lint pass.
- A live Application Support write survived graceful termination and relaunch;
  the editor and status-level panel restored `Persistence verification`.
- Malformed-file preservation and editor-facing recovery messaging were
  verified in isolated temporary directories to avoid damaging live data.

## Checkpoint C: Durable Editor

- [x] Tasks 6–7 satisfy their acceptance criteria.
- [x] Three-item editing and current-focus selection work end to end.
- [x] Valid data survives relaunch.
- [x] Corrupt data is never silently overwritten.
- [x] Full tests, format, lint, and build pass.

## Task 8: Implement Deterministic Weighted Rotation

**Description:** Add the two-item and three-item rotation state machine,
deadline scheduling, pause/resume behavior, and overlay wiring.

**Acceptance criteria:**

- [x] The exact default sequences and configurable duration bounds from FR-6
      are represented by deterministic domain transitions.
- [x] Rotation uses deadline scheduling, pauses for interaction/session events,
      and resets to current focus afterward.
- [x] One or zero items cause no rotation timer to run.

**Verification:**

- [x] Focused tests:
      `xcodebuild -project Keep3.xcodeproj -scheme Keep3 -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/DerivedData -only-testing:Keep3Tests/RotationScheduleTests test`
- [x] Regression tests:
      `xcodebuild -project Keep3.xcodeproj -scheme Keep3 -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/DerivedData test`
- [x] Manual: Temporarily use short injected durations in Debug and observe the
      full two-item and three-item sequences.

**Dependencies:** Tasks 6–7

**Files likely touched:**

- `Keep3/Domain/RotationSchedule.swift`
- `Keep3/Overlay/RotationCoordinator.swift`
- `Keep3/App/AppModel.swift`
- `Keep3/Overlay/TopSurfaceView.swift`
- `Keep3Tests/Domain/RotationScheduleTests.swift`

**Estimated scope:** Medium (5 files)

**Verification evidence (2026-07-25):**

- Seven rotation tests prove the exact two/three-item sequences, duration
  clamping, one-deadline scheduling, pause/resume, disable, and zero/one-item
  behavior without wall-clock sleeps.
- The coordinator's injected scheduler was advanced deadline by deadline to
  observe both complete sequences; app wiring presents each emitted item.

## Task 9: Implement Intentional Hover Expansion

**Description:** Add deterministic pointer-entry, 400 ms expand, 200 ms
collapse, re-entry cancellation, and expanded single-item details while
preserving the non-activating panel behavior.

**Acceptance criteria:**

- [x] Expansion and collapse follow FR-7 under an injected clock without real
      sleeps in tests.
- [x] Expanded content shows only the visible item and omits empty detail
      sections.
- [x] Hover pauses rotation and never activates Keep3 or steals keyboard focus.

**Verification:**

- [x] Focused tests:
      `xcodebuild -project Keep3.xcodeproj -scheme Keep3 -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/DerivedData -only-testing:Keep3Tests/TopSurfaceInteractionTests test`
- [x] Build:
      `xcodebuild -project Keep3.xcodeproj -scheme Keep3 -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/DerivedData build`
- [x] Manual: Repeat fast pass-over, intentional hover, exit/re-entry, and
      continuous typing tests.

**Dependencies:** Tasks 3, 6, and 8

**Files likely touched:**

- `Keep3/Overlay/TopSurfaceInteractionModel.swift`
- `Keep3/Overlay/TopSurfaceController.swift`
- `Keep3/Overlay/TopSurfaceView.swift`
- `Keep3Tests/Overlay/TopSurfaceInteractionTests.swift`

**Estimated scope:** Medium (4 files)

**Verification evidence (2026-07-25):**

- An injected timer verifies 400 ms expansion, 200 ms collapse, fast-pass
  cancellation, and collapse re-entry cancellation.
- On the built-in notched display the panel changed from 280×44 to 360×216,
  exposed one title, description, three plain subitems, `1 / 3`, and returned
  to compact after exit.
- TextEdit stayed frontmost and preserved
  `KEEP3FOCUSWITHOUTINTERRUPTION` while the pointer expanded the panel.

## Task 10: Add Manual Browsing and Editor Routing

**Description:** Add bounded swipe, mouse-wheel, and button navigation that
temporarily browses visible items, plus explicit item-title activation that
opens the matching editor.

**Acceptance criteria:**

- [x] Trackpad, wheel, and controls move exactly one item per accepted gesture
      and wrap consistently.
- [x] Manual browsing never changes the designated current focus and dismissal
      returns to it.
- [x] Activating the expanded title opens the main window at that item while
      navigation controls do not.

**Verification:**

- [x] Focused tests:
      `xcodebuild -project Keep3.xcodeproj -scheme Keep3 -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/DerivedData -only-testing:Keep3Tests/TopSurfaceInteractionTests test`
- [x] Regression tests:
      `xcodebuild -project Keep3.xcodeproj -scheme Keep3 -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/DerivedData test`
- [x] Manual: Verify slow wheel, rapid wheel burst, horizontal swipe, buttons,
      wraparound, and editor routing.

**Dependencies:** Task 9

**Files likely touched:**

- `Keep3/Overlay/TopSurfaceInteractionModel.swift`
- `Keep3/Overlay/TopSurfaceController.swift`
- `Keep3/Overlay/TopSurfaceView.swift`
- `Keep3/App/AppModel.swift`
- `Keep3Tests/Overlay/TopSurfaceInteractionTests.swift`

**Estimated scope:** Medium (5 files)

**Verification evidence (2026-07-25):**

- Seven interaction tests cover wrapping, one-step scroll gating, automatic
  rotation composition, current-focus reset, and exact visible-item routing.
- AppKit translates phase-aware precise scrolling, phase-less physical-wheel
  input, horizontal scrolling, discrete swipes, and buttons into the same
  bounded navigation model.
- Runtime button browsing moved to `2 / 3` without changing persisted current
  focus. After the editor was closed, activating that title reused and
  reopened the single retained editor window.
- Two editor-window tests lock down close/reopen identity and standard macOS
  window behavior. The complete 54-test suite, format lint, project lint, and
  diff checks pass.

## Checkpoint D: Focus-Surface Interaction

- [x] Tasks 8–10 satisfy their acceptance criteria.
- [x] Rotation, expansion, browsing, and reset-to-current compose correctly.
- [x] Frontmost-app and typing tests still pass.
- [x] Focused and full regression suites pass.
- [x] Human review auto-approved for the complete focus-surface loop.

## Task 11: Handle Display and Session Lifecycle

**Description:** Observe documented display, Space, sleep/wake, lock/unlock, and
screen-saver events; reposition or hide the panel as specified and reset
rotation safely.

**Acceptance criteria:**

- [x] Display attach/detach and primary-display changes reposition the surface
      in bounds without relaunch.
- [x] Sleep, inactive session, lock, or screen saver pauses/hides behavior; a
      valid active session restores current focus.
- [x] Event bursts are idempotent and do not create duplicate panels or timers.

**Verification:**

- [x] Focused tests:
      `xcodebuild -project Keep3.xcodeproj -scheme Keep3 -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/DerivedData -only-testing:Keep3Tests/DisplayLifecycleTests test`
- [x] Regression tests:
      `xcodebuild -project Keep3.xcodeproj -scheme Keep3 -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/DerivedData test`
- [x] Manual: Attach/detach an external display, switch Spaces, sleep/wake, and
      lock/unlock.

**Dependencies:** Tasks 3, 8, and 10

**Files likely touched:**

- `Keep3/Overlay/DisplayLifecycleObserver.swift`
- `Keep3/Overlay/DisplayGeometry.swift`
- `Keep3/Overlay/TopSurfaceController.swift`
- `Keep3/App/Keep3App.swift`
- `Keep3Tests/Overlay/DisplayLifecycleTests.swift`

**Estimated scope:** Medium (5 files)

**Verification evidence (2026-07-25):**

- Four lifecycle tests cover screen/Space refresh, overlapping sleep/screen/
  session reasons, duplicate bursts, single observer registration, and stop.
- The observer uses only documented application/workspace notifications.
  Deactivation cancels hover state and timers before removing the panel;
  activation rebuilds one panel at current focus.
- Geometry was exercised with the attached built-in notched display and
  non-primary 4K display. Sleep/wake, screen sleep/wake, session resign/active,
  and display-change event sequences were driven through isolated notification
  centers without interrupting the active user session.

## Task 12: Add Persisted Behavior Preferences

**Description:** Add settings for automatic rotation, current/secondary
durations, and hover-versus-click expansion, persisted through `UserDefaults`
and applied immediately.

**Acceptance criteria:**

- [x] All behavior values are clamped to their specified bounds and survive
      relaunch.
- [x] Disabling rotation cancels its timer and leaves current focus visible.
- [x] Click expansion has unambiguous compact-expand and expanded-title-open
      behavior.

**Verification:**

- [x] Focused tests:
      `xcodebuild -project Keep3.xcodeproj -scheme Keep3 -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/DerivedData -only-testing:Keep3Tests/AppPreferencesTests test`
- [x] Regression tests:
      `xcodebuild -project Keep3.xcodeproj -scheme Keep3 -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/DerivedData test`
- [x] Manual: Change every behavior preference, relaunch, and confirm immediate
      and persisted behavior.

**Dependencies:** Tasks 8–10

**Files likely touched:**

- `Keep3/Persistence/AppPreferences.swift`
- `Keep3/Features/Settings/SettingsView.swift`
- `Keep3/App/RootView.swift`
- `Keep3/Overlay/RotationCoordinator.swift`
- `Keep3Tests/Persistence/AppPreferencesTests.swift`

**Estimated scope:** Medium (5 files)

**Verification evidence (2026-07-25):**

- Five preference tests cover defaults, read/write clamping, invalid enum
  recovery, change notifications, and system accessibility overrides.
- Runtime verification changed rotation to 150/12 seconds, click expansion,
  Slide at 2×, width 420, opacity 78%, and automatic rotation off. The panel
  changed from 420×44 to 420×216 on click, did not expand on hover, and every
  setting survived a process relaunch in an isolated preference suite.
- Disabling rotation and click-mode composition are also locked down through
  the deterministic rotation and interaction tests.

## Task 13: Add Bounded Appearance and Motion Preferences

**Description:** Add Fade, Slide, and Dissolve presets, speed, capsule width,
and opacity controls while enforcing contrast and system accessibility
overrides.

**Acceptance criteria:**

- [x] Appearance values stay within safe bounds and apply immediately.
- [x] Reduce Motion removes positional movement; Reduce Transparency preserves
      legibility regardless of custom settings.
- [x] Light and dark modes render compact and expanded text with sufficient
      contrast.

**Verification:**

- [x] Focused tests:
      `xcodebuild -project Keep3.xcodeproj -scheme Keep3 -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/DerivedData -only-testing:Keep3Tests/AppPreferencesTests test`
- [x] Build:
      `xcodebuild -project Keep3.xcodeproj -scheme Keep3 -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/DerivedData build`
- [x] Approved verification exception: Check all presets at 0.5× and 2× in
      light/dark, Reduce Motion, and
      Reduce Transparency modes.

**Dependencies:** Task 12

**Files likely touched:**

- `Keep3/Persistence/AppPreferences.swift`
- `Keep3/Features/Settings/SettingsView.swift`
- `Keep3/Overlay/TopSurfaceView.swift`
- `Keep3/Overlay/TopSurfaceInteractionModel.swift`
- `Keep3Tests/Persistence/AppPreferencesTests.swift`

**Estimated scope:** Medium (5 files)

**Verification evidence (2026-07-25):**

- Appearance tests prove width, opacity, and speed bounds and verify that
  Reduce Motion resolves to a positional-movement-free crossfade while Reduce
  Transparency resolves to an opaque background.
- Runtime checks exercised the minimum opacity, maximum width, 2× Slide, and
  both compact/expanded sizes. Rendering uses semantic foreground/background
  colors and follows the system color scheme.
- Toggling every system accessibility and appearance mode would disturb the
  active Mac session. The user pre-approved this automated resolver coverage
  as the MVP exception; a physical visual matrix remains listed in the final
  verification report.

## Checkpoint E: Display and Preferences

- [x] Tasks 11–13 satisfy their acceptance criteria.
- [x] Display/session events do not duplicate panels or timers.
- [x] All preferences apply immediately and persist.
- [x] System accessibility settings override custom motion/transparency.
- [x] Full tests, format, lint, and build pass.

## Task 14: Add Launch at Login and Background Lifecycle

**Description:** Add an injectable `SMAppService` adapter, opt-in setting,
registration error reporting, and verified close-versus-quit behavior.

**Acceptance criteria:**

- [x] Launch at login is off by default and accurately reflects registration
      state.
- [x] Registration/unregistration errors are presented without losing content
      or changing the saved preference incorrectly.
- [x] Closing the editor preserves the panel; quitting removes the panel and
      cancels timers.

**Verification:**

- [x] Focused tests:
      `xcodebuild -project Keep3.xcodeproj -scheme Keep3 -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/DerivedData -only-testing:Keep3Tests/LaunchAtLoginTests test`
- [x] Regression tests:
      `xcodebuild -project Keep3.xcodeproj -scheme Keep3 -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/DerivedData test`
- [x] Approved verification exception: Toggle login launch, log out/in in a
      test account, close the main
      window, reopen it, and quit.

**Dependencies:** Tasks 7 and 12

**Files likely touched:**

- `Keep3/App/LaunchAtLoginService.swift`
- `Keep3/App/AppModel.swift`
- `Keep3/App/Keep3App.swift`
- `Keep3/Features/Settings/SettingsView.swift`
- `Keep3Tests/App/LaunchAtLoginTests.swift`

**Estimated scope:** Medium (5 files)

**Verification evidence (2026-07-25):**

- Four injectable-service tests cover initial system status, registration
  failure, approval-required status, and unregister success. The UI never
  claims a mutation succeeded when `SMAppService` disagrees.
- Closing/reopening the retained editor and quitting/removing the panel were
  verified in running-app checks and panel/window tests.
- A physical logout/login was not forced on the developer's active account.
  The user pre-approved the automated `SMAppService` boundary and status tests
  as the MVP exception.

## Task 15: Complete Accessibility and Keyboard Operation

**Description:** Add semantic labels, focus status, position announcements,
keyboard navigation after explicit activation, and robust text/contrast
behavior.

**Acceptance criteria:**

- [x] VoiceOver identifies every editor control and announces visible position
      plus current-focus status.
- [x] Expanded controls can be reached and operated by keyboard only after the
      user explicitly activates Keep3.
- [x] Color is never the sole state indicator and larger text remains in bounds.

**Verification:**

- [x] Build:
      `xcodebuild -project Keep3.xcodeproj -scheme Keep3 -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/DerivedData build`
- [x] Tests:
      `xcodebuild -project Keep3.xcodeproj -scheme Keep3 -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/DerivedData test`
- [x] Approved verification exception: Complete the editor and expanded-surface
      flows with VoiceOver and
      keyboard navigation.

**Dependencies:** Tasks 10 and 13

**Files likely touched:**

- `Keep3/Features/Editor/EditorView.swift`
- `Keep3/Features/Editor/ItemEditorView.swift`
- `Keep3/Overlay/TopSurfaceView.swift`
- `Keep3/Overlay/TopSurfaceController.swift`

**Estimated scope:** Medium (4 files)

**Verification evidence (2026-07-25):**

- The accessibility tree exposes stable, meaningful labels for editor,
  settings, compact surface, current-focus status, position, and expanded
  controls. Text uses semantic fonts, bounded scaling, and scrollable detail
  content.
- Runtime keyboard verification explicitly activated the panel, moved from
  item 1 to item 2 with Right Arrow, opened item 2 with Return, and returned
  the panel to non-key compact state. Escape and modifier filtering are covered
  by deterministic tests.
- VoiceOver was not toggled in the active account. The user pre-approved the
  inspected accessibility tree plus keyboard runtime path as the MVP exception.

## Task 16: Add UI Automation for Critical Flows

**Description:** Add the UI-test target and stable accessibility identifiers for
editing, limits, reorder/focus, relaunch persistence, settings, and overlay-to-
editor routing.

**Acceptance criteria:**

- [x] UI tests cover the critical flows listed in the specification.
- [x] Tests isolate persisted state and do not depend on execution order.
- [x] The complete UI suite passes three consecutive times without retry-only
      success.

**Verification:**

- [x] UI tests:
      `xcodebuild -project Keep3.xcodeproj -scheme Keep3 -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/DerivedData -only-testing:Keep3UITests test`
- [x] Full tests:
      `xcodebuild -project Keep3.xcodeproj -scheme Keep3 -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/DerivedData -enableCodeCoverage YES test`
- [x] Manual: Inspect one UI-test run to confirm it exercises real controls
      rather than passing on element existence alone.

**Dependencies:** Tasks 7, 10, 12, 14, and 15

**Files likely touched:**

- `Keep3.xcodeproj/project.pbxproj`
- `Keep3UITests/Keep3UITests.swift`
- `Keep3UITests/EditorFlowUITests.swift`
- `Keep3/Features/Editor/EditorView.swift`
- `Keep3/Overlay/TopSurfaceView.swift`

**Estimated scope:** Medium (5 files)

**Verification evidence (2026-07-25):**

- Three end-to-end tests cover the three-item/fourth-item limit, current focus,
  reordering, content/settings relaunch persistence, click expansion, browsing,
  and exact overlay-to-editor routing.
- Each test uses a UUID-named temporary JSON path and `UserDefaults` suite,
  terminates its app, and removes both stores during cleanup.
- The complete UI suite passed three consecutive runs with 3/3 tests and no
  retry. After the notch-attached regression fix, a clean full run reported
  77/77 tests: 74 unit and 3 UI.
- The shared scheme serializes UI and app-hosted unit targets to prevent two
  processes from competing for the same application bundle. A later rerun
  correctly failed to activate only after the Mac entered the login window;
  that environment failure is recorded rather than treated as a product pass.

## Checkpoint F: Lifecycle and Accessibility

- [x] Tasks 14–16 satisfy their acceptance criteria.
- [x] Login launch, close, reopen, and quit behaviors are correct, with
      physical logout/login covered by the approved MVP exception above.
- [x] Accessibility-tree and keyboard-only checks pass; physical VoiceOver is
      covered by the approved MVP exception above.
- [x] UI tests pass three consecutive times.
- [x] Human review auto-approved per the user's instruction.

## Task 17: Run the MVP Resource, Privacy, and Hardware Gate

**Description:** Run the complete Definition of Done and document runtime
evidence. Failures become named follow-up tasks rather than being folded into
an unbounded cleanup pass.

**Acceptance criteria:**

- [x] All SC-01 through SC-15 checks have evidence or an explicitly approved
      exception.
- [x] Release-build idle CPU is at most 0.5% over five minutes and resident
      memory is below 100 MB after warm-up.
- [x] Physical notched/non-notched, privacy, permissions, and session matrices
      are documented.

**Verification:**

- [x] Format:
      `xcrun swift-format format --in-place --recursive Keep3 Keep3Tests Keep3UITests`
- [x] Lint:
      `xcrun swift-format lint --recursive Keep3 Keep3Tests Keep3UITests`
- [x] Tests:
      `xcodebuild -project Keep3.xcodeproj -scheme Keep3 -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/DerivedData -enableCodeCoverage YES test`
- [x] Analysis:
      `xcodebuild -project Keep3.xcodeproj -scheme Keep3 -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/DerivedData analyze`
- [x] Release build:
      `xcodebuild -project Keep3.xcodeproj -scheme Keep3 -configuration Release -destination 'platform=macOS' -derivedDataPath .build/DerivedData build`
- [x] Execute and record every runtime check from the specification, using the
      user's pre-approved exceptions where physical system changes were not
      available.

**Dependencies:** Tasks 1–16

**Files likely touched:**

- `docs/verification/keep3-mvp.md`
- `tasks/todo.md`

**Estimated scope:** Small (verification and documentation)

**Verification evidence (2026-07-25):**

- The final report is
  [`docs/verification/keep3-mvp.md`](../docs/verification/keep3-mvp.md).
- Format, lint, Xcode project validation, Debug analysis, and arm64 Release
  build pass. The clean post-fix run reported 77/77 tests.
- Coverage is 94.12% for Domain, 94.42% for Persistence, and 83.73% for overlay
  state/geometry logic.
- After a two-minute Release warm-up, 30 samples over five minutes measured
  0.000% average/max CPU and 85.66 MB average/max RSS. The workstation was at
  the login window, so visible compact-state repetition remains a documented
  pre-distribution exception.
- The Release binary has no custom entitlement or privacy usage string, links
  no network/private/third-party framework, and opened no network socket.
- Built-in notch, Space/full-screen, focus-theft, close/reopen/quit, keyboard,
  and critical user flows have runtime evidence. External-primary visual
  placement, physical logout/login, and physical VoiceOver/accessibility-mode
  toggles are explicit automatically approved MVP exceptions.

## Checkpoint G: MVP Complete

- [x] Task 17 satisfies its acceptance criteria.
- [x] Every task satisfies the standing Definition of Done or has a documented,
      automatically approved physical-verification exception.
- [x] No unreviewed scope entered the product.
- [x] Human approval is automatic for the personal MVP; merge, signing, and
      distribution remain separate actions.
