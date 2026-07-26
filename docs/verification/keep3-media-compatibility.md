# Keep3 Media Compatibility Verification

This record is the release-gate evidence for Keep3's isolated MediaRemote
compatibility boundary. It does not claim end-to-end player parity by itself.
Player-specific session discovery, metadata, and commands remain gated by the
integration matrix below.

## Verified host

| Item | Value |
| --- | --- |
| macOS | 15.7.7 (24G720) |
| Architecture | arm64 |
| Xcode | 16.4 (16F6) |
| SDK | macOS 15.5 |
| Verified implementation commit | `0e74be0` |

## Runtime symbol probe

The helper successfully opened:

`/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote`

Resolved mandatory symbols:

- `MRMediaRemoteGetNowPlayingInfo`
- `MRMediaRemoteGetNowPlayingApplicationIsPlaying`
- `MRMediaRemoteGetNowPlayingApplicationPID`
- `MRMediaRemoteRegisterForNowPlayingNotifications`
- `MRMediaRemoteUnregisterForNowPlayingNotifications`
- `MRMediaRemoteSendCommand`

Resolved optional symbols:

- `MRMediaRemoteSetElapsedTime`
- `MRMediaRemoteSetShuffleMode`
- `MRMediaRemoteSetRepeatMode`

Resolved current-source capability symbols:

- `MRMediaRemoteGetLocalOrigin`
- `MRMediaRemoteCopySupportedCommands`
- `MRMediaRemoteCommandInfoGetCommand`
- `MRMediaRemoteCommandInfoGetEnabled`

No probed symbol was missing on this host. Optional transport symbols and the
current-source capability group still fail closed independently: a missing
transport symbol retracts only its mapped capability, while a missing
current-source capability symbol produces an empty control set instead of
advertising framework-wide support.

## Isolation and failure behavior

- `Keep3MediaService.xpc` is built before the app and embedded at
  `Keep3.app/Contents/XPCServices/Keep3MediaService.xpc`.
- The XPC service owns `dlopen` and `dlsym`.
- Neither the Keep3 executable nor its debug dylib has a static MediaRemote
  dependency or undefined MediaRemote symbols.
- The app/XPC contract uses versioned, property-list-safe dictionaries.
- The helper bounds strings and artwork before XPC, publishes artwork as
  `replace` / `unchanged` / `clear`, and rejects stale capability revisions.
- Every asynchronous refresh is fenced by both monitoring generation and
  runtime identity.
- Controls are derived from enabled commands reported for the current source,
  not from MediaRemote symbol presence.
- A missing mandatory symbol, malformed compatibility response, protocol
  mismatch, interruption, or invalidation produces `.unavailable`.
- Missing optional symbols remove only their corresponding capability.

## Automated evidence

The post-rebase suite passes 146/146 tests, including:

- `MediaRemoteSymbolsTests`: 2 tests
- `MediaSessionNormalizationTests`: 7 tests
- `MediaCommandCoordinatorTests`: 5 tests
- `MediaRemoteAdapterIntegrationTests`: 1 test

Static analysis and the optimized arm64 Release build pass. The embedded helper
has package type `XPC!`. The Release app and helper were ad-hoc signed and passed
deep strict `codesign` verification. Dependency and undefined-symbol inspection
show no static MediaRemote linkage; the helper contains only the expected
dynamically resolved MediaRemote symbol strings.

## Provider integration matrix

Rows stay release-blocking until the real signed adapter demonstrates the
available behavior on each source. A dash means the source does not expose the
capability, not that Keep3 should render an empty control.

| Source | Discover | Metadata | Artwork | Play/pause | Prev/next | Seek | Pause return | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Apple Music | Pending | Pending | Pending | Pending | Pending | Pending | Pending | Not verified |
| Spotify | Pending | Pending | Pending | Pending | Pending | Pending | Pending | Not verified |
| NetEase Cloud Music | Pending | Pending | Pending | Pending | Pending | Pending | Pending | Not verified |
| Safari media | Pending | Pending | Pending | Pending | Pending | Pending | Pending | Not verified |
| Chrome media | Pending | Pending | Pending | Pending | Pending | Pending | Pending | Not verified |

## Remaining release gates

- Prove stable normalized snapshots and increasing revisions from live
  MediaRemote callbacks.
- Prove XPC interruption/backoff and epoch rejection with an active session.
- Complete the source matrix on a signed Release build.
- Verify player commands and success confirmation independently from UI
  animation.
- Repeat the compatibility probe for every supported macOS/architecture row.

The live provider gate is tracked in
[GitHub issue #4](https://github.com/taobaorun/keep3/issues/4). Trusted
provider-specific Favorite and Repeat One dispatch is tracked separately in
[GitHub issue #3](https://github.com/taobaorun/keep3/issues/3); Keep3 leaves
those controls hidden until a verified backend exists.
