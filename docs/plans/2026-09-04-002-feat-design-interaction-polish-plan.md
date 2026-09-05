# Implementation Plan: Keep3 Design Interaction Polish

Product Contract: [`../specs/keep3-design-interaction-polish.md`](../specs/keep3-design-interaction-polish.md)
Technical Design: [`../design-docs/2026-09-04-design-interaction-polish-design.md`](../design-docs/2026-09-04-design-interaction-polish-design.md)
Requirements: R1-R13
Commit policy / authority: `none`; the user requested planning, not commits, push, PR, installation, or release publication

## Implementation decisions

- Work test-first at the existing pure presentation, geometry, panel, and UI-test
  seams. Do not add a second navigation state machine or persist presentation
  state.
- Extend the existing keyboard-navigation presentation with current guidance and
  render one shared status overlay. Use compact visible geometry as the floor
  only while a keyboard session is active at logical hardware level; do not
  change `SurfaceNavigationCoordinator` semantics.
- Give the keyboard status a stable accessibility identifier and aggregate label.
  It must not be a button or accept hit testing.
- Use one internal `SurfacePressButtonStyle` or equivalently narrow shared style:
  press-in uses `scaleEffect(0.97)` and opacity `0.92` for 100 milliseconds;
  release returns both values to `1` over 160 milliseconds. Use
  `.timingCurve(0.23, 1, 0.32, 1, duration: ...)` for both directions. Reduce
  Motion keeps scale at `1` and uses 120-millisecond opacity-only feedback. Do
  not apply it to native buttons outside the black top surface.
- Remove hover haptic behavior completely. Preserve navigation and track haptics
  and their existing capability/threshold policies.
- Classify priorities from normalized display content. Title-only expanded height
  requests 148 points; supporting-content height remains 216 points. A taller
  notch resolves title-only height to the maximum of 148 and the obstruction plus
  the fixed title-only body minimum. Do not add rendered-content measurement.
- Media and Calendar Settings previews remain production-rendered but become
  non-interactive and one-element accessible samples. They must not expose
  descendant buttons.
- Focus Surface preview uses two fixed local sample titles and changes identity
  once when the switch-effect preference changes. Set optional card fold to 220
  milliseconds, retain instant default and the existing 120-millisecond Reduce
  Motion crossfade. Runtime and preview folds are latest-wins: a new identity
  retargets immediately, never queues an intermediate item, and retains at most
  one outgoing and one incoming title layer.
- Keep `TabView`; use icon-plus-text tabs named `重点`, `历史`, and `设置`.
- Preserve current sidebar layouts. Add restrained visual states without changing
  selection models: hover tint, pressed tint/opacity, visible selected marker or
  outline, and native keyboard focus indication. Hover, selection, and keyboard
  focus are immediate; only pressed opacity uses 100 milliseconds. Rows never
  scale or translate.
- Keep transient business state authoritative and immediate. Archive undo uses
  its existing operation ID and eight-second timer; make-current updates the
  model/top surface before visual completion; update and error announcements are
  never delayed by animation.
- Scope R11-R13 animation to the smallest presented element. Archive banner
  insertion uses opacity plus six points of vertical offset over 180ms and exits
  with 120ms opacity. Make-current and message replacement use 160ms
  opacity/transform. These transitions use
  `.timingCurve(0.23, 1, 0.32, 1, duration: ...)`; Reduce Motion uses 120ms
  opacity only.
- Do not attach R11-R13 animation to a parent stack, ScrollView, editor detail,
  History detail, TabView, or keyboard-navigation state. Surrounding layout must
  not inherit motion.
- Introduce one internal value-only surface-frame animation policy at the current
  panel/render boundary. It returns no animation for keyboard sessions/commands,
  guidance changes, priority content-class changes, and companion-envelope-only
  changes; preserves the existing 220ms pointer/gesture level transition; and
  preserves the existing media direction/peek treatment. It owns no timer or
  navigation state.
