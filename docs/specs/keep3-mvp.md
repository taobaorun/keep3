# Spec: Keep3

Status: MVP implemented; event-surface product iteration in progress under
[`docs/plans/2026-07-26-001-feat-event-surface-interactions-plan.md`](../plans/2026-07-26-001-feat-event-surface-interactions-plan.md)
Source idea: [`docs/ideas/keep3.md`](../ideas/keep3.md)

## Objective

Keep3 is a quiet, native macOS event surface. It keeps at most three
user-defined priorities in sight, yields to active media, and can show the
next relevant local Calendar commitment after explicit opt-in. These components
share the top center of the primary display without becoming a task manager or
interrupting the user's work.

The first release is for the developer's personal workflow. It validates one
job:

> When my attention is pulled elsewhere, I want to glance at the top of my Mac
> and recover the thing I meant to focus on, without opening a task manager.

### Product Success

After 14 consecutive workdays:

- The user still chooses to launch Keep3 every day.
- The user reports at least one moment on most workdays when Keep3 helped them
  recover their intended focus.
- The top surface is not disabled because it is distracting, obstructive, or
  unreliable.

Completion counts, streaks, and productivity scores are explicitly not success
measures.

## Scope

### In Scope

- A native macOS editing window for up to three priority items.
- One designated current-focus item whenever at least one item exists.
- A compact top surface adapted to notched and non-notched displays.
- Weighted automatic rotation plus manual browsing.
- Intentional hover expansion with details.
- Local persistence and launch-at-login support.
- A small set of appearance and interaction preferences.
- A media-first top surface for the active system media session.
- An opt-in, local-only EventKit Calendar component.
- Hardware-aligned, compact, and expanded surface levels.
- Vertical component/depth gestures and horizontal media track gestures.
- Accessibility, reduced-motion behavior, and idle resource constraints.

### Out of Scope

- Completion state, checkboxes, progress, history, review, or analytics.
- Priority-item dates, deadlines, reminders, or notifications.
- Automatic activity monitoring or drift detection.
- Reminders, third-party calendar services, accounts, cloud, or team integration.
- Clipboard, file shelf, system HUD, or other general notch utilities.
- iPhone, iPad, Apple Watch, ActivityKit, or Live Activities.
- Independent overlays per display or freely draggable overlay placement.

## Functional Requirements

### FR-1: Priority Items

1. The user can maintain zero to three items.
2. Each item has:
   - A required title containing 1–60 user-perceived characters after trimming.
   - An optional description containing up to 500 user-perceived characters.
   - Zero to eight optional plain-text subitems, each containing up to 120
     user-perceived characters.
3. Subitems are explanatory text. They have no checked, completed, deferred, or
   progress state.
4. The user can reorder items.
5. Reordering changes their secondary rotation order.
6. When one or more items exist, exactly one is the designated current focus.
7. The first item created becomes the current focus automatically.
8. If the current-focus item is removed, the first remaining item becomes the
   current focus.
9. Removing the final item hides the top surface.

### FR-2: Editing and Persistence

1. Changes autosave after valid edits.
2. Saved content survives app termination, logout, and Mac restart.
3. Content is stored as versioned Codable JSON under the app's Application
   Support directory.
4. Preferences are stored in `UserDefaults`.
5. Persistence uses atomic replacement so a failed write cannot leave a
   partially written state file.
6. If persisted content is unreadable, Keep3 preserves the unreadable file for
   recovery, starts with an empty state, and presents a non-destructive error in
   the main window.
7. Keep3 performs no network requests.

### FR-3: Main Window

1. The main window exposes all content editing, ordering, current-focus
   selection, and settings.
2. Editing an item updates the top surface without requiring an explicit save.
3. Activating an item title in the expanded surface opens or activates the main
   window and selects the corresponding item.
4. Closing the main window does not quit Keep3 or remove the top surface.
5. Quitting Keep3 removes the top surface immediately.
6. Launch-at-login is opt-in and disabled by default.

### FR-4: Top Surface Placement

1. Keep3 displays on the system primary display only.
2. It follows changes to display configuration and repositions without
   requiring a relaunch.
3. On a display with a hardware camera notch, the surface is centered on the
   notch geometry and may extend below it; it must not pretend pixels exist
   inside the physical camera cutout.
4. On a display without a notch, the surface appears as a centered floating
   capsule immediately below the menu bar.
5. The surface joins all user Spaces, including full-screen application Spaces.
6. The surface does not appear on the login window, lock screen, or screen
   saver.
