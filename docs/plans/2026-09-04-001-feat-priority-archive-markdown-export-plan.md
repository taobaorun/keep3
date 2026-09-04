# Implementation Plan: Priority Archive and Markdown Export

Product Contract:
[`../specs/keep3-priority-archive-markdown-export.md`](../specs/keep3-priority-archive-markdown-export.md)

Technical Design:
[`../design-docs/2026-09-04-priority-archive-markdown-export-design.md`](../design-docs/2026-09-04-priority-archive-markdown-export-design.md)

Requirements: R1–R12

Commit policy / authority: `none`; the user authorized scoped working-tree
implementation through `ad-gallop` but did not authorize commits, pushes, a pull
request, deployment, merge, or history rewriting.

## Implementation Decisions

- Preserve the existing aggregate-state and autosave architecture; do not add a
  repository or coordinator abstraction.
- Use schema-specific v1/v2 Codable payloads and the existing atomic file
  replacement/recovery path.
- Keep undo metadata and its cancellable expiry timer runtime-only in `AppModel`,
  using the existing injectable app-timer seam for deterministic tests.
- Use one pure Markdown renderer and SwiftUI `FileDocument` integration; do not
  introduce an external library or custom save-panel controller.
- Add one History tab to the existing main-window `TabView`; do not change the
  settings or top-surface component architecture.

## Scope Deltas

None. Search, filtering, bulk operations, import, restore from History,
additional formats, and unrelated editor/settings refinements remain excluded.

## Implementation Units

### U1 — Persist crash-consistent immutable archive history

- Requirements: R1, R2, R6, R7, R12.
- Dependencies and accepted-design pointers: domain and schema decisions in
  “Proposed Structure and Responsibilities” and “Persistence, Failure,
  Compatibility, and Recovery.”
- Affected modules and mutation: add `ArchivedFocusItem`; extend `Keep3State`
  validation/mutations, including mutation-time aggregate identity and sorted
  timestamp preservation; add strict schema-v1 migration and schema-v2 load/save
  in `JSONStateStore`; update Xcode source membership and domain/persistence
  tests.
- Entry / exit conditions: enter with passing baseline unit tests; exit when
  archive/delete/undo-support mutations preserve ordering/focus/uniqueness and
  v1 fixtures migrate losslessly while v2 round-trips atomically.
- Focused verification: run `Keep3StateTests` and `JSONStateStoreTests`, including
  invalid cross-collection identity and malformed v2 recovery cases.
- Recovery checkpoint: changes are additive until the schema writer switches to
  v2; if focused checks fail, restore the last passing local file set without
  touching unrelated work.
- Complexity allowance: one explicit v1 compatibility decoder is authorized by
  R12; no generalized migration framework.

### U2 — Add application archive, delete, and one-shot undo behavior

- Requirements: R1, R3–R7, R10.
- Dependencies and accepted-design pointers: U1 domain mutations and the
  runtime-only undo lifecycle in the Technical Design.
- Affected modules and mutation: extend `AppModel` with archive time injection,
  an injected app-timer scheduler, pending undo state, archive/undo/dismiss/
  history-delete operations, selection repair, mutation invalidation, and
  user-facing errors; extend `AppModelTests` and its recording store.
- Entry / exit conditions: enter with U1 passing; exit when archive publishes and
  saves once, undo restores the same identity/index/focus once, subsequent
  mutation or dismissal invalidates undo, and history deletion cannot affect
  active focus.
- Focused verification: run `AppModelTests` with deterministic dates and manual-
  scheduler expiry/cancellation/same-item stale-callback checks—no sleeping—and
  prove expiry continues independently of editor view lifetime.
- Recovery checkpoint: keep all behavior behind new model methods so the
  pre-existing edit/add/remove paths remain independently testable.
- Complexity allowance: none.

### U3 — Produce deterministic, non-mutating Markdown documents

- Requirements: R8–R11.
- Dependencies and accepted-design pointers: U1 state shape and the Markdown
  output contract in the Technical Design.
- Affected modules and mutation: add pure `MarkdownExporter` and
  `MarkdownDocument`; add formatter fixtures for full/individual export, empty
  states, Unicode, multiline/Markdown punctuation, ordering, focus marker, and
  stable offset-bearing timestamps; add source/test target membership.
- Entry / exit conditions: enter with stable state types; exit when serialized
  output contains all and only requested data and constructing/exporting
  documents has no state mutation path.
- Focused verification: run new Markdown exporter tests and a compile check for
  the `FileDocument` adapter.
- Recovery checkpoint: the renderer is additive and can be removed without
  touching state/persistence if its focused tests fail.
- Complexity allowance: none; escaping and date formatting stay private to the
  single renderer.

### U4 — Deliver the active/archive interaction in the main window

