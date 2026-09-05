# Technical Design: Keep3 Design Interaction Polish

Design identity: `keep3-design-interaction-polish/2026-09-04`
Product Contract: [`../specs/keep3-design-interaction-polish.md`](../specs/keep3-design-interaction-polish.md)
Requirements covered: R1-R13
Authority: confirmed Product Contract plus its explicit delegated engineering defaults

## Current behavior, constraints, and invariants

- `SurfaceNavigationCoordinator` remains the sole owner of selected component,
  logical surface level, hover preview, and navigation generation. This change
  does not add another navigation state machine.
- `TopSurfaceController` resolves screen geometry, creates or updates the one
  `TopSurfacePanel`, and keeps its visible surface frame synchronized with the
  panel hit region. Resizing must continue to update the rendered frame and
  tracking area together.
- `TopSurfaceKeyboardNavigationPresentation` already publishes whether an
  explicit keyboard session is active. Component-specific direction guidance is
  used for the accessibility announcement and is intentionally not rendered as
  surface chrome.
- Pointer entry currently produces an immediate hover haptic independently of
  the deliberate gesture threshold. Gesture haptics are already emitted once
  when a supported gesture crosses its lock threshold.
- Priorities use a fixed 216-point expanded height. The expanded layout reserves
  the full supporting-content region even when an item has only a title.
- Media and Calendar Settings previews render production surface views with
  no-op callbacks, leaving visually active controls inert.
- Custom surface buttons and custom sidebar rows use plain button styles without
  a shared pressed-state treatment.
- The archive undo token and eight-second expiry are already owned by
  `AppModel`, but `EditorView` presents and removes the corresponding banner
  without a transition.
- `ItemEditorView` conditionally replaces `设为当前重点` with the current-state
  label in a variable-width header region, with no bounded visual bridge.
- Update status text and editor, persistence, History, and export messages are
  published immediately by their existing owners but swap or appear without a
  presentation-level transition.
- Persistent data, media and Calendar provider boundaries, permissions, XPC,
  component ordering, gesture meanings, and the 220-millisecond shared level
  transition are unchanged.

## Decision summary and active design dimensions

1. Keyboard mode remains owned by the existing panel presentation. It keeps a
   component-aware accessibility announcement but renders no arrows, Return,
   Escape, keyboard badge, or provider-specific visual guidance. When the logical
   level is hardware-only during an active keyboard session, rendering may use
   the compact interaction envelope so keyboard routing remains available; the
   logical level and arrow-key semantics do not change.
2. Surface controls share one internal pressed-state style. It changes only
   transform and opacity and substitutes opacity-only feedback under Reduce
   Motion.
3. Pointer hover produces no haptic. Existing committed gesture haptics remain
   unchanged; no replacement hover timer or haptic state is introduced.
4. Priority expansion uses two stable content classes: title-only and supporting
   content. Title-only requests a 148-point expanded height; any non-empty details
   or subitems use the existing 216-point height. Geometry is resolved before
   panel presentation; SwiftUI does not feed measured size back into the AppKit
   panel.
5. Media and Calendar previews are non-interactive visual samples with one
   aggregate accessibility description. Focus Surface reuses the real priority
   title transition in a local, side-effect-free sample and demonstrates a
   newly selected motion option once.
6. Main-window tabs use consistent icon-plus-text labels. Priority and History
   rows retain their current layout while gaining explicit hover, pressed,
   selected, and keyboard-focus treatments.
7. Archive undo, current-focus confirmation, and transient status/error feedback
   remain owned by their existing models. View-local transition wrappers animate
   only transform and opacity, never delay state publication or animate parent
   layout, and retain immediate accessibility output.
8. Surface frame animation becomes cause-aware. Existing pointer/gesture level
   motion and media transient motion remain available, while keyboard sessions,
   keyboard commands, accessibility-guidance replacement, focus content-class
   changes, and companion-envelope recalculation update without animation.

The active design dimensions are user interaction state, internal presentation
and geometry flow, accessibility, and motion performance. No durable data,
external dependency, trust-boundary, migration, or distributed-system design is
activated.

## Proposed structure and responsibilities

### Keyboard navigation presentation

