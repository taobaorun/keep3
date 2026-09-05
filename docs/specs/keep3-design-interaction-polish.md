# Product Contract: Keep3 Design Interaction Polish

Authority: User requests on 2026-09-04 and 2026-09-05 to align every finding from the `emil-design-eng` review and merge the surviving `find-animation-opportunities` candidates into the same scope
Product Context: [`docs/specs/keep3-mvp.md`](keep3-mvp.md)

## Actor and observable outcome

The actor is a Keep3 user who glances at and directly manipulates the top
surface, or manages priorities and preferences in the main window.

After this change, Keep3 retains its quiet black event-surface identity while
making every interaction honest and legible: keyboard capture is visibly
active, incidental hover does not create physical feedback, clickable controls
respond to press, previews do not pretend to work, sparse priority content does
not produce an oversized empty surface, repeated motion stays fast, and the
main-window navigation and selectable rows use consistent affordances.
Occasional state changes in the editor, History, and Settings also receive
short, restrained visual bridges so confirmation and failure feedback does not
appear or disappear abruptly.

## Requirements

- **R1 — Visible keyboard-navigation state.** When explicit surface activation
  starts keyboard navigation, a sighted user can see that the mode is active,
  which directions/actions are currently available, and how to exit. The
  indication remains present for the keyboard-navigation session and disappears
  immediately on exit. Starting or operating this keyboard-driven mode does not
  add a decorative entrance animation. Acceptance: activate Priorities, Media,
  and Calendar keyboard navigation and observe component-appropriate guidance;
  press Escape and observe its immediate removal and restoration of the prior
  application. Owner/method: engineering UI coverage plus human keyboard-flow
  verification. Provenance: user acceptance of the full 2026-09-04 design
  interaction review; existing keyboard-navigation product behavior.

- **R2 — Honest Settings previews.** A preview must either perform the action it
  visually advertises in an isolated preview state or be visibly and
  semantically non-interactive. Media and Calendar previews must not expose
  buttons that hover or accept clicks while their callbacks do nothing.
  Acceptance: pointer, click, keyboard, and accessibility inspection find no
  inert interactive affordance in either preview. Owner/method: engineering UI
  test and accessibility inspection. Provenance: user acceptance of the full
  2026-09-04 design interaction review.

- **R3 — Intentional haptic feedback.** Merely entering the surface with the
  pointer produces no haptic. A haptic may occur only after the interaction has
  crossed an existing intentional threshold or committed a meaningful state
  change; gesture threshold feedback remains unchanged. Acceptance: a quick
  pointer pass produces zero haptics, while a committed supported navigation or
  track gesture still produces exactly one. Owner/method: engineering
  haptic-recorder tests plus human trackpad verification. Provenance: user
  acceptance of the full 2026-09-04 design interaction review and Keep3's
  quiet-by-default product principle.

- **R4 — Unified press feedback on custom surface controls.** Every custom
  pressable control on the top surface provides immediate, subtle pressed-state
  feedback without changing layout or delaying its action. This includes the
  compact surface, item title, previous/next controls, Keep3 control, artwork,
  and media actions. Acceptance: each enabled control visibly responds for the
  duration of a pointer press; disabled controls do not imply availability; no
  control shifts neighboring content. Owner/method: human pointer-flow review
  supported by shared-style unit or snapshot coverage. Provenance: user
  acceptance of the full 2026-09-04 design interaction review.

- **R5 — Content-proportionate priority expansion.** Expanded Priorities uses a
  compact height when the visible item has only a title and grows only when
  details or subitems need the additional space. The footer, title, notch
  attachment, hit region, and display bounds remain correct at every resulting
  height. Acceptance: title-only, details-only, subitems-only, and maximum-
  content fixtures show no unexplained empty field, clipping, overlap, or
  off-screen surface. Owner/method: engineering layout tests and screenshot
  review on notched and floating placements. Provenance: user acceptance of the
  full 2026-09-04 design interaction review.