- Mark keyboard navigation active before publishing its initial expanded logical
  level so the first click cannot start an animated frame handoff before the
  keyboard-active policy applies.
- Prefer existing files for single-use helpers. A new shared Swift source is
  allowed only for a control/row style with at least two real consumers; if one
  is added, update the Xcode project target membership in the same unit.

## Scope deltas

None. Every unit below traces directly to R1-R13 and the accepted Technical
Design. Do not absorb unrelated archive/export work, existing untracked files,
website changes, provider behavior, or broader editor redesign.

## Implementation units

### U1 — Make explicit keyboard navigation visibly persistent

- Requirements: R1, R10.
- Dependencies and accepted-design pointers: Technical Design sections
  “Keyboard navigation presentation”, “Motion recipes and transition
  provenance”, “Keyboard session”, and “Surface frame animation decision”. No
  code unit dependency.
- Affected modules and mutation:
  - `Keep3/Overlay/TopSurfacePanel.swift`: publish active guidance, refresh it
    when `PanelContent` changes, retain existing accessibility announcements,
    and expose the status to the shared root.
  - `Keep3/Overlay/TopSurfaceController.swift`: resolve compact visible geometry
    for active-keyboard/logical-hardware presentation without mutating the
    coordinator; mark keyboard navigation active before publishing the expanded
    logical level; derive the value-only frame animation category from the
    previous/next presentation.
  - `Keep3/Overlay/TopSurfaceView.swift`: render the shared, non-interactive,
    component-aware keyboard status and make notch/floating placement legible.
  - `Keep3/Overlay/MediaSurfaceView.swift` and
    `Keep3/Overlay/CalendarSurfaceView.swift`: only the minimum insets or
    presentation metadata needed to prevent status collision; no provider-owned
    keyboard state.
  - `Keep3Tests/Overlay/TopSurfacePanelTests.swift` and
    `Keep3Tests/Overlay/DisplayGeometryTests.swift`: guidance, component refresh,
    hardware visual-floor, focus, frame, hit-region, and frame-animation-policy
    coverage. Assert `.none` for activation, every keyboard arrow, guidance
    replacement, and keyboard exit; retain 220ms only for pointer/gesture level
    changes.
  - `Keep3UITests/Keep3UITests.swift`: visible status, component-specific
    directions, and Escape removal/restoration flow.
- Entry / exit conditions: enter with existing keyboard routing and focus tests
  green. Exit when Priorities, capability-varying Media, and Calendar publish
  correct visible guidance at hardware/compact/expanded logical levels, status
  never intercepts clicks, and Escape clears it immediately without changing
  existing key routing or restoration. Slow-motion inspection must show no
  surface-frame animation on activation, any keyboard command, guidance update,
  or exit.
- Focused verification:
  `xcodebuild test -project Keep3.xcodeproj -scheme Keep3 -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/DerivedData -only-testing:Keep3Tests/TopSurfacePanelTests -only-testing:Keep3Tests/DisplayGeometryTests -only-testing:Keep3Tests/SurfaceNavigationCoordinatorTests CODE_SIGNING_ALLOWED=NO`.
- Recovery checkpoint: keep coordinator semantics untouched. If the visual floor
  breaks frame ownership, revert only the U1 controller/presentation hunks and
  restore the previously passing keyboard tests; do not reset the working tree.
- Complexity allowance: one internal value-only frame-animation policy is
  authorized because the same rendered frame carries keyboard, pointer/gesture,
  content-class, envelope, and media-transient causes with different accepted
  motion. No new public API, timer, observable model, or navigation owner is
  authorized.

### U2 — Make surface feedback intentional and responsive

- Requirements: R3, R4, R10.
- Dependencies and accepted-design pointers: Technical Design sections “Press
  and row feedback”, “Motion recipes and transition provenance”, and “Haptic
  ownership”. Independent of U1 except for overlapping `TopSurfaceView` edits,
  which must preserve U1 status behavior.