7. The compact and expanded surfaces remain within the visible frame of the
   display at every supported screen size.
8. The surface never takes keyboard focus merely because the pointer enters or
   hovers over it.

### FR-5: Compact Presentation

1. With content present, the compact surface displays exactly one item title.
2. Titles use a single line and truncate at the tail when space is insufficient.
3. The designated current-focus item is the initial item after launch, display
   changes, editing, and hover dismissal.
4. With one item, rotation and manual navigation controls are absent.
5. With two or three items, a subtle position indicator is available in the
   expanded state.
6. With zero items, no top surface is shown; opening Keep3 shows the editor's
   empty state.

### FR-6: Weighted Rotation

For three items, the default sequence is:

1. Current focus for 30 seconds.
2. First secondary item for 8 seconds.
3. Current focus for 30 seconds.
4. Second secondary item for 8 seconds.
5. Repeat.

For two items, the sequence is:

1. Current focus for 30 seconds.
2. Secondary item for 8 seconds.
3. Repeat.

Additional rules:

1. Automatic rotation can be disabled.
2. The user can configure current-focus duration from 30–600 seconds.
3. The user can configure secondary duration from 4–30 seconds.
4. Intentional expansion, manually browsing, editing content, sleeping, or
   deactivating the session pauses rotation; a quick pointer pass does not.
5. When an interaction ends, the compact surface returns to the designated
   current focus and restarts its duration.
6. Manual browsing changes only the visible item; it does not change the
   designated current focus.
7. Timer scheduling does not use a display-link or continuously running
   animation while idle.

### FR-7: Expansion and Navigation

1. In the default interaction mode, a quick pointer pass does not pause or reset
   rotation.
2. After a 400-millisecond intentional-hover delay, rotation pauses and the
   surface expands.
3. Every expanded surface component collapses to compact when the pointer exits
   its active frame. Priorities, Media, Calendar, and future component types use
   the same rule rather than implementing provider-specific dismissal.
4. Re-entering follows the normal hover or click expansion trigger; an
   in-progress collapse is never kept alive by stale component state.
5. Expanded content displays only the currently visible item:
   - Title
   - Optional description
   - Optional subitems
   - Position indicator such as `1 / 3`
   - Previous and next controls when applicable
6. Horizontal trackpad swipes, vertical mouse-wheel movement, and previous/next
   controls browse items.
7. Scroll and swipe thresholds prevent incidental movement from causing more
   than one navigation step.
8. A preference can replace hover expansion with click expansion. In this mode,
   clicking the compact surface expands it; clicking the item title in the
   expanded surface opens the main window.
9. Expansion and navigation do not activate Keep3 or steal keyboard focus from
   the frontmost application.
10. Activating the item itself opens the main window; navigation controls do
    not.

### FR-8: Motion and Appearance

1. Hardware, compact, and expanded level changes use one shared top-aligned,
   non-overshooting ease-in-out transition lasting 220 milliseconds.
   Priorities, Media, Calendar, and future component types inherit this motion
   without provider-specific animation switches.
2. Component content changes atomically at the level boundary so the outgoing
   layout is never stretched through the resizing container. A bounded
   220-millisecond opacity transition may be used for item-to-item handoff.
3. Content providers do not add independent long-running shape, position, or
   staggered transitions to level changes.
4. When Reduce Motion is enabled in macOS, Keep3 removes the container
   transition and positional movement; state and dismissal semantics remain
   unchanged.
5. The user can adjust capsule width within layout-safe bounds.
6. On floating displays, the expanded Priorities surface is 32 points wider
   than its compact surface, preserving a 16-point centered reveal on each
   edge. On notched displays, its expanded width never contracts below the
   resolved compact width.
7. The user can adjust background opacity within a range that preserves text
   contrast.
8. Appearance follows the system light/dark appearance.

### FR-9: Accessibility

1. Every editable field and interactive control has a meaningful accessibility
   label.
2. Expanded navigation is usable with keyboard focus after the user explicitly
   activates Keep3.
3. VoiceOver announces the visible item's position and current-focus status.
4. Text remains legible with macOS text-size and contrast accessibility
   settings.
5. Color is not the only indicator of current focus or selection.
6. Reduced Motion and Reduce Transparency system settings are respected.
7. In expanded Media, the keyboard and VoiceOver retreat action is labeled
   "Return to normal player", collapses to compact Media, moves accessibility
   focus to that compact player, and announces the resulting state once.