- Keep `TopSurfaceKeyboardNavigationPresentation` as the MainActor-owned source
  of keyboard-session presentation state. Extend its published value to include
  the current `TopSurfaceKeyboardNavigationGuidance` alongside `isActive`.
- `TopSurfacePanel` derives guidance from its current `PanelContent` both when a
  session begins and whenever content changes while the session remains active.
  Media guidance continues to announce only supported previous/next actions.
- `TopSurfaceRootView` renders no keyboard-status overlay. Keyboard state remains
  available only to motion suppression, focus handling, and accessibility
  announcements; providers reserve no visual inset for it.
- While keyboard navigation is active and the logical level is `.hardware`,
  `TopSurfaceController` resolves the visible layout with the compact envelope.
  Exiting the session immediately returns geometry to the logical presentation
  chosen by the existing dismissal path.

This keeps the keyboard lifecycle in the panel, preserves the navigation
coordinator's state contract, and avoids three provider-owned session flags.

### Press and row feedback

- Add one internal surface button style driven by SwiftUI's pressed
  configuration. Press-in uses scale `0.97` plus opacity `0.92` over 100
  milliseconds; release returns to scale `1` and opacity `1` over 160
  milliseconds. Both use the strong ease-out curve defined below. Reduce Motion
  removes scale and retains a 120-millisecond opacity change.
- Apply it only to custom black-surface controls currently using plain styles.
  Native Settings and editor controls keep platform-standard styles.
- Priority and History rows use a small shared visual-state model or equivalent
  local styling for rest, hover, press, selection, focus, and disabled states.
  Selection adds a shape/marker or border so it is not communicated by tint
  alone. These row states do not animate layout or text. Hover, selection, and
  keyboard focus update immediately; only pressed opacity transitions for 100
  milliseconds. Rows do not scale, spring, or translate.

### Motion recipes and transition provenance

- New entering, exiting, press, and state-confirmation motion uses SwiftUI
  `.timingCurve(0.23, 1, 0.32, 1, duration: ...)`. Do not substitute built-in
  `.easeIn`, `.easeInOut`, or an unowned curve for these new transitions.
- The optional card fold uses the existing fold curve
  `.timingCurve(0.33, 0, 0.2, 1, duration: 0.22)`. The existing shared surface
  level transition remains 220 milliseconds and is not retuned by this task.
- Exact new recipes are:

  | Interaction | Normal motion | Exit/release | Reduce Motion |
  | --- | --- | --- | --- |
  | Surface button press | scale `1 → 0.97`, opacity `1 → 0.92`, 100ms | scale/opacity to `1`, 160ms | opacity only, 120ms |
  | Archive undo banner | opacity `0 → 1`, vertical offset `-6 → 0`, 180ms | opacity `1 → 0`, 120ms | opacity only, 120ms |
  | Make-current confirmation | opacity plus scale `0.97 → 1`, 160ms | outgoing opacity, 100ms | opacity only, 120ms |
  | Status replacement | always-present or optional insertion opacity, 160ms | optional-message opacity, 120ms | opacity only, 120ms |
  | Sidebar hover/press | hover/selection/focus immediate; pressed opacity 100ms | opacity 100ms | opacity only, 100ms |

- Add one internal value-only frame-animation policy at the existing panel/render
  boundary. It compares the current rendered presentation with the next one and
  returns an animation category, not a new user state:
  - `.none` for keyboard-session activation/deactivation, every keyboard command,
    guidance/capability text replacement, focus title-only/supporting-content
    changes, and companion-envelope-only changes;
  - the existing 220-millisecond level animation only for pointer- or gesture-
    initiated logical depth/component changes;
  - the existing media transient treatment for track direction and confirmed
    metadata peek.
- Explicit surface activation marks keyboard navigation active before publishing
  the expanded logical level. Therefore both the initial expansion and later
  keyboard depth/component changes resolve to `.none`; there is no one-frame
  animated handoff before the keyboard-active flag arrives.
- Apply the resolved animation only to the leaf surface position/transform that
  owns the visual change. Do not attach a broad animation to the root panel frame,
  Settings container, editor stack, History stack, or navigation container.

### Haptic ownership

- Remove hover-entry haptic dispatch from `handleSurfaceHoverChange`.
- Keep hover state publication, gesture recognition, supported-capability
  checks, and `performSurfaceGestureFeedback` unchanged.