- Affected modules and mutation:
  - `Keep3/App/Keep3App.swift`: remove hover-entry haptic dispatch while retaining
    hover state and gesture feedback.
  - `Keep3/Media/SurfaceHapticFeedback.swift`: remove the orphaned hover-specific
    protocol method if it has no remaining caller; retain track/navigation
    methods and feedback types.
  - `Keep3/Overlay/TopSurfaceView.swift`,
    `Keep3/Overlay/MediaSurfaceView.swift`, and
    `Keep3/Overlay/CalendarSurfaceView.swift`: add and apply the shared surface
    press style to every enabled custom pressable surface control. Apply the
    transform to the button label/control only, not the shared surface root or
    top-attached background.
  - `Keep3Tests/Media/MediaCommandCoordinatorTests.swift` and
    `Keep3Tests/Overlay/TopSurfacePanelTests.swift`: compile-time/policy coverage
    for remaining haptics and pure press-effect values, including Reduce Motion.
- Entry / exit conditions: enter after recording all current hover and gesture
  haptic call sites. Exit when pointer entry has no haptic path, each supported
  committed gesture still emits one, every custom surface button has consistent
  100ms press-in and 160ms release feedback with the exact strong ease-out curve,
  and disabled/Reduce Motion states are truthful. Pressing compact controls while
  a level transition begins must not create a second root transform or overshoot.
- Focused verification:
  `xcodebuild test -project Keep3.xcodeproj -scheme Keep3 -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/DerivedData -only-testing:Keep3Tests/MediaCommandCoordinatorTests -only-testing:Keep3Tests/SurfaceGestureRecognizerTests -only-testing:Keep3Tests/TopSurfacePanelTests CODE_SIGNING_ALLOWED=NO`.
- Recovery checkpoint: haptic and press changes remain separable. Restore the
  prior style at individual controls if a hit target regresses; never restore the
  incidental hover haptic merely to make an obsolete test pass.
- Complexity allowance: one internal shared button style is authorized by the
  multiple current surface consumers in R4; no general design-system package or
  configurable animation API is authorized.

### U3 — Size expanded priorities to their actual content class

- Requirements: R5, R10.
- Dependencies and accepted-design pointers: Technical Design sections
  “Priority height resolution”, “Priority geometry”, and “Surface frame
  animation decision”. Independent of U2; it must preserve U1's keyboard visual-
  floor and cause-aware animation policy when both affect geometry.
- Affected modules and mutation:
  - `Keep3/Overlay/TopSurfaceContent.swift`: expose a pure normalized
    title-only/supporting-content classification or equivalent resolver input.
  - `Keep3/App/Keep3App.swift`: resolve focus surface metrics for the visible
    content before presentation while retaining stable companion metrics for
    Media and Calendar envelopes.
  - `Keep3/Overlay/DisplayGeometry.swift` and
    `Keep3/Overlay/TopSurfaceView.swift`: centralize the 148/216 height tokens and
    fixed title-only body minimum; keep header, title, optional support,
    separator, and footer frames valid for floating and taller-notch geometry.
  - `Keep3/Overlay/TopSurfaceController.swift`: only if required to keep active
    and envelope frames synchronized; no post-render measurement.
  - `Keep3Tests/Overlay/TopSurfacePanelTests.swift` and
    `Keep3Tests/Overlay/DisplayGeometryTests.swift`: title-only, blank-normalized,
    details-only, subitems-only, maximum-content, notch, floating, and bounds
    coverage.
- Entry / exit conditions: enter with fixed-height geometry characterized. Exit
  when title-only uses 148 points for floating and the supported 32-point notch,
  taller notches use the obstruction-plus-body minimum, content-bearing items
  retain 216 points, browsing/editing recomputes the active frame, and panel,
  hover, gesture, and footer bounds remain synchronized.
  Transitions between the two content classes and companion-envelope-only changes
  must snap top-aligned with `.none`, including changes caused by editor typing;
  they must not inherit the 220ms level animation.
