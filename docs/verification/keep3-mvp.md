# Keep3 MVP Verification

Date: 2026-07-25
Environment: MacBook Pro (Mac14,10), Apple M2 Pro, 32 GB RAM, macOS 15.7.7,
Xcode 16.4, Swift 6, arm64
Status: Implementation complete; distribution remains out of scope

> Historical baseline: this report predates Visual System 2.0 and the
> user-approved personal-build MediaRemote exception. Its “no private
> framework” findings apply to the original focus-only MVP. See
> [`keep3-visual-media.md`](keep3-visual-media.md) for the current architecture
> and verification.

## Result

The Keep3 MVP implementation satisfies the agreed product scope and automated
quality gates. It maintains at most three plain-text priorities, keeps exactly
one current focus, renders a non-activating top surface, supports weighted
rotation and intentional expansion, persists locally, and contains no progress
or task-management semantics.

The user instructed that all remaining checkpoints and non-distribution
verification exceptions are automatically approved. This approval does not
turn an unperformed physical check into a pass: the matrix below distinguishes
direct evidence from approved exceptions.

## Automated gates

| Gate | Result | Evidence |
|---|---|---|
| Format | Pass | `swift-format format` completed; subsequent lint was clean |
| Lint | Pass | `swift-format lint --recursive Keep3 Keep3Tests Keep3UITests` |
| Project | Pass | Xcode lists `Keep3`, `Keep3Tests`, and `Keep3UITests` under the shared `Keep3` scheme |
| Unit tests | Pass | 80/80 on the final formatted source |
| UI tests | Pass | 3/3 on three consecutive unlocked-session runs, with no retries |
| Full suite | Pass | 83/83: 80 unit plus 3 UI |
| Static analysis | Pass | Debug `xcodebuild analyze` |
| Release build | Pass | arm64 Release `xcodebuild build` |
| Resource gate | Pass with session-state exception | 0.000% average/max CPU and 85.66 MB average/max RSS after warm-up |
| Privacy gate | Pass | Link, entitlement, Info.plist, source, and live-socket audits |

The shared scheme runs UI and app-hosted unit targets serially, with UI first.
This avoids two test processes competing for the same application bundle. A
later UI rerun correctly could not activate the app after the workstation
entered `com.apple.loginwindow`; that locked-session environment failure is not
counted as either a product regression or an additional successful run.

### Coverage

The successful coverage run measured:

- Domain: 94.12% (208/221 lines).
- Persistence: 94.42% (203/215 lines).
- Overlay state and geometry logic: 83.73% (530/633 lines).
- Whole app target: 49.55% (1,928/3,891 lines), with SwiftUI rendering covered
  primarily through XCUITest and runtime checks rather than a numeric target.

These exceed the specification's 80% Domain/Persistence and 70% overlay-logic
expectations.

## Success criteria

| Criterion | Status | Evidence or exception |
|---|---|---|
| SC-01 | Pass | macOS 14 deployment target, Swift 6, Release build; no package or third-party dependency |
| SC-02 | Pass | Domain and UI tests enforce zero to three items and reject a fourth without mutation |
| SC-03 | Pass | Domain and UI tests enforce exactly one current focus whenever content exists |
| SC-04 | Pass | Atomic versioned JSON round trip, live relaunch, and non-destructive corrupt-file recovery |
| SC-05 | Pass | App-model/panel tests and runtime checks cover zero-item hiding and reset to current focus |
| SC-06 | Pass | Deterministic tests cover both exact weighted sequences, pausing, deadlines, and reset |
| SC-07 | Pass | Injected-clock tests plus TextEdit typing check prove hover/browsing without focus theft |
| SC-08 | Pass | Unit, keyboard runtime, and UI tests open the editor at the exact visible item |
| SC-09 | Approved physical exception | Built-in notched screen verified in the running app; non-notch geometry is covered by fixtures and a previously attached 4K screen descriptor, but that screen was not available as the primary display for final visual inspection |
| SC-10 | Approved physical exception | Close/reopen/quit behavior passes; `SMAppService` status and error paths have four tests, but a real logout/login was not forced |
| SC-11 | Approved physical exception | Accessibility tree, explicit keyboard navigation, semantic colors/fonts, and Reduce Motion/Transparency resolution pass; VoiceOver and every system appearance toggle were not physically switched |
| SC-12 | Pass | Format, lint, 83-test full suite, analysis, and Release build pass |
| SC-13 | Approved session-state exception | Numerical Release measurements meet the limits; sampling occurred while the workstation was at the login window, so the exact unlocked visible-capsule state still needs one physical rerun before distribution |
| SC-14 | Pass | No network socket, network/private framework, prohibited usage string, extra entitlement, telemetry, or third-party SDK |
| SC-15 | Pass | Source and UI review find no completion, progress, history, dates, reminders, analytics, cloud, accounts, or general notch utilities |

