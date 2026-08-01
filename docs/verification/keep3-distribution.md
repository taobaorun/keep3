# Keep3 distribution readiness

Date: 2026-08-01
Implementation baseline: `feat/open-source-distribution` through `9914418`
Status: Native unsigned-distribution implementation present; public launch
blocked by the pending gates below

## Readiness decision

The repository contains the legal, update, packaging, signed-metadata, and
staged-promotion foundations needed to prepare an unsigned Keep3 candidate.
This is not approval to publish a public release. `NoRelease` remains the
expected public state until every launch-blocking row is complete and the
protected release environment passes a real dry run.

Apple Developer funding is not an unsigned implementation gate. Cleared
cumulative donations covering the approved USD 99 first-year fee starts a
separate Developer ID/notarization implementation. Until then, Keep3 may prepare
an unsigned release with truthful installation guidance. Once trusted
distribution starts, loss or expiry of credentials freezes new releases; it
does not authorize a return to unsigned artifacts.

## Repository evidence

| Area | Status | Evidence |
| --- | --- | --- |
| Free source and identity | Implemented | GPL-3.0-only `LICENSE`, exact-tag guidance, third-party notices, `dev.keep3.Keep3`, project-owned helper, semantic marketing version, and numeric build |
| Sparkle boundary | Implemented | Sparkle 2.9.4 is pinned; manual checks and opt-in automation use the canonical feed; system profiling is disabled; archive and signed-feed verification are enforced, with the production key still gated below |
| Release contract | Implemented | Schemas and fixtures cover immutable manifest, signed current discovery, signed operational status, strict build order, artifact SHA-256, exact source, Sparkle signature, and Homebrew projection |
| Release candidate | Implemented | One credential-free candidate is built and attested; promotion reuses the candidate digest rather than rebuilding tagged bytes |
| Channel promotion | Implemented, production unproven | Protected promotion validates ancestry, attestations, monotonicity, credentials, and channel order; failure fixtures cover Promoting, Degraded, and Compromised states |
| Website handoff | Implemented, external app pending | `docs/distribution/website-handoff.md` defines pinned verification, privacy, click, donation, copy, and trust-transition requirements without website code |
| Tracked website audit | Pass | `scripts/tests/website-handoff-tests.sh` rejects any repository-index path under `website/`; it does not inspect or mutate a local user-owned directory |

## Focused automated evidence

| Gate | Command | Result |
| --- | --- | --- |
| Website handoff and documentation links | `scripts/tests/website-handoff-tests.sh` | Pass on 2026-08-01 |
| Release schemas, signatures, packaging, and projections | `scripts/tests/release-contract-tests.sh` | Pass on 2026-08-01 |
| Sparkle archive/update fixtures | `scripts/tests/sparkle-integration-tests.sh` | Pass on 2026-08-01 |
| Promotion state and failure matrix | `scripts/tests/channel-promotion-tests.sh` | Pass on 2026-08-01, including sequential release replacement and resumable failure paths |
| Native full suite, format, analysis, and Release build | Plan verification commands | Local pass on 2026-08-01; four keyboard-routing cases explicitly skipped because the locked desktop did not grant key-window ownership |

The release scripts keep private keys and channel credentials outside the
repository. The checked-in metadata key contains public material only. A final
secret scan and protected-environment review remain required because fixture
success does not prove production credential hygiene.

## Privacy and release assertions

- Keep3 sends no priorities, Calendar data, media state, preference values, or
  usage events. Native network traffic is limited to Sparkle release discovery
  and archive download; system profiling is disabled.
- There is no trial, license key, subscription, payment gate, donor entitlement,
  account, or in-app analytics path.
- Every binary must name its exact source tag and retain GPL text, dependency
  lock, packaging and release scripts, third-party notices, and source archive.
- The unsigned Homebrew cask keeps quarantine intact. Neither the app nor the
  cask automatically runs `xattr`; public copy must describe Control-click →
  Open and Privacy & Security approval truthfully.
- GitHub, Homebrew, Sparkle, signed current discovery, and the future website
  must converge on the same immutable DMG, checksum, version, build, source,
  and trust state before current discovery moves.
