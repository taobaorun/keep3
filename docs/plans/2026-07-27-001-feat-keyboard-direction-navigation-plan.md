---
title: Four-Direction Keyboard Surface Navigation - Plan
type: feat
date: 2026-07-27
artifact_contract: ce-unified-plan/v1
artifact_readiness: implementation-ready
product_contract_source: ce-plan-bootstrap
execution: code
---

# Four-Direction Keyboard Surface Navigation - Plan

## Goal Capsule

- **Objective:** Make Keep3's explicitly activated keyboard mode reliably support the applicable Up, Down, Left, and Right actions on the top surface, with clear entry and exit feedback.
- **Authority:** The user's four-direction request takes precedence, followed by the existing non-interruptive focus contract in `docs/specs/keep3-mvp.md` and current surface-navigation semantics.
- **Execution profile:** Tighten and prove the existing keyboard path instead of introducing a second navigation system.
- **Stop conditions:** Stop if completion would require globally intercepting unmodified arrow keys, stealing focus on hover, or changing the established gesture direction meanings.
- **Tail ownership:** The invoking LFG pipeline owns review, shipping, and CI after implementation.

## Product Contract

### Summary

Keep3 will recognize all four direction keys after explicit activation and expose the applicable action for the current component and surface level.

### Problem Frame

The repository already parses all four arrow keys and routes vertical keys through the gesture recognizer, but the behavior is only partially protected by tests and the activation affordances do not consistently explain the available directions. This leaves a user-visible gap: four-direction support exists in pieces without a reliable interaction contract proving that each arrow reaches the intended navigation seam exactly once.

### Requirements

- R1. Explicit keyboard mode consumes each applicable unmodified arrow key and routes it exactly once only while the top-surface panel is key and its event view owns first-responder focus.
- R2. Left and Right reuse the selected component's established horizontal behavior: priorities browse visible items and Media requests supported previous or next tracks; components without a horizontal target leave state unchanged.
- R3. Up and Down reuse the established vertical surface contract: they advance or retreat depth until expanded, then navigate components, except expanded Media Up returns to compact Media.
- R4. A direction with no applicable target leaves state unchanged without crashing, dispatching an unrelated action, or leaking a duplicate event.
- R5. Arrow keys with meaningful modifiers remain available to macOS and the active application.
- R6. Hover, presentation refreshes, and component takeovers do not activate Keep3 or disable an already explicit keyboard session.
- R7. Starting keyboard mode provides visible and accessibility feedback; ending it with Escape or session teardown restores the previously active non-Keep3 application when it is still available.
- R8. Each priority, Media, and Calendar affordance describes only the keys available in that component and state, with Return and Escape named only where they have an action.
- R9. Automated coverage protects the U1 routing seams; per the user's
  2026-07-27 acceptance decision, U2 visual, accessibility, and physical
  keyboard behavior are handed off with an explicit human-verification flow
  instead of new UI automation.

### Scope Boundaries

- Keyboard support is limited to the top surface; editor and Settings navigation are unchanged.
- This work does not add a global hotkey or a global unmodified-arrow monitor.
- Existing gesture meanings, component availability rules, media capability checks, and automatic selection policy remain unchanged.

## Planning Contract

### Key Technical Decisions

- KTD1. **Extend the existing command and navigation pipeline.** `TopSurfaceKeyboardCommand`, `TopSurfaceEventView`, `SurfaceGestureRecognizer`, and `SurfaceNavigationCoordinator` remain the owners of parsing, event routing, direction semantics, and state publication. Implements R1-R6.
- KTD2. **Keep keyboard ownership explicitly activated and session-scoped.** The panel remains non-activating until requested, handles keys only while it owns key-window and first-responder status, and ends the session by restoring the previously active application when possible. Implements R1, R5-R7.
- KTD3. **Render state-aware guidance instead of a universal key claim.** Priorities, Media, and Calendar name only actions that can execute in their current state; unavailable horizontal actions remain safe no-ops rather than being advertised. Implements R2-R4, R7-R8.
- KTD4. **Prove behavior at the routing seams and hand off the visible flow.**
  Parser tests cover key codes and modifiers, route-level tests cover focus
  ownership, single dispatch, restoration, and vertical event parity, while a
  documented human flow covers activation through visible outcome. Implements
  R1-R9.

