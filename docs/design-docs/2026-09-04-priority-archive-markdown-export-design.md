# Technical Design: Priority Archive and Markdown Export

Design identity: priority-archive-markdown-export-v3

Product Contract:
[`../specs/keep3-priority-archive-markdown-export.md`](../specs/keep3-priority-archive-markdown-export.md)

Requirements covered: R1–R12

Authority: The confirmed Product Contract and its delegated engineering
defaults. This autonomous Gallop run accepts the design because no material
choice below exceeds those defaults.

## Current Behavior, Constraints, and Invariants

`Keep3State` currently owns only an ordered array of zero to three `FocusItem`
values plus one current-focus identifier. `AppModel` applies synchronous domain
mutations, publishes the whole state to the top surface, and autosaves through
`StateStore`. `JSONStateStore` atomically replaces one schema-v1 JSON file and
preserves unsupported or corrupt files instead of overwriting them.

The editor is one SwiftUI tab containing the active-item list and editable
detail. Deletion is the only removal path. The app has no document or file-export
seam. The Xcode project uses explicit file references, so every new source and
test file must be added to the correct target.

The design preserves these invariants:

- no more than three active items;
- exactly one current focus when active items exist, otherwise none;
- archive entries never participate in rotation or top-surface rendering;
- all user content stays local and no new entitlement, permission, network
  access, or third-party dependency is introduced;
- a failed persistence write follows the existing non-destructive in-memory
  error behavior.

## Decision Summary

1. Extend the single aggregate state with immutable archive snapshots and keep
   archive/removal/focus changes inside one synchronous mutation.
2. Upgrade the on-disk state from schema v1 to schema v2 with an explicit v1
   decoder that supplies an empty archive.
3. Keep the one available undo token and its expiry timer in `AppModel`. Neither
   is persisted; expiry is independent of which main-window tab is visible.
4. Add History as a third main-window tab with a newest-first list and read-only
   detail; keep archived content out of the active editor and top surface.
5. Render Markdown with a pure Foundation formatter and hand it to SwiftUI's
   native file exporter as UTF-8 `.md` content.

The activated design concerns are durable data/migration, transient lifecycle,
user interaction states, and local file output.

## Proposed Structure and Responsibilities

### Domain state

Add an immutable `ArchivedFocusItem` value containing:

- `item: FocusItem`, preserving the original item identifier and content;
- `archivedAt: Date`;
- `id`, derived from `item.id` for stable SwiftUI and deletion identity.

Extend `Keep3State` with `archivedItems`, stored by descending archive timestamp.
State validation requires unique identifiers across both active and archived
collections. Every domain mutation preserves both aggregate invariants: adding
rejects an identifier already present in History, and archiving inserts at the
timestamp-sorted position even if the system clock moves backwards. Domain
mutations own:

- archiving one active item into the front of History while applying the
  existing focus fallback;
- permanently deleting one archived entry;
- restoring a just-archived entry only when given the runtime undo payload,
  reinserting it at its former position and restoring its former focus status.

The restore mutation is an internal correction seam for `AppModel`; no History
UI calls it and it is not a general product capability.

### Application state and transient undo

`AppModel` captures a runtime-only undo payload before archiving: an operation-
unique identifier, archived entry identity, former active index, and whether the
item was current focus. The operation identifier is distinct from the item ID so
an overdue callback from an earlier archive cannot dismiss a later archive of
the same restored item. After the archive state publishes successfully in memory,
the model exposes one pending undo action for presentation.

Another content mutation invalidates the payload. Selection and tab navigation
do not. Undo removes the matching archive entry and restores the same `FocusItem`
atomically; a stale or missing token is a no-op with an explanatory editor
message. Relaunching cannot restore an archived entry because the token is not
persisted.

The model schedules expiry for eight seconds through the existing injectable
`AppTimerScheduling` seam. A stale callback carries the operation identifier and
cannot dismiss a newer undo token. Another content mutation, explicit dismissal,
or successful undo cancels the active timer. This keeps expiry running when the
editor tab disappears and lets tests advance a manual scheduler without sleeps.

The editor renders the pending token and exposes both Undo and an accessible
explicit Dismiss control. Both send the exact operation identifier to model-owned
actions; the view does not own or restart the lifetime.

### Main-window History interaction

Add `history` to `MainWindowDestination` and a third `TabView` destination.
`HistoryView` contains:

- an empty state when no archive exists;
- a newest-first selectable list showing title and localized archive time;
- a read-only detail showing title, description, subitems, and archive time;
- a confirmed permanent-delete action in the selected detail;
- a complete-export action available even for an empty state;
- a selected-entry export action when a history entry is selected.

Archive becomes the visually primary removal action in `ItemEditorView`.
Permanent deletion moves into a secondary menu and retains a destructive
confirmation. After archiving, active selection follows the same fallback as
focus; the undo banner remains available in the editor until used, dismissed,
expired, or invalidated.