- A compromised Sparkle or metadata key blocks appcast, current, tap, and
  release publication. Recovery follows
  `docs/distribution/update-key-incident-runbook.md` with a higher-version
  manual trust-root build.

## Public-launch blockers

All rows are mandatory. “Pending” is intentionally release-blocking.

| Blocker | Status | Required completion evidence |
| --- | --- | --- |
| GPL compatibility review | Pending | Human review confirms Sparkle 2.9.4 and every shipped component are GPL-3.0-compatible; `THIRD_PARTY_NOTICES.md`, dependency lock, tagged source, and release assets agree |
| live media/provider checks | Pending | Complete the signed Release provider matrix in `keep3-media-compatibility.md`, including discovery, metadata, artwork, commands, interruption recovery, and supported OS/architecture rows |
| permanent Sparkle key provisioning and backup | Pending | Replace the fixture `SUPublicEDKey` before the first tag; record offline encrypted backup, recovery access, public-key review, and old-to-new fixture update evidence |
| permanent metadata key provisioning and backup | Pending | Replace the checked-in fixture public key; record key ID, fingerprint, offline encrypted backup, website pin, recovery access, and signed consumer fixtures |
| tap ownership and token | Pending | Create and protect `taobaorun/homebrew-keep3`, verify `taobaorun/keep3` naming, configure a least-privilege token, and pass clean install/upgrade/uninstall on macOS 14+ |
| gh-pages setup | Pending | Create and protect the release-channel Pages source, serve the canonical HTTPS endpoints, configure caching, and verify origin, expiry, immutable paths, and rollback rejection |
| standalone website readiness | Pending | Separate application passes signed-metadata fixtures, direct-download failure tests, unsigned copy, privacy disclosure, unique-click methodology, 90-day reporting, and donation failure behavior |
| channel credentials | Pending | Protected `release-production` environment contains least-privilege GitHub Pages, release, tap, Sparkle, and metadata credentials with reviewer approval and no tag-job access |
| Protected publisher live exercise | Pending | Exercise the wired U4 generate, Sparkle-sign, metadata-sign, validate, tap-PR, publish, probe, and recovery path in the reviewed `release-production` environment; prove trusted-main preflight completes before protected credentials are read |
| Unsigned installation proof | Pending | A clean supported Mac verifies SHA-256, downloads the canonical DMG, completes documented macOS approval without automatic quarantine removal, launches, upgrades, and uninstalls |
| Cross-channel production dry run | Pending | Protected workflow re-verifies ancestry, attestation, signatures, exact bytes, monotonic build, appcast, tap, GitHub asset, current/status state, and forward recovery |
| Final native regression gate | Local automation pass; physical checks pending | Current branch passed format, focused and full tests, static analysis, Release build, property-list validation, and source/privacy/secret audit. Complete the key-window/UI cases from an unlocked desktop and the remaining physical MVP checks before public launch |

## Standalone website gate

The website is a public-launch dependency but not a native build dependency.
Its implementation, host, analytics provider, donation provider, domain, DNS,
and deployment remain external to this repository. Click measurement is
best-effort and never gates the download. The first target is 100 unique primary
download-link activations in the first 90 days, reported only as download
interest—not installation, active use, or retention.

## Post-funding Developer ID handoff

The future signing work must preserve:

- app `dev.keep3.Keep3` and helper/XPC `dev.keep3.Keep3MediaService`;
- `~/Library/Application Support/Keep3/state.json`, the standard `UserDefaults`
  domain `dev.keep3.Keep3`, and existing preference keys;
- the Sparkle feed and permanent `SUPublicEDKey`;
- the metadata key handoff used by the standalone website; and
- semantic version plus strictly increasing numeric build order.

The transition gate must prove nested signing, hardened runtime, Developer ID,
`notarytool`, stapling, Gatekeeper, permissions, and update continuity from the
last unsigned release. After the first Developer ID-signed and notarized stable
release, all official binary channels stay signed; renewal failure pauses
publication rather than weakening trust.