- Focused verification:
  `xcodebuild test -project Keep3.xcodeproj -scheme Keep3 -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/DerivedData -only-testing:Keep3Tests/TopSurfacePanelTests -only-testing:Keep3Tests/DisplayGeometryTests -only-testing:Keep3Tests/TopSurfaceInteractionTests CODE_SIGNING_ALLOWED=NO`.
- Recovery checkpoint: retain the existing 216-point path as the safe fallback.
  If the obstruction-plus-body resolver cannot satisfy a fixture, stop and return
  to design ownership; do not silently adjust the 148-point token, add
  GeometryReader feedback, or create a third sizing state.
- Complexity allowance: none. A pure two-class resolver and existing metrics
  path are sufficient.

### U4 — Make Settings previews honest and motion bounded

- Requirements: R2, R6, R9, R10.
- Dependencies and accepted-design pointers: Technical Design section “Honest
  previews and bounded motion” plus “Motion recipes and transition provenance”.
  No dependency on U1-U3.
- Affected modules and mutation:
  - `Keep3/Features/Settings/MediaSettingsView.swift` and
    `Keep3/Features/Settings/CalendarSettingsView.swift`: disable preview hit
    testing, collapse accessibility children into accurate preview summaries,
    and ensure no callback can reach production services.
  - `Keep3/Features/Settings/SurfacePreview.swift` and
    `Keep3/Features/Settings/FocusSurfaceSettingsView.swift`: render a faithful
    local priority sample and trigger one demonstration per switch-effect change.
  - `Keep3/Overlay/TopSurfaceContent.swift`: reduce the optional card-fold
    duration to 220 milliseconds while preserving instant and Reduce Motion
    resolution.
  - `Keep3Tests/Persistence/AppPreferencesTests.swift`: exact transition
    resolution/default coverage.
  - `Keep3UITests/Keep3UITests.swift`: previews expose descriptive elements and
    no inert descendant controls; changing the motion choice remains usable.
- Entry / exit conditions: enter with current preview callbacks and transition
  values characterized. Exit when Media/Calendar previews cannot be clicked or
  keyboard-activated, accessibility presents each as one sample, Focus preview
  demonstrates once without a timer, card fold is 220ms, and Reduce Motion uses
  the existing 120ms crossfade. Two or more item changes inside one 220ms window
  must settle on the latest identity with at most one outgoing and one incoming
  title layer, no queue, and no stale replay.
- Focused verification:
  `xcodebuild test -project Keep3.xcodeproj -scheme Keep3 -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/DerivedData -only-testing:Keep3Tests/AppPreferencesTests -only-testing:Keep3Tests/MediaSurfacePresentationTests -only-testing:Keep3Tests/CalendarSurfacePresentationTests CODE_SIGNING_ALLOWED=NO`.
- Recovery checkpoint: keep preview changes local to Settings. If faithful reuse
  of a production surface introduces interactive descendants, restore the visual
  rendering and wrap it in a stronger non-interactive accessibility boundary;
  do not add fake service implementations.
- Complexity allowance: none. Local preview state and existing production views
  are sufficient; no preview framework or timer service is authorized.

### U5 — Align main-window navigation and selectable rows

- Requirements: R7, R8, R10.
- Dependencies and accepted-design pointers: Technical Design sections “Press
  and row feedback”, “Motion recipes and transition provenance”, and “Main-
  window navigation”. No dependency on U1-U4.
- Affected modules and mutation:
  - `Keep3/App/RootView.swift`: change only tab presentation to icon-plus-text
    `重点`, `历史`, and `设置`, preserving tags and routing.
  - `Keep3/Features/Editor/EditorView.swift` and
    `Keep3/Features/History/HistoryView.swift`: add restrained hover, pressed,
    selected, and focus treatments without altering item selection or archive
    state.
  - A narrowly shared internal row-style source and
    `Keep3.xcodeproj/project.pbxproj` only if two consumers cannot share the
    treatment cleanly inside existing files.
  - `Keep3Tests/App/EditorWindowControllerTests.swift` and
    `Keep3UITests/Keep3UITests.swift`: destination labels, Command-comma,
    selection, current-focus distinction, History selection, and minimum-window
    layout coverage.