- Keep the haptic protocol method only if another current test or runtime caller
  still needs it; otherwise remove the now-orphaned hover-specific method and its
  tests as cleanup caused directly by R3. Do not alter track/navigation haptic
  types.

### Priority height resolution

- Add a pure content classification derived from normalized display details and
  subitems: `.titleOnly` when both are empty, otherwise `.supportingContent`.
- Resolve focus metrics before calling `showOnPrimaryDisplay`. The supporting
  class retains 216 points. The title-only class requests 148 points, derived
  from the existing header/title/separator/footer geometry and the supported
  32-point notch fixture. `DisplayGeometry` may raise that request only to the
  minimum required by a taller physical obstruction plus the same fixed body;
  this is hardware geometry resolution, not rendered-content measurement.
- Keep width resolution, top anchoring, continuous surface shape, shared media
  envelope, and display clamping in `DisplayGeometry`. Do not introduce a
  GeometryReader/preference feedback loop or content-driven NSPanel resizing
  after presentation.
- Recompute metrics when the visible priority changes or its normalized content
  changes. Panel frame, rendered surface frame, hover tracking region, and
  gesture generation continue to update through the existing controller path.
  Title-only/supporting-content changes and their shared-envelope effects are
  top-anchored and non-animated, including when caused by editor typing.

### Honest previews and bounded motion

- Media and Calendar previews continue to reuse production rendering for visual
  fidelity but disable hit testing and collapse their accessibility descendants
  into one descriptive preview element. They never dispatch media, request
  Calendar permission, enter keyboard navigation, or imply a working button.
- Replace the hand-drawn Focus Surface sample with a non-interactive production
  priority surface sample or an equivalent shared title-slot renderer so the
  configured transition is the same one used at runtime.
- A local preview revision alternates between two fixed sample titles only when
  the user changes the switch-effect selection. There is no timer and no loop.
- Reduce the optional card-fold duration from 580 milliseconds to exactly 220
  milliseconds. Keep `.instant` as the persisted default and the existing short
  Reduce Motion crossfade.
- Card-fold rendering is latest-wins. A new item identity arriving during the
  220-millisecond fold retargets from the currently presented visual state to the
  newest item without queuing intermediate identities. At most one outgoing and
  one incoming title layer may remain; stale outgoing layers are removed and
  cannot reappear after the newest item settles.

### Main-window navigation

- Keep the root `TabView` and `MainWindowDestination` routing. Change only tab
  labels to consistent icon-plus-text `重点`, `历史`, and `设置` presentations.
- Keep Command-comma routing, window reuse, editor selection, archive behavior,
  and History selection semantics unchanged.

### Editor and status transitions

- Keep `AppModel.pendingArchiveUndo`, its operation identity, replacement rules,
  and eight-second timer authoritative. `EditorView` renders the banner in an
  identity-keyed transition container: insertion uses opacity plus at most six
  points of vertical offset; undo, explicit dismissal, expiry, and replacement
  use a faster opacity exit. The outgoing visual cannot perform an action after
  its operation identity is no longer current.
- Keep the current-focus update synchronous. A fixed-size header slot in
  `ItemEditorView` owns the two presentation states: the actionable
  `设为当前重点` control and the non-actionable `当前重点` label. Only an
  `isCurrentFocus` change within the same selected item animates; constructing a
  new editor for a different selected item does not animate keyboard or selection
  navigation.
- Keep update and error values owned by `SparkleUpdateController`, `AppModel`,
  and `HistoryView`. The always-present update status uses
  `.contentTransition(.opacity)` keyed by its status identity. Conditional
  editor, persistence, History, and export messages use `.transition(.opacity)`
  keyed by message identity for insertion/removal. Both attach animation only to
  the smallest text or label container; parent stacks, controls, and scroll
  regions update with animation disabled.
- Use exactly 180 milliseconds for archive-banner insertion, 120 milliseconds
  for its exit, and 160 milliseconds for current-focus and status replacement.
  Reduce Motion removes archive offset and current-focus scaling while retaining
  a 120-millisecond opacity bridge. No blur, bounce, stagger, timer-driven loop,
  or layout-property animation is introduced.

## Interfaces and data/control flow