### FR-10: Resource Use and Privacy

1. The app requests no Accessibility, Screen Recording, Full Disk Access,
   Contacts, Reminders, or notification permission. Calendar full access is
   requested only after the user explicitly enables the Calendar component in
   Settings.
2. The app contains no analytics, telemetry, advertisements, or crash-reporting
   SDK.
3. After a two-minute warm-up in a release build on Apple Silicon, compact idle
   mode averages no more than 0.5% CPU over five minutes.
4. Compact idle resident memory remains below 100 MB.
5. No timer fires more frequently than once per second, and idle rotation uses
   deadline-based scheduling rather than polling.

### FR-11: Media-First Surface

1. When media-first mode is enabled and a new eligible system media session is
   playing, media auto-selects once in the shared top surface.
2. A controllable paused session remains available for manual component
   navigation. Pausing selected media keeps Media selected so its Play control
   can resume playback without opening the source application.
3. A paused session does not automatically replace a manually selected
   component. Starting playback may auto-select Media once unless the user
   already selected another component during that session.
4. Stopping, interruption, player exit, source suppression, or loss of the
   media session removes Media and returns the surface to an available
   component.
5. Compact media shows artwork or a fallback, title, artist, and a playback
   indicator. Expanded media shows metadata, progress, capability-gated
   controls, and the configured secondary action. When the compact playback
   indicator is a waveform, pointer hover reveals the current Play or Pause
   action in place and activating that region toggles playback.
6. A confirmed new track triggers a bounded peek without opening full controls.
   On notched displays, a continuously rounded 68-point metadata shelf extends
   below the hardware notch with separate, bounded title and artist lines;
   metadata never replaces artwork or waveform content in either wing. Next
   preserves the baseline left edge and left wing while changing only the
   right and lower regions; Previous mirrors this by preserving the right edge
   and right wing. Floating placement uses the same hierarchy in a rounded
   capsule. Hover or click expansion remains under direct user control.
7. Every media waveform uses a readable accent derived and cached from the
   current confirmed cover. Missing, malformed, transparent, grayscale, or
   low-contrast artwork uses a deterministic readable fallback. Playback-state
   and capability-only refreshes retain the confirmed cover when the provider
   temporarily omits artwork; a confirmed content change without artwork clears
   the previous cover.
8. Precise horizontal two-finger gestures dispatch at most one previous/next
   command per physical gesture. Vertical intent belongs to surface depth and
   component navigation rather than track switching; momentum never switches
   tracks. From expanded Media, Up returns to compact Media without selecting
   another component, while Down retains next-component navigation.
7. A supported track gesture emits one haptic when its precise two-finger
   displacement first crosses the gesture lock threshold, while the gesture is
   still active. Command completion emits no second haptic; newer same-session
   content remains required for the metadata peek.
8. The global media boundary runs in an embedded XPC service. Failure,
   interruption, incompatible symbols, or malformed payloads retract media
   state without affecting priorities or the editor.
9. Media settings include the master switch, Quick Peek, manual expansion,
   artwork treatment, waveform, secondary action, opacity, frontmost-player
   suppression, and persisted per-source suppression.

### FR-12: Event Surface and Calendar

1. The ordered initial components are priorities, media, and Calendar;
   unavailable components are skipped.
2. A manual component selection is not overridden by media progress snapshots.
   Media pause, exit, or session loss returns to the latest designated priority.
3. A notched display has hardware-aligned, compact, and expanded levels.
   Hover previews compact, click expands, and deliberate vertical gestures
   advance depth. From expanded Media, Up collapses to compact Media while Down
   selects the next available component in compact; expanded non-media
   components retain their established directional component navigation.
   Pointer exit collapses every expanded component to compact using the shared
   surface motion contract.
4. Calendar is disabled by default, requests EventKit access only from Settings,
   keeps no event persistence, and publishes at most five non-cancelled
   title/time projections from the next 24 hours.
5. Calendar content never enters the media XPC service or a network path.

## Tech Stack

- Xcode 16.4 baseline.
- Swift 6 language mode.
- macOS 14.0 deployment target.
- SwiftUI for the main window and surface content.
- AppKit for non-activating panel lifecycle, screen geometry, Space behavior,
  and pointer interaction.
- Foundation for Codable persistence and scheduling abstractions.
- ServiceManagement `SMAppService` for launch at login.
- XCTest and XCUITest for automated verification.
- `swift-format` from the Xcode toolchain.
- No third-party runtime or development dependencies.