- Entry / exit conditions: enter with existing destination and archive UI tests
  green. Exit when all three destinations are visibly and accessibly labeled,
  row hover/press/selection/focus are distinguishable without layout shift or
  color-only meaning, and routing/data behavior is unchanged. Hover, selection,
  and keyboard focus remain immediate; press opacity is 100ms; rows never scale
  or translate.
- Focused verification:
  `xcodebuild test -project Keep3.xcodeproj -scheme Keep3 -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/DerivedData -only-testing:Keep3Tests/EditorWindowControllerTests -only-testing:Keep3Tests/AppModelTests CODE_SIGNING_ALLOWED=NO`.
- Recovery checkpoint: tab labels and row visuals remain separate hunks. If a
  custom focus treatment conflicts with native focus behavior, retain the native
  focus ring and remove only the redundant decoration; do not replace `TabView`,
  editor selection, or History selection.
- Complexity allowance: one narrowly shared row treatment is authorized by the
  two current sidebar consumers. No general component library is authorized.

### U6 — Bridge transient editor, archive, update, and error states

- Requirements: R11, R12, R13, R10.
- Dependencies and accepted-design pointers: Technical Design sections “Editor
  and status transitions”, “Motion recipes and transition provenance”, and
  “Transient editor and status state”. Independent of U1-U5; if U5 introduces a
  shared row style, U6 must not broaden it into a general animation system.
- Affected modules and mutation:
  - `Keep3/Features/Editor/EditorView.swift`: extract or locally contain the
    identity-keyed archive undo banner; add its bounded asymmetric transition;
    keep outgoing stale operations non-interactive; apply scoped opacity
    presentation to editor and persistence messages.
  - `Keep3/Features/Editor/ItemEditorView.swift`: keep the make-current action and
    current-state label in one stable header slot, animate only a same-item
    `isCurrentFocus` state change, and avoid animation when a different item view
    is constructed or focused through navigation.
  - `Keep3/Features/History/HistoryView.swift`: apply scoped opacity presentation
    to export and History error messages without animating the archive list,
    detail snapshot, or surrounding controls.
  - `Keep3/Features/Settings/UpdateSettingsView.swift`: key the status text's
    `.contentTransition(.opacity)` to the existing update status while retaining
    the current immediate accessibility announcement. Optional editor,
    persistence, History, and export messages use `.transition(.opacity)` rather
    than the always-present content-transition path.
  - A narrowly shared internal transient-motion token/helper and
    `Keep3.xcodeproj/project.pbxproj` only if the four consumers cannot reuse
    exact duration/curve values without duplication. It must not own state,
    timers, side effects, or public API.
  - `Keep3Tests/App/AppModelTests.swift` and
    `Keep3Tests/Updates/SparkleUpdateControllerTests.swift`: preserve archive
    replacement/expiry, make-current, error clearing, and update state ordering.
  - `Keep3UITests/Keep3UITests.swift`: archive banner availability and removal,
    replacement token safety, stable make-current header geometry, transient
    message visibility, and immediate accessibility output.
- Entry / exit conditions: enter with existing archive/undo, make-current,
  export-failure, persistence-failure, and update-state tests characterized.
  Exit when all underlying states change immediately, archive Undo is actionable
  from the first rendered frame, old operations cannot affect replacements,
  make-current confirms within 160ms without header reflow, status/error text
  bridges only opacity with the exact strong ease-out recipe, and Reduce Motion
  removes spatial movement. Parent stack/scroll layout and accessibility output
  remain immediate and unanimated.
