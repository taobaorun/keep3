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
| Boundary commit | `8d0ae84` |

## Runtime symbol probe

The helper successfully opened:

`/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote`

Resolved mandatory symbols:

- `MRMediaRemoteGetNowPlayingClient`
- `MRMediaRemoteRegisterForNowPlayingNotifications`
- `MRMediaRemoteSendCommand`

Resolved optional symbols:

- `MRMediaRemoteSetElapsedTime`
- `MRMediaRemoteSetShuffleMode`
- `MRMediaRemoteSetRepeatMode`

Missing optional symbols:

- `MRMediaRemoteGetPlaybackQueue`

The missing optional queue symbol retracts only its mapped capability. It does
not disable baseline media support.

## Isolation and failure behavior

- `Keep3MediaService.xpc` is built before the app and embedded at
  `Keep3.app/Contents/XPCServices/Keep3MediaService.xpc`.
- The XPC service owns `dlopen` and `dlsym`.
- Neither the Keep3 executable nor its debug dylib has a static MediaRemote
  dependency or undefined MediaRemote symbols.
- The app/XPC contract uses versioned, property-list-safe dictionaries.
- A missing mandatory symbol, malformed compatibility response, protocol
  mismatch, interruption, or invalidation produces `.unavailable`.
- Missing optional symbols remove only their corresponding capability.

## Automated evidence

The focused boundary suite passes:

- `MediaRemoteSymbolsTests`: 2 tests
- `MediaSessionNormalizationTests`: 2 tests

The Debug app build passes, the embedded helper has package type `XPC!`, and
both app and helper dependency inspection show no static MediaRemote linkage.

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