All screen, notch, window, persistence, and settings behavior uses documented
Apple APIs. Global cross-application media control is an explicit personal-build
exception: public `MediaPlayer` APIs expose an app's own now-playing session,
not the system-wide session controlled by Control Center. Keep3 therefore
dynamically resolves the private system `MediaRemote.framework` inside a
separately embedded XPC service, validates every required symbol at runtime,
uses a versioned property-list boundary, and fails closed to priorities.

This exception is not App Store compatible and must be re-evaluated for every
macOS release before distribution.

## Commands

These commands become executable after the Xcode project is created.

### Build

```bash
xcodebuild -project Keep3.xcodeproj -scheme Keep3 -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/DerivedData build
```

### Test With Coverage

```bash
xcodebuild -project Keep3.xcodeproj -scheme Keep3 -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/DerivedData -enableCodeCoverage YES test
```

### Static Analysis

```bash
xcodebuild -project Keep3.xcodeproj -scheme Keep3 -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/DerivedData analyze
```

### Lint

```bash
xcrun swift-format lint --recursive Keep3 Keep3Tests Keep3UITests
```

### Format

```bash
xcrun swift-format format --in-place --recursive Keep3 Keep3Tests Keep3UITests
```

### Run the Debug Build

```bash
open .build/DerivedData/Build/Products/Debug/Keep3.app
```

## Project Structure

```text
Keep3.xcodeproj/                  Xcode project
Keep3/
  App/                            App entry point and lifecycle
  Domain/                         Models, validation, and rotation rules
  Persistence/                    JSON state store and preference store
  Overlay/                        Panel controller, geometry, and top surface
  Features/
    Editor/                       Three-item editing experience
    Settings/                     MVP preferences
  Resources/                      Assets, localization, and app metadata
Keep3Tests/
  Domain/                         Validation and rotation tests
  Persistence/                    Round-trip and recovery tests
  Overlay/                        Geometry and state-machine tests
Keep3UITests/                     Critical editor and settings flows
docs/
  ideas/                          Product idea one-pagers
  specs/                          Living specifications
tasks/
  plan.md                         Reviewed technical plan
  todo.md                         Dependency-ordered task list
```

The MVP uses one application target, one unit-test target, and one UI-test
target. New modules or packages require evidence that the single-target
structure has become a real constraint.

## Code Style

Use Swift API Design Guidelines, explicit domain names, value types for domain
state, and narrow protocols only at external seams such as time, persistence,
and display geometry. UI views do not read files or schedule timers directly.

```swift
import Foundation

struct FocusItem: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var title: String
    var details: String
    var subitems: [String]
}
```

Conventions:

- Types use `UpperCamelCase`; methods, properties, and enum cases use
  `lowerCamelCase`.
- Prefer `struct` and immutable values unless identity or shared mutable state
  is required.
- UI-facing mutable state is isolated to `@MainActor`.
- Use structured concurrency; do not introduce detached tasks for UI state.
- Avoid abbreviations except established Apple terms.
- Comments explain why a constraint exists, not what the code visibly does.
- Keep files focused; a file should normally contain one primary type.
- No speculative generic repositories, coordinators, or design-system layers.

## Testing Strategy

### Unit Tests

Unit tests cover all non-view behavior:

- Zero-to-three item validation and character limits.
- Exactly-one-current-focus invariants.
- Deletion and reordering rules.
- Two-item and three-item weighted rotation sequences.
- Pause, resume, manual browsing, and reset-to-current behavior.
- Duration preference bounds.
- Persistence round trips, schema versioning, atomic replacement, and corrupt
  file recovery.
- Notched and non-notched geometry using injected screen descriptions.
- Expansion/collapse delay state transitions using an injected clock.

Tests use deterministic clocks and temporary directories. They must not sleep
for real time or depend on the developer's screen configuration.

### UI Tests

XCUITest covers:

- Creating three items and selecting the current focus.
- Rejecting a fourth item.
- Reordering items.
- Relaunch persistence.
- Changing rotation and expansion settings.
- Clicking an overlay item opens the matching editor selection.

### Manual Runtime Verification

Before MVP completion:

- Verify on at least one MacBook with a hardware notch.
- Verify non-notch placement on an external display or non-notched Mac.
- Verify behavior across multiple Spaces and one full-screen app.
- Verify sleep/wake, screen lock/unlock, and display attach/detach.
- Verify VoiceOver labels and Reduce Motion behavior.
- Verify the surface never steals focus while typing in another app.
- Measure idle CPU and memory in a release build.