- **R6 — Bounded repeated motion.** Priority item changes that may occur during
  automatic rotation complete within 240 milliseconds and never block input.
  The default remains instant. Any optional decorative card treatment remains
  interruptible in perception, preserves the title slot's anchor, and becomes a
  short crossfade under Reduce Motion. Acceptance: automatic and manual item
  changes meet the duration bound, remain usable during rapid changes, and
  retain the existing Reduce Motion behavior. Owner/method: engineering
  transition tests plus slow-motion human review. Provenance: user acceptance
  of the full 2026-09-04 design interaction review.

- **R7 — Consistent main-window destinations.** The three primary destinations
  use consistent icon-plus-text navigation labels with the visible titles
  `重点`, `历史`, and `设置`. Existing destination routing, Command-comma
  behavior, and single-window behavior remain unchanged. Acceptance: all three
  labels are visible and accessible, and each opens the same destination as
  before. Owner/method: engineering UI tests. Provenance: user acceptance of the
  full 2026-09-04 design interaction review.

- **R8 — Legible selectable-row states.** Priority and History sidebar rows
  distinguish resting, hover, pressed, selected, focused, and disabled states
  without relying only on color. Feedback stays restrained because these are
  frequent interactions. Acceptance: mouse and keyboard passes can identify
  the clickable row and current selection; state changes do not reflow text or
  reduce title readability. Owner/method: human interaction review plus
  accessibility inspection. Provenance: user acceptance of the full 2026-09-04
  design interaction review.

- **R9 — Motion preference can be previewed.** Selecting the optional priority
  item-switch treatment demonstrates that treatment once inside Settings. It
  does not loop, block interaction, or animate unrelated controls. Under Reduce
  Motion it demonstrates the corresponding short crossfade. Acceptance: switch
  between `即时` and `卡片折叠` and observe one faithful, bounded demonstration
  for the selected mode. Owner/method: engineering state test plus human visual
  review. Provenance: user acceptance of the full 2026-09-04 design interaction
  review.

- **R10 — Existing accessibility and focus contracts remain intact.** All
  affected controls retain meaningful accessibility labels and keyboard access;
  Reduce Motion, Reduce Transparency, increased contrast, and differentiation
  without color continue to work. Hover alone never steals application focus,
  and only the existing explicit keyboard-navigation activation may capture
  keys. Acceptance: affected accessibility tests pass and a human pass confirms
  focus behavior before activation, during navigation, and after Escape.
  Owner/method: engineering regression suite plus human accessibility/focus
  verification. Provenance: existing Keep3 Product Contract and user acceptance
  of the full 2026-09-04 design interaction review.

- **R11 — Archive undo feedback has a bounded entrance and exit.** When an
  archive operation creates the existing undo opportunity, its banner appears
  with a short opacity-and-position transition and exits faster when undone,
  dismissed, or expired. Motion never delays availability of Undo, changes the
  existing eight-second lifetime, or blocks another archive operation. Under
  Reduce Motion, the banner uses opacity only. Acceptance: archive an item and
  observe the banner become actionable immediately, then verify Undo, explicit
  dismissal, expiry, and replacement all remove it without stale content or
  delayed state. Owner/method: engineering state/UI coverage plus human visual
  review. Provenance: user request on 2026-09-05 to align the surviving
  `find-animation-opportunities` candidates with the existing contract.

- **R12 — Making an item current visibly confirms the state change.** Activating
  `设为当前重点` transitions the same fixed control region into the non-actionable
  `当前重点` state without reflowing the header or delaying the underlying focus
  update. The visual bridge completes within 160 milliseconds; Reduce Motion
  uses a short opacity-only crossfade. Acceptance: make each non-current item
  current and observe immediate model/top-surface change, stable header geometry,
  one bounded confirmation transition, and no animation when merely navigating
  with the keyboard. Owner/method: engineering UI/state coverage plus human
  visual review. Provenance: user request on 2026-09-05 to align the surviving
  `find-animation-opportunities` candidates with the existing contract.

- **R13 — Transient status and error messages change legibly.** Update status,
  editor/persistence errors, and History export/error feedback use a restrained
  opacity bridge when their text appears, changes, or clears. The bridge
  completes within 160 milliseconds, never animates the surrounding functional
  content, and does not delay or replace existing accessibility announcements.
  Acceptance: exercise checking, success/failure, appearance, replacement, and
  clearing paths and observe readable messages, no animated movement of
  surrounding controls, and immediate assistive-technology output; Reduce
  Motion retains a short opacity transition. Owner/method: engineering state/UI
  coverage plus accessibility and human visual inspection. Provenance: user
  request on 2026-09-05 to align the surviving `find-animation-opportunities`
  candidates with the existing contract.

