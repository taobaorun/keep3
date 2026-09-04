# Product Contract: Priority Archive and Markdown Export

Status: Aligned on 2026-09-04; implementation not yet planned or started.

Authority: The user's archive and export request plus the decisions confirmed in
the 2026-09-04 product-grill conversation.

Product context: [`keep3-mvp.md`](keep3-mvp.md). This focused contract
supersedes that document's general exclusion of history only for the immutable,
local priority archive defined below. All other task-management exclusions and
existing priority invariants remain in force.

## Actor and Observable Outcome

A Keep3 user can remove a priority that no longer belongs among the current
three without losing what they wrote. The removed priority becomes a local,
read-only historical snapshot that can be reviewed or exported as Markdown,
while the active surface remains limited to at most three current priorities.

Archiving communicates only that an item no longer deserves current attention.
It does not mean completed, deferred, successful, or abandoned.

## Requirements

- **R1 — Archive an active priority.** The user can archive any current
  priority. A successful archive removes it from the active set and adds one
  historical snapshot; acceptance: archive each possible active position and
  observe exactly one matching history entry and no remaining active copy;
  owner/method: engineering, domain tests plus UI test; provenance: user request
  and confirmed grill decision.
- **R2 — Preserve the archived snapshot.** A history entry preserves the
  priority's title, optional description, ordered plain-text subitems, and the
  time it was archived; acceptance: archive priorities with empty and populated
  optional fields, relaunch, and compare every field and the recorded time;
  owner/method: engineering, persistence tests; provenance: confirmed grill
  decision.
- **R3 — Keep history immutable.** The user can view an archived entry but
  cannot edit it or return it to the active three. If the subject becomes
  important again, the user creates a new priority; acceptance: history exposes
  no edit, restore, or reactivate action and archived data remains unchanged
  while it is retained; owner/method: engineering and product owner, UI test
  plus runtime inspection; provenance: explicit user confirmation.
- **R4 — Make archive the primary removal path.** The active-priority editor
  presents Archive as its primary removal action. Permanent Delete remains a
  secondary destructive action and requires confirmation; acceptance: both
  paths are reachable, visually differentiated, and only permanent deletion
  presents destructive confirmation; owner/method: product owner and
  engineering, runtime inspection plus UI test; provenance: confirmed grill
  decision and existing delete behavior.
- **R5 — Permit immediate correction only.** Immediately after archiving, the
  user has one transient opportunity to undo that archive. Once the transient
  affordance expires or is dismissed, History provides no restore path;
  acceptance: undo restores the same priority once without duplication, while
  an expired or dismissed affordance cannot reactivate it; owner/method:
  engineering, deterministic state tests plus UI test; provenance: confirmed
  grill decision.
- **R6 — Preserve active-focus invariants.** Archiving the current focus makes
  the first remaining priority the current focus. Archiving the last active
  priority leaves no current focus and hides the priority top surface. Archiving
  a non-focus priority preserves the current focus; acceptance: tests cover all
  three cases and never persist more than three active priorities or a dangling
  focus identifier; owner/method: engineering, domain and overlay tests;
  provenance: confirmed grill decision plus existing Keep3 invariants.
- **R7 — Retain history until explicit deletion.** History is ordered newest
  archive first, has no item-count or age limit, and is never automatically
  cleared. The user can permanently delete an individual history entry after
  confirmation; acceptance: entries survive relaunch in reverse chronological
  order and disappear only after confirmed deletion; owner/method: engineering,
  persistence and UI tests; provenance: explicit user confirmation.
- **R8 — Export the complete record.** The user can export one Markdown document
  containing the current priorities in their current order followed by every
  archived snapshot in newest-first order. The export identifies the designated
  current focus and includes archive times; acceptance: export fixtures covering
  zero through three active priorities and zero through multiple history entries
  produce readable Markdown with all and only the expected content and ordering;
  owner/method: engineering, serializer tests; provenance: explicit user
  confirmation.
- **R9 — Export one archived entry.** From History, the user can export an
  individual archived snapshot as Markdown; acceptance: the resulting document
  contains exactly the selected snapshot's content and archive time;
  owner/method: engineering, serializer test plus UI test; provenance: explicit
  user confirmation.
- **R10 — Keep export non-mutating.** Exporting, cancelling export, or
  encountering an export error never archives, deletes, reorders, edits, or
  changes focus. A failure is reported without claiming a file was saved;
  acceptance: state equality checks cover successful, cancelled, and failed
  export attempts; owner/method: engineering, application-service tests;
  provenance: explicit user confirmation and existing non-destructive error
  principle.
- **R11 — Keep history and export local.** Archive contents remain in Keep3's
  local application data. Markdown is written only to a location the user
  chooses; no priority or archive content is sent over the network; acceptance:
  runtime export uses the standard macOS destination chooser and static/runtime
  network inspection finds no new content-bearing request; owner/method:
  engineering, runtime inspection and privacy regression check; provenance:
  existing local-first product boundary.
- **R12 — Preserve existing user data across adoption.** Updating from the
  current released state retains all active priorities, their order, and current
  focus, with an initially empty archive; acceptance: load a pre-feature state
  fixture and verify lossless migration followed by a successful archive/save/
  relaunch round trip; owner/method: engineering, migration fixture test;
  provenance: existing persistence guarantees and shipped-user compatibility.

## In Scope

- Archiving an active priority as an immutable local snapshot.
- A browsable newest-first History surface.
- Transient undo immediately after archive.
- Confirmed permanent deletion from either the active set or History.
- Complete-record and single-history-entry Markdown file export.
- Persistence compatibility for existing Keep3 installations.
- Empty, cancellation, write-failure, and relaunch behavior for these flows.

## Out of Scope

- Editing, restoring, reactivating, or moving an archived entry back into the
  active three.
- Completion state, checkboxes, progress, outcomes, scoring, streaks, review
  prompts, analytics, or productivity judgments.
- Search, filters, tags, folders, bulk selection, bulk deletion, or automatic
  retention policies for History.
- Markdown import, synchronization, sharing services, cloud storage managed by
  Keep3, accounts, or collaboration.
- Export formats other than Markdown.
- Changes to the three-active-priority limit or top-surface rotation semantics.

## Constraints and Confirmed Decisions

- The archive is historical evidence, not a parking lot or task status.
- Archived snapshots are immutable and have no persistent recovery path.
- Transient undo corrects only the immediately preceding archive operation and
  does not create a general History restore capability.
- Export reads state but never mutates it.
- Current priorities and archive history remain local-first and offline.
- Existing title, description, and subitem content rules remain unchanged.
- The current shipped state format must migrate without losing user data.

## Delegated Engineering Defaults and Boundaries

Engineering may choose the archive persistence representation, migration
mechanics, History navigation placement, transient-undo duration, standard macOS
save-panel configuration, default filenames, heading levels, date rendering,
and Markdown escaping rules, provided every choice satisfies R1–R12 and:

- does not add a third-party dependency, entitlement, permission, or network
  access;
- produces UTF-8 plain-text `.md` files that preserve all user-authored text and
  are readable in ordinary Markdown editors;
- makes the current-focus marker and archive times unambiguous;
- keeps destructive deletion visually and accessibly distinct from Archive;
- does not expose archived entries on the top surface or count them toward the
  three-priority limit.

## Deferred Adjacent Ideas

Search, filtering, bulk operations, additional export formats, and Markdown
import may be evaluated as separate product requests after real archive usage
demonstrates a need.

## Open Product Decisions

None.
