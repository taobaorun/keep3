# Implementation Plan: Keep3 MVP

Status: Personal MVP implementation complete
Specification: [`docs/specs/keep3-mvp.md`](../docs/specs/keep3-mvp.md)

## Overview

Build Keep3 as a native macOS 14+ application that lets one user maintain at
most three priorities, designate a current focus, and keep that focus visible
in a quiet top-center surface. The implementation starts by proving the
highest-risk platform behavior—public notch geometry and a non-activating
AppKit panel—before investing in the editor, persistence, rotation, settings,
and polish.

The implementation remains deliberately small: one app target, one unit-test
target, one UI-test target, no third-party dependencies, no network, and no
task-management semantics.

## Architecture Decisions

- **Single source of truth:** A `@MainActor` `AppModel` owns the current
  `Keep3State`, selected editor item, preferences, and user-facing errors.
- **Pure domain state:** `FocusItem`, `Keep3State`, validation, and rotation
  rules are value types with no SwiftUI, AppKit, file, or timer dependencies.
- **Local persistence:** Versioned Codable JSON stores content atomically in
  Application Support; `UserDefaults` stores bounded preferences.
- **Non-activating overlay:** An AppKit panel owns window behavior while SwiftUI
  renders compact and expanded content. Hover must never steal keyboard focus.
- **Deterministic state machines:** Rotation and hover expansion use injected
  clocks/schedulers so tests do not sleep.
- **Public screen geometry:** A pure `DisplayDescriptor` abstraction converts
  documented `NSScreen` information into notched or floating-capsule frames.
- **One target until proven otherwise:** New packages or framework targets are
  deferred unless the app target becomes a measured constraint.
- **Spec-first changes:** Any change to the three-item limit, progress
  semantics, permissions, distribution constraints, or private/public API
  boundary requires updating and reapproving the spec first.

## Dependency Graph

```text
Project scaffold
├── Display geometry ──→ Non-activating panel spike
└── Domain invariants ──→ First focus-item slice
                          ├── Three-item editor ──→ Local persistence
                          └── Panel spike ──→ Weighted rotation
                                             ──→ Hover expansion
                                             ──→ Manual navigation/editor route

Panel + interaction ──→ Display/session lifecycle
Rotation + interaction + persistence ──→ Behavior preferences
Behavior preferences ──→ Appearance and motion preferences
Persistence + app lifecycle ──→ Launch at login
All user flows ──→ Accessibility ──→ UI automation
All tasks ──→ Resource, privacy, and final verification
```

## Implementation Phases

### Phase 1: Platform Foundation and Risk Spike

- [x] Task 1: Scaffold the native macOS project and quality commands.
- [x] Task 2: Model public display and notch geometry.
- [x] Task 3: Prove the non-activating top-surface panel.

#### Checkpoint: Platform Feasibility

- [x] Debug build and smoke tests pass.
- [x] The hardcoded top surface appears in bounds on the available display.
- [x] Typing in another app continues uninterrupted during hover.
- [x] Public API use is verified against Apple documentation.
- [x] Human reviews the spike before product work continues.

### Phase 2: First Usable Priority Flow

- [x] Task 4: Define and test the three-item domain invariants.
- [x] Task 5: Connect one editable focus item to the top surface.
- [x] Task 6: Complete the three-item editor, ordering, and current focus.
- [x] Task 7: Persist content and recover non-destructively.

#### Checkpoint: Durable Editor Slice

- [x] The user can create, edit, reorder, and remove up to three items.
- [x] Exactly one current focus exists whenever items exist.
- [x] The top surface updates immediately.
- [x] Content survives relaunch and corrupt data is preserved.
- [x] Unit tests and a running-app smoke test pass.

### Phase 3: Focus-Surface Behavior

- [x] Task 8: Implement deterministic weighted rotation.
- [x] Task 9: Implement delayed hover expansion without focus theft.
- [x] Task 10: Add manual browsing and editor routing.
- [x] Task 11: Handle display, Space, sleep, lock, and session changes.

#### Checkpoint: Complete Top-Surface Loop

- [x] Default two-item and three-item rotation sequences are correct.
- [x] Interaction pauses and resets to the designated current focus.
- [x] Expanded details and manual navigation work with mouse and trackpad.
- [x] Display changes reposition the panel without relaunch.
- [x] The panel remains non-activating across the tested flows.