- Focused verification:
  `xcodebuild test -project Keep3.xcodeproj -scheme Keep3 -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/DerivedData -only-testing:Keep3Tests/AppModelTests -only-testing:Keep3Tests/SparkleUpdateControllerTests CODE_SIGNING_ALLOWED=NO`, followed on an unlocked desktop by targeted archive, make-current, update-fixture, and export-failure `Keep3UITests`.
- Recovery checkpoint: keep all model/controller code behaviorally unchanged.
  If a visual transition delays semantics or leaks to parent layout, remove only
  the presentation modifier/transition and restore the immediate baseline; never
  change the eight-second timer, operation guards, update state machine, or error
  production to accommodate animation.
- Complexity allowance: one internal value-only motion recipe may be shared by
  the current consumers. A coordinator, observable animation model, timer,
  generalized design system, or new public abstraction is not authorized.

## Verification contract

### Baseline and focused evidence

- Required before mutation: record `git status --short`, preserve all unrelated
  tracked/untracked content, and run the first unit's focused tests. A dirty tree
  is not a reason to absorb or delete unrelated work.
- Required per unit: run the focused command named by that unit and inspect its
  diff against R-IDs before starting the next unit.
- Required formatting after Swift edits:
  `xcrun swift-format lint --strict --recursive Keep3 Keep3Tests Keep3UITests`.

### Cross-unit engineering evidence

- Required full unit suite:
  `xcodebuild test -project Keep3.xcodeproj -scheme Keep3 -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/DerivedData -only-testing:Keep3Tests CODE_SIGNING_ALLOWED=NO`.
- Required static analysis:
  `xcodebuild analyze -project Keep3.xcodeproj -scheme Keep3 -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO`.
- Required optimized build:
  `xcodebuild build -project Keep3.xcodeproj -scheme Keep3 -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO`.
- Required project membership check when a Swift file is added: the focused/full
  builds compile that source in the Keep3 target, and `Keep3Tests/ProjectSmokeTests`
  passes.

### Native UI and experiential evidence

- Required signed UI run on an unlocked desktop, without
  `CODE_SIGNING_ALLOWED=NO`, covering:
  - component-specific keyboard status at logical hardware, compact, and
    expanded levels, including capability-limited Media;
  - immediate, non-animated keyboard activation, every arrow-driven depth or
    component change, guidance replacement, Escape removal, and previous-
    application restoration;
  - non-interactive Media/Calendar previews and consistent destination labels;
  - priority and History selection at the minimum 720×520 window;
  - archive undo appearance, immediate action, dismissal, replacement, and
    expiry; stable make-current action/state geometry; and update/export/error
    message appearance and clearing.
- Required human review on notched and floating placement where available:
  - quick pointer pass produces no haptic;
  - committed navigation and track gestures still produce exactly one haptic;
  - all custom surface buttons provide immediate pressed feedback;
  - press-in is visibly faster than release without scaling the top-attached
    surface background or double-transforming a simultaneous level change;
  - long titles do not collide with keyboard guidance;
  - title-only 148-point and supporting 216-point priority surfaces remain
    top-anchored and visually balanced, and content-class/envelope changes do not
    inherit level motion;
  - card fold completes crisply at 220ms, demonstrates once in Settings, and
    becomes a short crossfade under Reduce Motion; rapid repeated changes settle
    latest-wins without stacking or replaying titles;
  - archive banner enters within 180ms and exits within 120ms without stale hit
    targets, make-current confirms within 160ms without reflow, and transient
    status/error text does not animate surrounding controls;
  - R11-R13 use opacity-only presentation under Reduce Motion and remain
    immediately available to assistive technology;
  - sidebar hover, selection, and keyboard focus remain immediate; press opacity
    stays at 100ms and rows never scale or translate.
- Preferred evidence: screenshots for each component/level and slow-motion
  capture for the card fold, pressed state, archive banner, make-current slot,
  and transient status replacement.