### Assumptions

- “支持键盘的上下左右切换” refers to the top surface rather than the editor or Settings window.
- “Switching” reuses the direction semantics already approved in `docs/specs/keep3-mvp.md`: horizontal content navigation where supported and vertical depth/component navigation. The runtime baseline must identify any mismatch before implementation.
- Explicit keyboard activation is acceptable because silently capturing arrow keys from another application would contradict Keep3's existing focus contract.

### Sources and Research

- `Keep3/Overlay/TopSurfacePanel.swift` already owns arrow-key parsing, explicit keyboard focus, event monitoring, and vertical synthetic gesture events.
- `Keep3/App/Keep3App.swift` composes component-specific horizontal actions and the shared vertical gesture path.
- `Keep3/Overlay/SurfaceGestureRecognizer.swift` and `Keep3/Overlay/SurfaceNavigationCoordinator.swift` define the canonical direction semantics and atomic state changes.
- `Keep3Tests/Overlay/TopSurfacePanelTests.swift`, `Keep3Tests/Overlay/SurfaceGestureRecognizerTests.swift`, and `Keep3Tests/Overlay/SurfaceNavigationCoordinatorTests.swift` provide the test patterns to extend.
- `docs/plans/2026-07-26-001-feat-event-surface-interactions-plan.md` and `docs/specs/keep3-mvp.md` establish explicit activation and focus preservation as existing product constraints.
- No `docs/solutions/` corpus or root `CONCEPTS.md` exists, so there are no institutional learnings to carry forward.

## Implementation Units

### U1. Make four-direction event routing explicit and testable

- **Goal:** Ensure each arrow key is owned and dispatched exactly once during an explicit keyboard session.
- **Requirements:** R1-R7, R9; KTD1-KTD2, KTD4.
- **Dependencies:** None.
- **Files:**
  - `Keep3/Overlay/TopSurfacePanel.swift`
  - `Keep3/Overlay/TopSurfaceController.swift`
  - `Keep3/App/Keep3App.swift`
  - `Keep3Tests/Overlay/TopSurfacePanelTests.swift`
  - `Keep3Tests/Overlay/SurfaceGestureRecognizerTests.swift`
  - `Keep3Tests/Overlay/SurfaceNavigationCoordinatorTests.swift`
- **Approach:**
  1. Record the current runtime outcome for Left, Right, Up, and Down after explicit activation before changing code.
  2. Add route-level characterization coverage around the panel/event-view seam and turn every observed failure into a red test.
  3. Keep unmodified key parsing separate from component semantics and reuse the shared scroll/gesture path for vertical commands.
  4. Require both key-window and first-responder ownership before the local monitor consumes an event.
  5. Capture the previously active non-Keep3 application at session start, restore it on Escape or teardown when still available, and clear the captured reference.
- **Execution note:** If the runtime baseline shows all four direction routes already work, target the proven activation, ownership, feedback, and restoration gaps rather than shipping a test-only no-op.
- **Patterns to follow:** Existing command parsing in `TopSurfaceKeyboardCommand`, generation-safe gesture recognition, and callback recorders used by overlay tests.
- **Test scenarios:**
  - With keyboard mode enabled, Left and Right each invoke the horizontal navigation callback once with the matching direction.
  - With keyboard mode enabled, Up and Down each emit one complete vertical gesture and resolve to the established surface intent.
  - Repeated events remain one action per key-down event and do not double-dispatch through both the local monitor and responder path.
  - Command-, Option-, Control-, or Shift-modified arrows are not consumed by Keep3.
  - With keyboard mode disabled, the panel remains non-key and does not intercept navigation.
  - With the keyboard-session flag still enabled but key-window or first-responder ownership lost, arrows pass through without invoking a surface callback.
  - Escape and non-interactive teardown restore the captured application once when it is still running, while a missing or terminated application fails safely.
  - A direction without an available destination leaves the current state intact.