## Resource and privacy evidence

The Release resource test used
`KEEP3_UI_TEST_STATE_PATH=/tmp/keep3-resource-gate-state-20260725.json` and an
isolated `UserDefaults` suite, so it did not read or overwrite the user's Keep3
content or preferences. The state contained one current-focus item, which
means no rotation deadline is required. The process was warmed for two minutes
and sampled every ten seconds for five minutes.

All 30 samples reported 0.0% CPU and 87,712 KB RSS. The aggregate was 0.000%
average and maximum CPU, with 85.66 MB average and maximum RSS. This is below
the 0.5% CPU and 100 MB limits. The process was then terminated and its
isolated preference suite removed. The raw evidence is retained at
`/tmp/keep3-resource-gate.log`.

Privacy inspection found:

- The Release executable links only Apple system libraries and
  Foundation/AppKit/SwiftUI/Combine/CoreGraphics/ServiceManagement.
- No Network, CFNetwork, WebKit, MediaRemote, analytics, telemetry, advertising,
  or crash-reporting dependency or source call exists.
- The Release app has no custom entitlement and no privacy
  `UsageDescription` key.
- `lsof -i` showed no network socket for the running Release process.
- The app requests none of Accessibility, Screen Recording, Full Disk Access,
  Contacts, Calendar, Reminders, or notification access.

## Runtime and hardware matrix

| Check | Evidence | Status |
|---|---|---|
| Built-in notch placement | 1728×1117 points, 32-point safe-area top, valid auxiliary areas; the fixed 377×216 panel begins at the physical screen top and its compact active surface occupies the top 377×32 points | Pass |
| Non-notch placement | Injected small/standard/external fixtures and a live 4K display descriptor; final external screen was detached | Approved physical exception |
| Regular and full-screen Spaces | Panel remained visible in desktop and full-screen TextEdit Spaces | Pass |
| Focus theft | TextEdit stayed frontmost and received the complete test string through pointer expansion | Pass |
| Display changes | Public notification path and idempotent lifecycle coordinator covered by four tests | Pass; final physical attach/detach is an approved exception |
| Sleep/wake and session | Overlapping sleep, screen-sleep, and session state sequences covered with isolated notification centers | Pass; physical cycle is an approved exception |
| Lock screen | App hides through documented session/screen lifecycle; final test environment was observed at `com.apple.loginwindow` | Pass for lifecycle logic |
| Close/reopen/quit | Retained editor reopens; panel survives editor close and is removed on quit | Pass |
| Launch at login | Documented `SMAppService.mainApp`, system status as source of truth, four adapter tests | Approved physical logout/login exception |
| Keyboard | Explicit keyboard mode, arrows, Return, Escape, and modifier filtering | Pass |
| VoiceOver and system appearance modes | Labels/identifiers and resolved appearance tested; semantic rendering inspected | Approved physical exception |

## Notch-attached correction

Running-app feedback exposed that the first implementation recognized the
hardware notch but still treated the UI as a separate capsule below the camera
housing. Moving that capsule closer to the notch did not solve the underlying
layout problem: content intended for the notch must occupy the screen's top
band, reserve the physical obstruction in its center, and render usable wings
on both sides.

The corrected implementation:

- Keeps one transparent 377×216 panel fixed at Quartz `X = 675, Y = 0` while
  compact and expanded content animate inside it. This follows the fixed-canvas
  architecture used by Boring Notch and prevents the window itself from
  jumping during expansion.
- Makes the compact active surface exactly 377×32 points at the physical screen
  top. Its center reserves the measured 185×32 camera obstruction; two
  96-point visible wings place the focus indicator on the left and the current
  matter on the right, so no content is drawn behind the hardware.
- Expands the active surface to the full 377×216 canvas on hover or click, with
  details beginning below the 32-point camera obstruction. Moving outside
  collapses it back to the top band without moving or replacing the panel.
- Uses a top-attached pure-black shape with a one-pixel top seam on notched
  displays, without an independent panel shadow or a detached capsule outline.
- Retains the four-corner rounded, shadowed floating capsule only for displays
  whose public geometry does not identify a notch.
- Adds regressions for the exact real-screen safe-area and auxiliary-area
  measurements, central-obstruction reservation, the fixed panel canvas,
  panel interaction bounds, and current macOS window-sharing behavior. The
  final clean run passed 80 unit tests and 3 UI tests.