### Phase 4: Preferences and Lifecycle

- [x] Task 12: Add persisted behavior preferences.
- [x] Task 13: Add bounded appearance and motion preferences.
- [x] Task 14: Add launch-at-login and background lifecycle behavior.

#### Checkpoint: Configurable Daily Use

- [x] Preference changes apply immediately and survive relaunch.
- [x] Reduce Motion and Reduce Transparency override custom appearance safely.
- [x] Closing the editor keeps the surface alive; quitting removes it.
- [x] Launch at login is opt-in and reports registration failures.

### Phase 5: Accessibility and Automated User Flows

- [x] Task 15: Complete accessibility semantics and keyboard operation.
- [x] Task 16: Add the UI-test target and critical end-to-end flows.

#### Checkpoint: Accessible User Experience

- [x] VoiceOver identifies visible position and current-focus status.
- [x] Explicitly activated expanded controls are keyboard-operable.
- [x] Reduced-motion and high-contrast behavior is covered by the resolved
      appearance tests; physical accessibility-mode visual review is recorded
      as an MVP verification exception.
- [x] Editor and routing UI tests pass reliably on repeat runs.

### Phase 6: Hardening and MVP Gate

- [x] Task 17: Run the resource, privacy, regression, and hardware matrix.

#### Checkpoint: MVP Complete

- [x] All 15 specification success criteria pass or have an approved exception.
- [x] Format, lint, build, tests, and static analysis pass.
- [x] Notched and non-notched runtime checks are documented.
- [x] Release-build idle CPU and memory stay within the specification, with the
      locked-session limitation documented for a pre-distribution rerun.
- [x] No network traffic, prohibited permission, or out-of-scope feature exists.
- [x] Human approval is automatic for the personal MVP; merge and distribution
      remain separate actions.

## Verification Strategy

Every task follows test-driven implementation: add a failing focused test,
implement the smallest behavior that passes it, run the focused test, then run
the project build and relevant regression tests. UI-only changes require a
running-app check in addition to compilation.

Every checkpoint applies the project Definition of Done from the specification.
Failures found at a checkpoint become explicit follow-up tasks; they are not
hidden inside an open-ended "polish" task.

## Source Verification Required Before Implementation

The implementation phase must use `source-driven-development` to verify these
against current Apple documentation before code is written:

- `NSPanel` non-activating behavior and collection behavior across Spaces.
- Public `NSScreen` safe-area and auxiliary-area APIs for notch geometry.
- Screen, session, sleep/wake, and display-change notifications.
- `SMAppService` launch-at-login lifecycle and error handling.
- Accessibility environment values and AppKit/SwiftUI interoperability.

No private framework is an acceptable fallback.

## Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Public screen APIs do not expose enough notch geometry | High | Prove geometry in Tasks 2–3; fall back to a top-center capsule that respects the safe area, not private API |
| Panel hover activates Keep3 or steals text input | High | Use a non-activating panel, test frontmost-app identity, and make this the first runtime gate |
| Space/full-screen behavior differs by macOS release | High | Isolate collection behavior in the panel controller and run a manual matrix on macOS 14 and the development OS |
| Gestures cause accidental multi-step browsing | Medium | Centralize thresholds in a deterministic interaction state machine and test burst input |
| Timers increase idle energy use | Medium | Use deadline scheduling, no polling/display link, and enforce the release-build resource gate |
| JSON corruption loses user priorities | Medium | Atomic writes, versioned envelope, preserved corrupt file, explicit recovery test |
| Settings expand the product beyond its purpose | Medium | Bounded presets only; enforce the spec's Not Doing list at every checkpoint |
| Hardware matrix is unavailable | Medium | Test geometry through injected descriptors; do not call hardware support complete until physical verification occurs |

## Parallelization

Default execution is sequential because the repository is small and several
tasks share `AppModel`, the panel controller, and the top-surface view.

After Task 7 freezes the domain and persistence contracts, these could be
worked independently in separate sessions with coordination:

- Rotation tests and display-lifecycle tests.
- Editor accessibility work and preference-store tests.
- Final documentation preparation and UI-test fixtures.

No parallel edit should touch the same shared file without first agreeing on
the interface.

## Open Questions

None block implementation planning. Bundle identifier, signing team, and
distribution channel remain deferred until the personal MVP is validated.