- Fallback for an unavailable signed UI runner: focused unit tests plus source-
  level accessibility inspection may keep engineering work moving, but they do
  not satisfy R1, R2, R4, R7, R8, or R10-R13 acceptance. Authority to waive
  those user-visible gates is not present.
- Fallback when only one display placement is physically available: repository
  geometry tests are accepted for the unavailable placement, with the fidelity
  loss recorded. They do not replace the physical trackpad haptic check.

## Risks and recovery

- Shared keyboard presentation and panel geometry overlap with mature focus and
  media code. Preserve one state owner and add characterization tests before
  changing frame resolution.
- Compact guidance can collide with long titles or the media playback control.
  Prefer bounded glyph treatment and provider-specific insets inside the shared
  overlay contract; never hide an enabled control or primary title.
- Dynamic item edits may switch 148↔216 while the pointer is inside. The existing
  controller must update the active frame and tracking region atomically; if it
  cannot, retain 216 during the current expanded interaction and apply the new
  class on the next presentation rather than creating a layout feedback loop.
- The current root view animates every `surfaceFrameInPanel` change. Replace that
  unconditional attachment with the accepted value-only cause policy; otherwise
  keyboard activation and content/envelope changes will violate the motion
  contract. Tests must prove pointer/gesture and media motion remain intact.
- UI tests may be skipped when the desktop cannot grant key-window ownership.
  Record that environment limitation; do not convert a skip into a pass or
  manipulate the user's installed `/Applications/Keep3.app` instance.
- SwiftUI removal transitions may keep outgoing pixels alive briefly. Archive
  action closures must retain operation-ID guards and outgoing content must not
  remain hit-testable; slow-motion and replacement tests must cover this path.
- Broad `.animation(value:)` placement can animate stack reflow unintentionally.
  R11-R13 modifiers stay on identity-keyed leaf containers and must be inspected
  with slow motion before final acceptance.
- Rapid item changes can leave overlapping transition layers. Characterize the
  current `.id`/transition behavior first, then enforce latest-wins with no timer
  or queue; do not solve it by delaying rotation or input.
- No data migration or irreversible action exists. Recovery is unit-local source
  reversion through explicit patches. Do not use `git reset --hard`, broad
  checkout, or deletion of unrelated files.

## Definition of done

- R1-R13 each have passing focused engineering evidence and the required human
  evidence named above.
- Keyboard mode is visible throughout the session, including logical hardware
  level, is fully non-animated throughout keyboard operation, and retains
  existing focus/arrow/Escape semantics.
- Media and Calendar previews contain no inert interactive affordance; Focus
  motion preview demonstrates exactly once per selection change.
- Incidental hover produces no haptic, committed supported gestures retain one,
  and every custom surface control has the exact 100ms press-in/160ms release
  feedback without double transforms.
- Title-only and supporting priority surfaces use their bounded heights without
  clipping, hit-region drift, loss of top anchoring, or inherited frame animation
  during content/envelope changes.
- Main-window destinations and sidebar row states are consistent and accessible.
- Card-fold changes are 220ms, interruptible, and latest-wins with no queued or
  stale title layer.
- Archive Undo appears and exits with the bounded asymmetric treatment while
  retaining immediate actions, timer semantics, and replacement safety.
- Make-current confirmation uses a stable header slot and does not animate item
  selection or keyboard navigation.
- Update and error feedback uses scoped opacity transitions without delaying
  accessibility output or animating surrounding functional content; always-
  present status replacement and conditional message insertion use their
  distinct accepted SwiftUI transition mechanisms.
- Strict formatting, focused tests, full unit tests, static analysis, optimized
  arm64 Release build, signed UI flows, and required experiential checks pass or
  carry only the explicitly permitted placement fallback.
- No product data, provider, XPC, permission, archive/export, website, or release
  behavior changes; unrelated working-tree content remains untouched.
- No commit, push, PR, installation, or publication is performed without a new
  explicit authorization.