### Keyboard session

1. The user explicitly activates a surface.
2. Existing application code expands the logical surface and asks
   `TopSurfaceController` to begin keyboard navigation.
3. The controller captures the prior application as today; the panel publishes
   active state and accessibility guidance derived from current panel content.
4. Provider changes update the same accessibility guidance without restarting
   the session; the shared root renders no keyboard legend.
5. If navigation reaches logical hardware level, controller geometry uses the
   compact visible envelope while the coordinator remains at hardware level.
6. Escape follows the existing dismissal and application-restoration path; the
   active state and any compact-envelope override clear immediately.

No new public API is introduced. Any added presentation value is internal and
immutable outside its MainActor owner.

### Priority geometry

1. The visible `TopSurfaceContent` normalizes details and subitems as today.
2. A pure resolver maps the content to title-only or supporting-content metrics.
3. `TopSurfaceController` and `DisplayGeometry` compute the panel and surface
   frames before the panel update.
4. `TopSurfacePanel` updates its frame, hosted layout, hover frame, and content
   through the existing atomic presentation path.

The resolver never reads or writes persisted state and never measures a rendered
view asynchronously.

### Transient editor and status state

1. Existing model/controller state changes and accessibility announcements occur
   immediately, exactly as before.
2. SwiftUI receives the new undo identity, focus boolean, status value, or
   message value and updates functional semantics in the same render pass.
3. A view-local transition bridges only the old and new pixels. Outgoing undo
  content is non-interactive and remains protected by the existing operation-ID
  guard.
4. A replacement archive operation uses its new operation ID as a new visual
   identity; it does not extend or reuse the old operation's timer or actions.
5. Reduce Motion selects the opacity-only presentation recipe without changing
  state, timing, focus, or accessibility behavior.

### Surface frame animation decision

1. The panel/render boundary compares previous and next logical component,
   logical level, keyboard-active state, focus content class, envelope metrics,
   and media transient identity using values it already renders.
2. Keyboard active in either previous or next presentation forces `.none` for
   surface frame motion. Guidance still updates immediately.
3. A focus content-class or companion-envelope-only change forces `.none` and
   preserves the top screen edge exactly.
4. A pointer/gesture logical level change keeps the existing 220-millisecond
   surface transition. A media track-direction/peek change keeps its existing
   transient treatment.
5. The policy does not queue transitions, own a timer, mutate navigation state,
   or infer product behavior. Reduce Motion always resolves spatial motion to
   `.none` regardless of cause.

### Settings preview

Preference changes still update the observed preferences object. Visual previews
rerender from those values. Only the Focus Surface switch-effect change mutates
local preview revision/title state, producing one bounded demonstration; no
preview callback reaches application services.

## State, failure, compatibility, migration, security, and operations

- All new presentation state is transient, MainActor-confined, and rebuilt from
  existing component payloads or local preview state.
- A component or capability change during keyboard navigation replaces the
  accessibility announcement guidance atomically. No visual glyph layer exists.
- If content becomes unavailable, existing component fallback decides the next
  component; the keyboard overlay follows that result and does not select a
  component itself.
- Title-only geometry resolves to `max(148, obstruction height + fixed title-only
  body minimum)` on a notched display and 148 points on floating placement,
  subject to existing display clamping. Supporting content remains 216 points.
  Clipping is not an accepted recovery path.
- Existing UserDefaults and JSON formats are unchanged. Previously stored motion
  preferences remain valid; only the runtime duration of the optional treatment
  changes.
- Preview changes cannot invoke XPC, media commands, EventKit authorization,
  pasteboard actions, application activation, or persistent writes beyond the
  preference control the user explicitly changed.
- Archive, undo, make-current, update, persistence, and export state machines are
  unchanged. Presentation animation never owns a timer, retries a mutation, or
  keeps stale actions alive.
- Scoped animation must be attached to the identity/value being presented, not a
  parent feature container. This prevents unrelated controls and stack geometry
  from inheriting the transition.
- Surface frame animation is similarly scoped by cause. A generic
  `.animation(..., value: surfaceFrameInPanel)` without the resolved policy is
  not allowed because unrelated geometry changes would inherit level motion.
- No security or privacy boundary changes. No rollout flag or migration is
  required. Reverting the implementation restores previous presentation
  behavior without data repair.

