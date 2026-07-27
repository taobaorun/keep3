# Keep3 Event Surface Verification

## Scope

This record covers the post-MVP event surface iteration:

- ordered priorities, media, and Calendar components;
- hardware-aligned, compact, and expanded surface levels;
- vertical depth/component navigation with threshold-crossing haptics,
  including expanded Media Up returning to compact Media while Down and
  non-media component navigation remain directional;
- horizontal media track gestures with directional feedback;
- token-confirmed compact track metadata peeks with Next fixed-left, Previous
  fixed-right, and separate title and artist below the hardware notch;
- opt-in EventKit Calendar content;
- keyboard, accessibility, display-lifecycle, and XPC boundaries;
- named VoiceOver depth/component actions backed by the shared navigation state
  machine.

## Automated evidence

- Swift strict formatting/lint: passed.
- Focused correction suites: 82 passed, 0 failed.
  - priority availability and Calendar fallback;
  - one recognition haptic when a valid depth/component or track gesture first
    crosses its lock threshold, before gesture-end commit;
  - rotation resume across component switches;
  - screen-frame gesture ownership and resize cancellation;
  - media accepted/rejected/timeout/content-confirmation behavior;
  - metadata peek timing;
  - Calendar authorization, mid-query revocation, and request failure;
  - keyboard ownership across component rendering.
- Baseline UI automation before the review fixes: 4 passed, 0 failed.
- Calendar UI fixture and zero-priority fallback scenario: implemented; execution
  is pending an unlocked console session. The 2026-07-26 attempt was blocked
  before assertions because macOS reported `CGSSessionScreenIsLocked=Yes` and
  XCUIApplication could not activate either the new scenario or an unchanged
  baseline scenario.

## Media correction evidence

| Gate | Status | Evidence required |
|---|---|---|
| Directional geometry | Pending | Next preserves the baseline left edge and wing; Previous preserves the baseline right edge and wing through pending, confirmed, and retract phases |
| Metadata hierarchy | Pending | Notched placement uses a continuously rounded 68-point shelf below the notch with separate title and artist lines and no inline wing metadata; floating placement preserves the same hierarchy |
| Expanded Media navigation | Pending | A real upward two-finger gesture collapses expanded Media to compact Media without changing component; Down and expanded non-media gestures keep their established component navigation |
| Accessibility parity | Pending | The activated keyboard and VoiceOver action is named "Return to normal player", focuses compact Media after collapse, and announces that state once |

## Four-direction keyboard follow-up

The expanded Priorities, Media, and Calendar surfaces now share one explicit
keyboard-navigation affordance. Its visible direction summary and accessibility
hint are derived from the current component state:

- Priorities show Left/Right only when more than one item can be browsed and
  include Return because the visible priority can be opened.
- Media show Previous and Next only when the active session exposes those
  capabilities; Up returns expanded Media to the normal player and Down moves
  to the next surface.
- Calendar show only Up/Down component navigation and do not advertise a
  horizontal or Return action.
- Once activated, the affordance changes to a green “Enabled” state and Keep3
  announces the available actions. Escape announces exit before the keyboard
  session restores the previously active application.

Per the 2026-07-27 acceptance request, this follow-up is left for human
verification rather than claiming a new automated run:

1. Hover each compact surface and confirm Keep3 does not become active.
2. Expand Priorities with two or more items, activate the keyboard affordance,
   and confirm the visible “Enabled” state; use Left/Right to browse, Up/Down to
   change surface, and Return to open the item currently shown.
3. Expand Media with asymmetric Previous/Next capabilities and confirm only the
   supported track directions are advertised and actionable.
4. Expand Calendar and confirm its affordance advertises Up/Down only.
5. Press Escape from each active session and confirm the exit announcement,
   compact surface, and focus restoration to the application active before
   Keep3.

## Release checks

- Full Keep3Tests suite: 206 executed, 205 passed, 1 live-environment test
  skipped, 0 failed.
- Static analyzer: passed.
- Swift strict formatting/lint and `git diff --check`: passed.
- arm64 Release build: passed.
- Final local ad-hoc deep signature verification: passed for the application
  and embedded XPC service.
- Dynamic-only MediaRemote boundary: passed. `otool` and `nm` show no static
  MediaRemote dependency or undefined MediaRemote symbols in either executable.
- Installed `/Applications/Keep3.app` launch: passed; the app and embedded media
  service were both running from the installed bundle.
- Live media snapshot: passed. The installed helper registered with
  `mediaremoted` and resolved a playing
  `com.netease.163music`/网易云音乐 session.
- Physical two-finger direction, trackpad haptic, expanded Media retreat, and
  accessibility focus/announcement require the installed Release app on an
  unlocked, interactive console with human input.

## Privacy and isolation

- Calendar remains disabled by default and permission is requested only from
  Settings.
- EventKit work runs behind a serial actor and returns normalized, bounded
  `CalendarEvent` values.
- Authorization loss clears cached titles before publishing a denied or
  restricted state.
- Calendar values do not enter the media XPC service.
- MediaRemote remains dynamically resolved inside the embedded XPC service.
- An interrupted media client invalidates its connection immediately, and
  monitoring, publication, and commands are bound to the active client
  generation.