### Coverage Expectations

- Domain and Persistence code maintain at least 80% line coverage.
- Overlay state and geometry logic maintain at least 70% line coverage.
- SwiftUI rendering code has no numeric target; it is covered through UI tests
  and manual runtime checks.
- A test that would pass with the new behavior removed does not count as
  coverage.

## Boundaries

### Always Do

- Update this spec before changing agreed behavior or scope.
- Use documented Apple APIs.
- Keep content local and avoid network capabilities.
- Preserve the zero-to-three and exactly-one-current-focus invariants.
- Honor system accessibility preferences.
- Run format, lint, unit/UI tests, static analysis, and a runtime smoke test
  before calling an increment complete.
- Add tests that fail without each new behavior.

### Ask First

- Add any third-party dependency.
- Add an entitlement or request a system permission.
- Change the minimum macOS version.
- Change persistence schema or storage location after the first release.
- Add networking, cloud sync, telemetry, or an account.
- Add multi-display instances or arbitrary overlay positioning.
- Change the three-item limit or introduce progress semantics.
- Modify CI, signing, notarization, or distribution configuration.

### Never Do

- Use private Apple frameworks or undocumented API outside the existing,
  isolated, fail-closed MediaRemote XPC exception.
- Commit secrets, signing certificates, or provisioning profiles.
- Read unrelated user files or other applications' data.
- Add completion, streak, productivity-scoring, or drift-monitoring behavior
  without a new reviewed spec.
- Hide failing tests, weaken assertions, or remove tests to make a build pass.
- Add general-purpose notch widgets that are not passive, local-first,
  glanceable, non-interruptive, and tied to current or imminent context.

## Success Criteria

Checked criteria below have direct evidence or an explicitly approved physical
verification exception in
[`docs/verification/keep3-mvp.md`](../verification/keep3-mvp.md).

- [x] **SC-01:** The app builds for macOS 14+ with the documented build command
      and no third-party dependencies.
- [x] **SC-02:** The user can maintain zero to three valid items and can never
      persist more than three.
- [x] **SC-03:** Exactly one item is the designated current focus whenever
      content exists.
- [x] **SC-04:** Valid edits persist locally and survive relaunch; corrupt data
      is preserved and recovered without destructive overwrite.
- [x] **SC-05:** The top surface is hidden for zero items and displays the
      current focus after launch or interaction.
- [x] **SC-06:** Weighted rotation follows the specified two-item and three-item
      sequences and pauses/resets under the specified conditions.
- [x] **SC-07:** Hover expansion and manual browsing work without activating
      Keep3 or stealing keyboard focus.
- [x] **SC-08:** Clicking a visible item opens the editor at that item.
- [x] **SC-09:** Placement is visually correct on one notched and one
      non-notched display and remains in bounds after display changes.
- [x] **SC-10:** Closing the editor leaves the surface running; quitting removes
      it; optional launch at login restores it after login.
- [x] **SC-11:** VoiceOver, Reduce Motion, Reduce Transparency, light mode, and
      dark mode behaviors meet FR-8 and FR-9.
- [x] **SC-12:** All automated tests, formatting, linting, and static analysis
      pass.
- [x] **SC-13:** Release-build idle CPU and memory meet FR-10.
- [x] **SC-14:** The app performs no network request and requests none of the
      prohibited permissions.
- [x] **SC-15:** The full Not Doing list remains absent from the shipped MVP.

## Definition of Done

Every implementation task is complete only when:

- Its acceptance criteria and relevant success criteria pass.
- New behavior has a test that fails without the change and passes with it.
- Existing tests, formatting, linting, and static analysis pass.
- The behavior has been exercised in a running app, not only compiled.
- Error and edge paths are handled.
- No unrelated refactor, dead code, debug output, or commented-out code remains.
- User-facing behavior and durable architectural decisions are documented.
- Security, privacy, resource use, and rollback impact have been considered.
- The human has reviewed the increment before merge or distribution.

## Open Questions

None block technical planning.

- The final bundle identifier and signing team are deferred until distribution.
- Direct distribution versus the Mac App Store is deferred until after the
  personal MVP, but the MVP remains compatible with public-API and sandbox
  constraints.
- Final typography, iconography, and color tokens will be chosen during the
  functional UI prototype without changing the behaviors in this spec.