The current shell session does not have Screen Recording permission, so
`screencapture` omits application windows. Runtime verification instead uses
the Accessibility and Core Graphics window APIs: they confirm the compact
377×32 surface at `Y = 0`, the fixed 377×216 panel, expansion controls after
hover, collapse after pointer exit, and a single process running from the
installed application bundle.

## Rotation correction

- Runtime inspection showed that motion presets were attached only to
  transitions between compact and expanded states, so rotating item text
  changed without the selected animation.
- The compact visual payload now uses each visible item's stable identity for
  transitions while preserving the button's identity and interaction behavior.
- The default schedule is now 30 seconds for the current focus and 8 seconds for
  each secondary item.
- Rotation continues during the 140-millisecond hover-intent delay. It pauses
  only when the surface actually expands, so a quick pointer pass does not
  restart the schedule.
- Regression coverage includes transition identity, the default schedule,
  quick pointer passes, rotation during hover intent, and opening the matching
  editor item from the expanded surface.

## Surface continuity correction

Verification date: 2026-07-27

- Priorities, Media, and Calendar now render inside one persistent host. The host
  owns background, animated silhouette, clipping, interaction geometry, and
  accessibility focus transfer; component renderers no longer replace that
  outer shell at runtime.
- Trigger-specific timings replace the obsolete blanket handoff: content
  150 ms, component change 210 ms, expansion 270 ms, collapse 200 ms, and
  Reduce Motion crossfade 120 ms.
- Transition generations are latest-wins. Content revisions coalesce without
  restarting shell motion, rapid component retargets retain at most two content
  layers, preserve the in-flight visual source, and stale completions cannot
  restore an intermediate target. Same-component layout revisions animate the
  persistent shell without creating a second content layer.
- Automatic takeover and fallback defer while pointer-down, explicit keyboard
  navigation, a bounded VoiceOver action, or a component command owns the
  interaction. VoiceOver ownership is released after focus reaches the settled
  destination rather than remaining active for the lifetime of the assistive
  technology session.
- Hover intent is 140 ms, exit grace is 220 ms, a notched display keeps the
  physical top-edge corridor, and a floating surface uses the current clipped
  silhouette with 8 points of exit slop.
- Component controls and horizontal Media gestures stay inert until a handoff
  settles, while shell-level vertical navigation remains available.

| Gate | Result | Evidence |
|---|---|---|
| Strict formatting | Pass | Recursive Swift format lint and `git diff --check` report no findings |
| Focused continuity suites | Pass | 123 transition, navigation, geometry, gesture, interaction, Media, and Calendar tests passed before review; 64 focused tests passed after the review corrections |
| Full unit suite | Pass | 247 executed, 246 passed, 1 live-media probe skipped because no current system session published a snapshot, 0 failed |
| Static analysis | Pass | Debug `xcodebuild analyze` completed without findings |
| arm64 Release build | Pass | Optimized application and embedded media service built successfully |
| UI automation execution | Session-state exception | The new depth/component identifier scenario compiled, but macOS cancelled the runner before assertions because system authentication was active |
| Release runtime geometry | Pass | The isolated Release executable owned one 377×216 top panel at Quartz `X = 675, Y = 0` plus its editor window; the QA process and isolated defaults were removed afterward |
| Native motion capture | Physical exception | Both connected displays reported asleep and application windows remained excluded from screenshot capture, so normal-speed, slow-motion, and Reduce Motion visual review must be repeated in an unlocked interactive session |

## Expanded surface presentation

The fixed 216-point expanded surface reserves distinct regions for item
identity, supporting context, and controls. The title has the strongest visual
weight; details and subitems scroll inside one low-contrast content panel; and
the navigation toolbar remains above a 10-point bottom inset regardless of
content length.

The real notched-display layout resolves to a 337×75-point supporting-content
region and a 337×28-point footer. A deterministic layout test covers these
frames, while the UI test confirms that browsing and opening the selected item
remain accessible after the visual reflow.

## Distribution boundary

This report approves the personal MVP implementation, not shipping. Before
notarization, public distribution, or a merge policy decision, rerun the three
physical exceptions on an unlocked session:

1. Make a non-notched external display primary and inspect compact/expanded
   placement.
2. Toggle VoiceOver, Reduce Motion, Reduce Transparency, light, dark, increased
   contrast, and larger text.
3. Enable launch at login in a signed distribution-style build and perform one
   logout/login cycle.
4. Repeat the five-minute Release resource measurement while the compact
   top surface is visibly present.
