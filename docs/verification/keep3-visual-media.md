# Keep3 Visual System 2.0 and Media Verification

Date: 2026-07-26  
Environment: Apple Silicon Mac, macOS 15.7.7, Xcode 16.4, macOS 15.5 SDK,
Swift 6, arm64  
Verified implementation commit: `0e74be0`

Status: Code gates pass; live provider and UI session gates are documented

## Delivered behavior

- One stationary top canvas owns both priority and media presentation.
- Priority changes use Keep3's signature staged transition without moving the
  panel.
- Settings use a sidebar, grouped controls, and live previews for Focus Surface
  and Media.
- A playing system media session preempts priorities; pause, stop, interruption,
  exit, suppression, and service loss return the latest priority.
- Compact and expanded media presentations include normalized metadata,
  capability-gated controls, progress, artwork treatments, waveform preference,
  Quick Peek, and manual expansion.
- Precise horizontal two-finger gestures dispatch one previous/next command
  only at the end of the physical gesture. Momentum and vertical intent are
  rejected for track navigation.
- Confirmed track metadata uses a continuously rounded 68-point shelf below the
  hardware notch with separate title and artist lines and no metadata in the
  artwork or waveform wings. Next keeps the left edge and left wing fixed;
  Previous keeps the right edge and right wing fixed. Floating placement uses
  the same hierarchy in a rounded capsule.
- Regular, notched-compact, and expanded waveforms use a readable accent derived
  and cached from the current confirmed cover, with a deterministic readable
  fallback for missing or unusable artwork.
- From expanded Media, Up returns to compact Media without changing component;
  Down and expanded non-media gestures retain component navigation. The
  equivalent activated accessibility action is named "Return to normal player",
  focuses compact Media, and announces the resulting state once.
- One haptic is emitted when a supported track gesture first crosses its lock
  threshold, before gesture-end command dispatch. A newer matching track
  identity controls the metadata peek and does not emit a second haptic.

## Safety boundary

Global media access is isolated in `Keep3MediaService.xpc`. The service
dynamically resolves Apple's private `MediaRemote.framework`, publishes only
bounded property-list values, and carries a protocol version. The main app
rejects malformed or stale snapshots and falls back to priorities if the
service becomes unavailable.

The main executable does not link MediaRemote. The private integration remains
an explicit personal-build exception and is not Mac App Store compatible.

## Automated evidence

| Gate | Result | Evidence |
|---|---|---|
| Format and lint | Pass | Recursive `swift-format`; zero lint findings |
| Debug build | Pass | `xcodebuild build`, arm64 |
| Unit tests | Pass | 206 executed, 205 passed, 1 live-environment test skipped, 0 failed |
| Media interaction | Pass | Gesture, command confirmation, haptic, Quick Peek, source policy, lifecycle, and surface ownership tests |
| Static analysis | Pass | Debug `xcodebuild analyze` |
| Release build | Pass | Optimized arm64 app and embedded XPC service |
| Package integrity | Pass | Explicit ad-hoc signing followed by deep, strict `codesign --verify` |
| Binary boundary | Pass | `otool -L` and `nm -u` show no static MediaRemote dependency or undefined MediaRemote symbols; the helper contains the expected dynamic symbol strings |
| UI test source | Pass | The new media-first fixture scenario compiles into `Keep3UITests` |
| UI execution | Session-state exception | The macOS UI test runner was rejected before test launch because system authentication/loginwindow was active (`LocalAuthentication Code=-4`) |

## Installed Release correction checklist

| Scenario | Status | Required observation |
|---|---|---|
| Notched, normal motion | Pending — blocking | Use real two-finger Next and Previous gestures. Next leaves the left side unchanged, Previous leaves the right side unchanged, and slow-motion frame capture shows no angular corner during pending, confirmation, or retraction |
| Notched, Reduce Motion | Pending — blocking | The fixed side remains invariant; the rounded 68-point metadata shelf appears by crossfade below the notch and restores the persistent frame without directional travel |
| Floating placement | Pending | Real Next and Previous gestures preserve the mirrored fixed sides, keep the title/artist hierarchy outside waveform content, and retain a continuous rounded capsule |
| Valid bright artwork | Pending | Every waveform style changes to a readable accent derived from the current cover |
| Valid dark artwork | Pending | The derived accent remains readable against the black surface |
| Missing or invalid artwork | Pending | Every waveform style uses the deterministic readable fallback without stale cover color |
| Expanded Media Up | Pending | One real upward two-finger gesture and the equivalent keyboard/VoiceOver action return to compact Media, keep Media selected, focus the compact player, and announce the result once |
| Regression directions | Pending | Expanded Media Down and expanded non-media Up/Down continue component navigation without dispatching media commands |

The XPC integration test starts the embedded Alcove-style helper, resolves the
macOS 15.5 MediaRemote symbols, establishes the versioned client/service
interfaces, and stops cleanly. It does not require a third-party player to be
running.

The UI fixture provides a deterministic NetEase-style playing session, confirms
media ownership and next-command completion, then disables media-first mode and
expects the priority capsule to return. The fixture test did not reach its first
assertion in this run because the operating system refused to initialize
XCUITest while system authentication was active. Rerun that one test from an
unlocked desktop before distributing a binary:

```bash
xcodebuild test -project Keep3.xcodeproj -scheme Keep3 \
  -derivedDataPath .build/DerivedData -destination 'platform=macOS' \
  -only-testing:Keep3UITests/Keep3UITests/testPlayingMediaOwnsSurfaceAndDisablingMediaRestoresFocus
```