## Alternatives and rejected approaches

- **Provider-specific keyboard indicators:** rejected because keyboard-session
  ownership is shared and provider-local state could become stale during
  component switching.
- **Leave hardware geometry invisible during keyboard mode:** rejected because
  it violates R1 whenever an arrow moves the logical level to hardware on a
  notched display.
- **Change Up or Escape semantics to keep the surface visible:** rejected because
  it would alter the existing navigation contract rather than only its
  presentation.
- **Measure expanded SwiftUI content and feed size back into AppKit:** rejected
  because it creates an asynchronous layout/panel feedback loop and unstable hit
  regions for a problem satisfied by two bounded content classes.
- **Make Media and Calendar previews fully interactive:** rejected as the
  default because faithful isolated playback, permissions, and component depth
  would add scope without improving the configured production behavior.
- **Replace editor sidebars with new native List architectures:** rejected
  because consistent row feedback can be added without changing selection or
  window layout.
- **Add a global animation coordinator or animation state to `AppModel`:**
  rejected because R11-R13 are projections of existing state and can be rendered
  locally without coupling business lifetime to visual lifetime.
- **Animate whole editor/History/Settings containers:** rejected because it would
  move functional controls and data for a small message change, violating the
  motion-restraint contract.
- **Keep one unconditional surface-frame animation:** rejected because keyboard
  activation and content/envelope recalculation share the same frame value but
  have different frequency and purpose contracts.
- **Queue every card-fold identity:** rejected because automatic and manual
  changes may overlap; latest-wins is faster, bounded, and cannot replay stale
  priorities.

## Risks and verification approach

- **Keyboard overlay collision:** compact notch wings and Media controls have the
  least space. Verify all components, capability combinations, title lengths,
  increased contrast, and hardware/compact/expanded logical levels with snapshot
  or frame-level assertions followed by native screenshots.
- **Panel/hit-region drift:** test that title-only/supporting height changes and
  the keyboard hardware-envelope override keep `renderedSurfaceFrameInPanel`,
  hover tracking, and screen-space gesture bounds synchronized.
- **Double animation:** verify preference demonstration changes only the sample
  title identity and does not animate Settings layout. Inspect the transition in
  slow motion. Trigger a second and third title change before the first fold
  settles and verify latest-wins with no stacked or replayed title.
- **False controls in previews:** UI accessibility inspection must find one
  descriptive preview element and no enabled descendant buttons.
- **Focus regression:** existing key-window, first-responder, modified-key pass-
  through, Escape restoration, and action-handoff tests remain authoritative.
- **Interaction quality:** final human evidence is required on an unlocked Mac
  with a pointer and physical trackpad; automated tests cannot approve press
  feel, haptic absence, compact readability, or animation quality.
- **Stale undo affordance:** replace or expire an undo operation during slow-
  motion inspection and prove any outgoing banner is non-interactive and cannot
  affect the replacement operation.
- **Implicit layout animation:** use instrumentation or slow-motion inspection to
  confirm R11-R13 animate only their content transform/opacity; surrounding
  fields, buttons, rows, and scroll regions must snap to their new layout without
  inherited motion.
- **Transition-cause leakage:** activate keyboard navigation, issue every arrow,
  edit an item across the title-only/supporting-content boundary, and change a
  companion envelope while recording slow motion. None may inherit the 220ms
  pointer/gesture level animation; genuine pointer/gesture level changes and
  media transient feedback must retain their existing motion.
- **Accessibility timing:** verify new labels and existing Sparkle announcements
  are available immediately rather than after visual completion.

## Scope deltas and specialist evidence

No scope delta is required. The design uses only the Product Contract's explicit
requirements and delegated defaults. The preceding `emil-design-eng` review and
`find-animation-opportunities` sweep are the specialist basis for the motion,
feedback, and preview constraints already promoted into that contract.

No ADR is created: all decisions are task-local, reversible, and unsurprising
once the Product Contract is read.

## Open technical decisions

None. Exact colors, border weights, and local helper names remain reversible
implementation choices inside the delegated boundaries. Expanded-height rules,
motion curves, durations, asymmetry, interruption, Reduce Motion, and transition-
cause decisions required for implementation are fixed above.