- Requirements: R3–R11.
- Dependencies and accepted-design pointers: U2 model actions, U3 document
  output, and the History interaction states in the Technical Design.
- Affected modules and mutation: make Archive primary and permanent Delete
  secondary in `ItemEditorView`; render model-owned transient Undo and explicit
  Dismiss controls in `EditorView`;
  add `HistoryView`; add the History destination to `RootView`; update focused
  view wiring, accessibility identifiers, and Xcode source membership.
- Entry / exit conditions: enter with all non-view behavior passing; exit when
  empty/list/detail, archive, immediate undo, confirmed deletion, full export,
  individual export, cancellation, and visible export errors are represented;
  History has no edit or restore control.
- Focused verification: compile; run focused UI tests for archive/undo/dismiss,
  active-delete confirmation, history persistence, and archived-delete
  confirmation; inspect the main window at minimum size in light and dark
  appearance with VoiceOver labels available.
- Recovery checkpoint: maintain the existing editor tab and top-surface inputs;
  if History rendering fails, revert only new destination/view wiring while
  retaining passing domain behavior for repair.
- Complexity allowance: none; reuse existing `TabView`, split-view, button,
  confirmation, and content-unavailable patterns.

### U5 — Prove the integrated feature and synchronize durable documentation

- Requirements: R1–R12.
- Dependencies and accepted-design pointers: U1–U4.
- Affected modules and mutation: extend XCUITest only where stable native
  interaction evidence is required; update the focused Product Contract or
  Technical Design only if implementation uncovers a genuine authority-owned
  correction—otherwise leave accepted artifacts unchanged.
- Entry / exit conditions: enter with focused checks passing; exit when format,
  lint, the full unit/UI suite, static analysis, release build, migration fixture,
  and native smoke/interaction checks agree with the Product Contract.
- Focused verification: use the repository commands in `keep3-mvp.md`, with
  targeted reruns for any recoverable failure before repeating invalidated full
  gates.
- Recovery checkpoint: treat failures as implementation work, retain exact logs
  outside canonical documentation, and do not weaken tests or product scope.
- Complexity allowance: none.

## Verification Contract

- Required baseline: focused pre-change domain, persistence, and model tests pass
  before their owning unit is mutated.
- Required acceptance: every R1–R12 behavior has a test that would fail without
  the feature; v1 migration and v2 round-trip/corruption cases are mandatory.
- Required cross-unit checks: `xcrun swift-format lint --recursive Keep3
  Keep3Tests Keep3UITests`; full Debug test with coverage; Debug static analysis;
  Release build.
- Required Apple-platform evidence: `ad-test-xcode` reports the affected project,
  scheme, destination, focused/full commands, and results to final verification.
- Required experiential evidence: the implementation owner inspects the running
  native app for archive prominence, secondary destructive action, transient
  undo, read-only History, empty state, both export entry points, window sizing,
  keyboard reachability, accessibility labels, and light/dark legibility.
- Preferred evidence: XCUITest covers archive → History → relaunch, immediate
  undo, explicit dismissal, cancellation and confirmation for both permanent-
  delete paths, and native export cancellation. A real
  `MarkdownDocument` write test proves UTF-8 output and export-result tests cover
  success/cancel/error mapping. If native save-panel success/error automation is
  unsafe or unreliable, serializer/document tests plus manual save/error
  inspection are the authorized fallback; fidelity loss is limited to automated
  panel interaction, not Markdown contents, visible feedback, or state
  non-mutation.
- No browser evidence is required because the affected product is a native macOS
  application with no web surface.

## Risks and Recovery

- A schema-v2 defect could trigger move-aside recovery. Keep the v1 fixture and
  exact state-file backup during manual migration smoke testing; never test
  migration against the user's live Application Support file.
- Async undo expiry can race with a newer archive. Key dismissal to the archive
  identifier and make stale dismissal a no-op.
- SwiftUI file-export callback behavior can differ for cancellation. Treat user
  cancellation as non-error and verify it on the supported macOS baseline.
- Explicit Xcode project membership is an integration risk; project smoke tests
  and clean Release build must prove every new file belongs only to intended
  targets.
- Preserve all pre-existing untracked files and unrelated changes. Do not clean,
  reset, stash, or rewrite repository history.

## Definition of Done

- R1–R12 are implemented with no excluded task-management behavior.
- Active/archive invariants and v1→v2 migration are proven by focused tests.
- Full and single-entry `.md` output is deterministic, readable, complete, and
  non-mutating.
- The main window provides accessible archive, undo, History, export, and
  destructive-delete flows without changing top-surface semantics.
- Formatting, lint, full tests, static analysis, Release build, and native
  experiential checks pass or an explicitly authorized fallback is reported.
- A fresh code review finds no actionable correctness, safety, scope, or
  maintainability issue.
- The working tree remains uncommitted and unpublished unless the user grants
  separate Git authority.
