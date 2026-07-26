# Keep3 Event Surface Verification

## Scope

This record covers the post-MVP event surface iteration:

- ordered priorities, media, and Calendar components;
- hardware-aligned, compact, and expanded surface levels;
- vertical depth/component navigation;
- horizontal media track gestures with directional feedback;
- token-confirmed compact track metadata peeks;
- opt-in EventKit Calendar content;
- keyboard, accessibility, display-lifecycle, and XPC boundaries.
- named VoiceOver depth/component actions backed by the shared navigation state
  machine.

## Automated evidence

- Swift strict formatting/lint: passed.
- Focused state and integration tests: 55 passed, 0 failed.
  - priority availability and Calendar fallback;
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

## Release checks

- Full Keep3Tests suite: 176 executed, 175 passed, 1 live-environment test
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
- Physical two-finger direction and trackpad haptic: requires an unlocked,
  interactive console and human trackpad input.

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