- **Verification:** Focused panel, gesture-recognizer, and navigation-coordinator tests pass with exact callback and state assertions.

### U2. Expose and verify the four-direction user flow

- **Goal:** Make the supported keys discoverable on every expanded component and prove a user can activate keyboard mode and switch content.
- **Requirements:** R6-R9; KTD2-KTD4.
- **Dependencies:** U1.
- **Files:**
  - `Keep3/Overlay/TopSurfaceView.swift`
  - `Keep3/Overlay/MediaSurfaceView.swift`
  - `Keep3/Overlay/CalendarSurfaceView.swift`
  - `Keep3/Overlay/TopSurfacePanel.swift`
  - `Keep3/Overlay/TopSurfaceController.swift`
  - `Keep3UITests/Keep3UITests.swift`
  - `docs/verification/keep3-event-surface.md`
- **Approach:**
  1. Publish keyboard-session state to the rendered surface so successful activation is visible and announced.
  2. Align component-specific visible and accessibility guidance: priorities name item browsing and Return, Media names supported track actions, and Calendar omits unavailable horizontal actions.
  3. Provide a clear Escape/exit announcement before focus returns to the previously active application.
  4. Preserve stable accessibility identifiers so the activation controls are
     easy to locate during human acceptance.
  5. Record a component-by-component human verification flow without claiming
     automated or physical-keyboard evidence that was not requested.
- **Patterns to follow:** Existing stable accessibility identifiers and the
  verification matrix in `docs/verification/keep3-event-surface.md`.
- **Test scenarios:**
  - The priorities affordance announces item browsing, vertical surface movement, Return, and Escape without requiring the user to infer them from an icon.
  - Media advertises Left and Right only when the matching track capability exists; Calendar does not advertise unavailable horizontal or Return actions.
  - Successful activation presents a visible active state and one accessibility announcement.
  - A human acceptance pass activates keyboard mode, presses Right, and observes
    the next priority before Return opens that same item.
  - Escape ends keyboard navigation, announces exit once, leaves the surface compact, and restores the application that was active before Keep3.
  - Pointer hover without explicit activation continues to leave typing in the frontmost application uninterrupted.
- **Verification:** The verification document provides a complete human flow
  and distinguishes the completed U1 regression evidence from the pending
  physical acceptance check.

## Verification Contract

| Gate | Units | Command | Done signal |
|---|---|---|---|
| Focused keyboard and navigation tests | U1 | `xcodebuild test -project Keep3.xcodeproj -scheme Keep3 -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/DerivedData -only-testing:Keep3Tests/TopSurfacePanelTests -only-testing:Keep3Tests/SurfaceGestureRecognizerTests -only-testing:Keep3Tests/SurfaceNavigationCoordinatorTests CODE_SIGNING_ALLOWED=NO` | All arrow, modifier, single-dispatch, and state assertions pass |
| Human keyboard flow | U2 | Follow `docs/verification/keep3-event-surface.md` | The user confirms component-specific guidance, activation feedback, four-direction behavior, Escape, and focus restoration |

## Definition of Done

- All four unmodified arrow keys route exactly once after explicit keyboard activation.
- Horizontal and vertical commands preserve the existing component, depth, availability, and media-capability contracts.
- Modified arrows and ordinary hover do not steal input from another application.
- Priority, Media, and Calendar activation affordances describe their applicable keyboard behavior accessibly.
- U1 focused regression tests pass; U2 is ready for the user-requested human
  acceptance flow.
- Verification evidence records the pending physical acceptance check honestly.
- Experimental or abandoned keyboard-routing code is removed from the final diff.
