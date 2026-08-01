# Keep3 Media Compatibility Verification

This record is the release-gate evidence for Keep3's isolated MediaRemote
compatibility boundary. It does not claim end-to-end player parity by itself.
Player-specific session discovery, metadata, and commands remain gated by the
integration matrix below.

Release status: the pending provider rows remain public-launch blockers in
[`keep3-distribution.md`](keep3-distribution.md). Distribution work does not
turn a debug or ad-hoc media result into signed-release provider evidence.

## Verified host

| Item | Value |
| --- | --- |
| macOS | 15.7.7 (24G720) |
| Architecture | arm64 |
| Xcode | 16.4 (16F6) |
| SDK | macOS 15.5 |
| Verified implementation commit | `0e74be0` |

The verified implementation commit is a historical probe baseline. Public
distribution preserves the current app identifier `dev.keep3.Keep3` and helper
identifier/XPC service name `dev.keep3.Keep3MediaService`; final live checks
must run against the exact candidate commit and embedded helper.

## Runtime symbol probe

The helper successfully opened:

`/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote`

Resolved mandatory symbols:

- `MRMediaRemoteCommandInfoGetCommand`
- `MRMediaRemoteCommandInfoGetEnabled`
- `MRMediaRemoteCopySupportedCommands`
- `MRMediaRemoteGetLocalOrigin`
- `MRMediaRemoteGetNowPlayingClient`
- `MRMediaRemoteGetNowPlayingClients`
- `MRMediaRemoteGetNowPlayingInfo`
- `MRMediaRemoteGetNowPlayingInfoForClient`
- `MRMediaRemoteGetNowPlayingApplicationIsPlaying`
- `MRMediaRemoteGetNowPlayingApplicationPID`
- `MRMediaRemoteGetSupportedCommandsForClient`
- `MRMediaRemoteRegisterForNowPlayingNotifications`
- `MRMediaRemoteUnregisterForNowPlayingNotifications`
- `MRMediaRemoteSendCommand`
- `MRMediaRemoteSendCommandToClient`
- `MRNowPlayingClientCreate`
- `MRNowPlayingClientGetBundleIdentifier`
- `MRNowPlayingClientGetParentAppBundleIdentifier`

Resolved optional symbols:

- `MRMediaRemoteSetElapsedTime`
- `MRMediaRemoteSetShuffleMode`
- `MRMediaRemoteSetRepeatMode`

No probed symbol was missing on this host. Optional transport symbols and the
current-source capability group still fail closed independently: a missing
transport symbol retracts only its mapped capability, while a missing mandatory
client-discovery or command symbol disables media rather than advertising
unverified framework-wide support.

## Isolation and failure behavior

- `Keep3MediaService.xpc` is built before the app and embedded at
  `Keep3.app/Contents/XPCServices/Keep3MediaService.xpc`.
- The XPC service owns `dlopen` and `dlsym`.
- Neither the Keep3 executable nor its debug dylib has a static MediaRemote
  dependency or undefined MediaRemote symbols.
- The app/XPC contract uses versioned, property-list-safe dictionaries.
- The app supplies a bounded, validated snapshot of running applications when
  it starts monitoring. The XPC service uses that host-owned process context
  instead of relying on an `NSWorkspace` cache inside the service process.
- The helper bounds strings and artwork before XPC, publishes artwork as
  `replace` / `unchanged` / `clear`, and rejects stale capability revisions.
- Every asynchronous refresh is fenced by both monitoring generation and
  runtime identity.
- Controls are derived from enabled commands reported for the current source,
  not from MediaRemote symbol presence.
- When the global Now Playing payload is empty or uncontrollable, the helper
  enumerates registered clients, prefers the system-selected or previously
  selected client, and publishes the first running client with Play/Pause.
- Commands for a client-discovered inactive player are sent back to that exact
  client instead of relying on the global command target.
- If no registered client exists, the helper can construct an exact
  process-bound client for a running Apple Music, Spotify, or NetEase Cloud
  Music application and expose Play/Pause. Browser processes are intentionally
  excluded because a running browser alone does not identify a media session.
- A process-bound client is resolved through its default player and
  `MRNowPlayingPlayerPath`. Metadata and enabled commands are then requested
  from that exact player path; artwork is requested from its playback queue at
  a bounded 512-point size.
- After a dormant Play command is accepted, refreshes at 0.35, 1.2, and 2.5
  seconds bridge players that publish their first metadata asynchronously.
  Refreshes stop affecting presentation as soon as metadata is available.
- Player launch and termination are reconciled by the app with bounded retries;
  stale PIDs are rejected and the component is removed after process exit.
- The per-client command completion byte is interpreted according to the
  observed ABI on this host: status `0` means accepted.
- A missing mandatory symbol, malformed compatibility response, protocol
  mismatch, interruption, or invalidation produces `.unavailable`.
- Missing optional symbols remove only their corresponding capability.

## Automated evidence

The original post-rebase suite for the verified commit passed 146/146 tests.
The 2026-07-28 dormant-player regression checks on the current working tree
include:

- `MediaRemoteSymbolsTests`: 11 tests
- `WorkspaceApplicationObserverTests`: 1 test
- `MediaSessionNormalizationTests`: 8 tests
- `MediaCommandCoordinatorTests`: 7 tests
- `MediaRemoteAdapterIntegrationTests`: 2 tests

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
| NetEase Cloud Music | Debug pass | Debug pass | Debug pass | Debug pass | Debug capability | Pending | Debug pass | Release pending |
| Safari media | Pending | Pending | Pending | Pending | Pending | Pending | Pending | Not verified |
| Chrome media | Pending | Pending | Pending | Pending | Pending | Pending | Pending | Not verified |

## Remaining release gates

Every item in this section is still pending and release-blocking. Completion
must be copied into `keep3-distribution.md` with the candidate version, build,
commit, signing state, host, and player versions.

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
