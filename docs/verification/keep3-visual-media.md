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
- Precise vertical two-finger gestures dispatch one previous/next command only
  at the end of the physical gesture. Momentum and horizontal intent are
  rejected.
- A success haptic is emitted only after Keep3 observes a newer track identity
  for the same active session and capability revision.

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
| Unit tests | Pass | 146/146 after rebase, including helper integration |
| Media interaction | Pass | Gesture, command confirmation, haptic, Quick Peek, source policy, lifecycle, and surface ownership tests |
| Static analysis | Pass | Debug `xcodebuild analyze` |
| Release build | Pass | Optimized arm64 app and embedded XPC service |
| Package integrity | Pass | Explicit ad-hoc signing followed by deep, strict `codesign --verify` |
| Binary boundary | Pass | `otool -L` and `nm -u` show no static MediaRemote dependency or undefined MediaRemote symbols; the helper contains the expected dynamic symbol strings |
| UI test source | Pass | The new media-first fixture scenario compiles into `Keep3UITests` |
| UI execution | Session-state exception | The macOS UI test runner was rejected before test launch because system authentication/loginwindow was active (`LocalAuthentication Code=-4`) |

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