### Markdown rendering and file output

A stateless `MarkdownExporter` produces:

- a complete document with a `Keep3` title, an active-priorities section in
  active order, an unambiguous current-focus marker, and a History section in
  archive order;
- a single-entry document with the archived title/content and archive time.

Optional empty descriptions and subitem sections are omitted, while empty
active/history collections receive readable empty-state text. Every ASCII
punctuation character that can participate in CommonMark/GFM syntax or character
references is backslash-escaped in user-authored text, including ampersands and
tildes, so rendered output displays the original text. Line breaks and subitem
order are preserved. Archive dates use a stable, locale-independent
representation containing date, time, and numeric time-zone offset.

`MarkdownDocument` adapts the rendered UTF-8 string to SwiftUI `FileDocument`.
The view supplies a suggested filename and invokes the standard macOS file
exporter. Cancellation is silent; other failures produce a visible local error.
No export path calls an `AppModel` mutation.

## Interfaces and Data Flow

Archive flow:

1. `ItemEditorView` sends the selected active identifier to `AppModel`.
2. `AppModel` captures undo metadata and asks `Keep3State` to archive at the
   injected/current date.
3. `Keep3State` inserts the immutable snapshot, removes the active item, and
   repairs focus as one value mutation.
4. `AppModel.publish` updates the editor/top surface and atomically saves schema
   v2; the pending undo banner appears and the model starts its expiry timer.
5. Undo performs the inverse aggregate mutation once; expiry/dismissal cancels
   timer ownership and removes only the runtime token.

Export flow:

1. History asks the pure formatter for complete state or one archive entry.
2. The view wraps the string in `MarkdownDocument` and presents the native save
   destination chooser.
3. SwiftUI writes the file; completion clears export state or exposes a local
   error without touching `Keep3State`.

## Persistence, Failure, Compatibility, and Recovery

Schema v2 stores `items`, `currentFocusID`, and `archivedItems` in the existing
single JSON file. Loading first decodes only `schemaVersion`, then selects a
strict version-specific payload:

- v1: validate active items/current focus and construct state with an empty
  archive;
- v2: decode and validate active plus archived content;
- any other version or invalid content: use the existing move-aside recovery
  behavior.

Every successful save writes schema v2 atomically. This makes removal plus
archive insertion one crash-consistent replacement. A pre-feature version that
opens v2 treats it as unsupported and preserves the file under the existing
recovery policy instead of silently discarding archive fields. Downgrading is
therefore not a supported editing path, but the v2 file remains recoverable.

Archive, undo, and permanent deletion report domain or persistence errors through
existing editor/persistence messages. A file-export error affects only the
proposed output file and does not change application state. The app creates no
background work, telemetry, logs containing user content, or new network flow.

## Alternatives and Rejected Approaches

- **A second archive file:** rejected because active removal and archive
  insertion could not be atomically committed across two files, creating a
  crash window for loss or duplication.
- **An optional archive field while retaining schema v1:** rejected because an
  older Keep3 would ignore the field and erase history on its next save.
- **Persistent or multi-level undo:** rejected because it becomes the prohibited
  History restore capability and complicates migration/state semantics.
- **A new task-management model:** rejected because archived snapshots require
  no status, completion, edit, tags, search, or scheduling concepts.
- **Custom AppKit save-panel coordination:** rejected because SwiftUI's native
  file exporter already supplies the required user-chosen local destination and
  error callback.

## Risks and Verification Approach

- Migration loss is guarded by checked-in v1 fixtures and v2 round-trip/corrupt
  data tests.
- Focus or ordering regressions are guarded by domain tests for current,
  secondary, and final-item archive cases plus undo reinsertion.
- Stale undo and tab-independent expiry are guarded by manual-scheduler identity,
  cancellation, same-item rearchive, and expiry tests.
- Markdown corruption is guarded by exact formatter fixtures including Unicode,
  entities, GFM punctuation, multiline text, empty sections, ordering, and
  time-zone output.
- Accidental task-management expansion is guarded by UI inspection confirming
  read-only History with no restore/edit/status controls.
- Active and archived permanent deletion are guarded by native UI journeys for
  cancellation, confirmation, and resulting persisted state.
- File-system side effects are guarded by a real `MarkdownDocument` UTF-8 write
  test, an XCUITest cancellation journey, export-result error mapping checks, and
  state equality assertions. If forcing a native save-panel write error is unsafe
  or unreliable, the Plan's manual fallback remains required for that branch.
- Full format, lint, unit/UI tests, static analysis, release build, and native
  runtime inspection remain final gates.

## Scope Deltas and Specialist Evidence

No product-scope delta is introduced. The only change to the base MVP boundary
is the focused immutable archive already authorized by the Product Contract.
No destructive migration, external protocol, or new trust boundary warrants an
independent document review. No separate ADR is needed because the schema and
single-file decision is fully owned by this focused design.

## Open Technical Decisions

None.