## In scope

- The Priorities, Media, and Calendar top-surface presentations and their shared
  pressed, hover, keyboard-active, motion, shape, and haptic behavior.
- The Focus Surface, Media, and Calendar Settings previews.
- Priority expanded-height behavior for title-only through maximum-content
  items on notched and floating displays.
- Main-window destination labels and the selectable rows in active priorities
  and History.
- The existing archive-undo banner, current-focus action/state region, update
  status, editor/persistence errors, and History export/error feedback, limited
  to the state transitions defined by R11-R13.
- Focused automated coverage and human verification needed to prove R1-R13.

## Out of scope

- A visual rebrand, new app icon, new color system, or replacement of the
  signature black top surface.
- New surface components, configurable component ordering, new gesture
  mappings, or new Calendar actions.
- Changes to media discovery, MediaRemote/XPC safety, Calendar data access,
  persistence formats, archive/export semantics, update delivery, or the
  marketing website. R11 and R13 change only presentation of existing archive,
  export, and update feedback.
- A general redesign of the editor, History, or Settings information
  architecture beyond the labels, row states, and previews named above.
- New sounds, notifications, celebratory motion, analytics, or onboarding.
- Animated keyboard-navigation activation or keyboard-command feedback, animated
  main-window destination changes, animated History snapshot replacement,
  decorative Media progress motion, or a hold-to-confirm delete interaction.

## Constraints and confirmed decisions

- All findings from the 2026-09-04 `emil-design-eng` review and all surviving
  candidates from the 2026-09-05 `find-animation-opportunities` sweep are
  included; none are deferred from this contract.
- Keep3 remains quiet, native, glanceable, top-aligned, and non-overshooting.
- The existing 220-millisecond shared level transition remains the baseline.
- Keyboard-initiated surface actions do not receive decorative motion.
- The priority switch default remains `即时`; optional repeated motion is capped
  at 240 milliseconds.
- Incidental hover never produces a haptic. Existing one-haptic-per-committed-
  gesture behavior remains authoritative.
- Reduce Motion removes positional and scaling movement while preserving useful
  opacity/state feedback. Reduce Transparency and contrast accommodations remain
  authoritative.
- New R11-R13 motion is reserved for occasional state indication or prevention
  of abrupt feedback changes. Functional data, high-frequency navigation, and
  keyboard-triggered navigation remain immediate.
- R11-R13 animate only transform and opacity, stay at or below 180 milliseconds
  on entry and 160 milliseconds for state replacement, and use a faster exit
  where applicable.
- Existing unrelated working-tree content is not part of this task.

## Delegated engineering defaults and boundaries

- Engineering may choose the exact keyboard-active visual treatment, provided
  it stays inside the current surface, lists only available actions, is visible
  for the whole session, and does not animate on keyboard input.
- The default implementation for Media and Calendar Settings previews is a
  clearly non-interactive visual preview. Engineering may instead implement a
  complete isolated preview interaction only if it adds no production side
  effect, permission request, source command, or material scope expansion.
- Press feedback may use scale in the 0.95-0.98 range with a 100-160ms
  responsive curve; Reduce Motion must substitute non-spatial feedback.
- Engineering may choose the exact compact and expanded priority heights after
  measuring real content, within current safe-area and display-bound contracts.
- Hover/selected colors, border weights, and easing curves are delegated within
  the existing black-surface and native-main-window visual language.
- Archive-banner entrance may translate by at most 6 points and must remain
  actionable from its first rendered frame; its exit may be shorter than its
  entrance.
- Engineering may choose the exact opacity curve and fixed control-region width
  for R12-R13 within the stated duration, layout-stability, accessibility, and
  Reduce Motion boundaries. Blur, bounce, continuous animation, and layout-
  property animation are not delegated.
- Engineering may select the minimum test seams necessary to observe timing,
  haptic count, focus, layout, and accessibility without changing public product
  APIs.

## Open product decisions

None.
