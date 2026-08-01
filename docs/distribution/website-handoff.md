# Keep3 standalone website handoff

This document is the integration contract for the separately owned Keep3
website application. The native repository publishes release facts; the
website verifies and presents them. The website must not scrape GitHub's
“latest” page, infer a version from page content, publish native artifacts, or
write any release channel.

## Ownership boundary

This repository owns the macOS app, immutable DMG, GitHub Release, Sparkle
appcast, Homebrew projection, and signed release metadata. The standalone
website owns its hosting, domain, deployment, product copy, unique download
clicks, privacy disclosure, analytics provider, and external donation path.
Website source and generated output do not belong in this repository.

The website is a read-only consumer. A clean clone of the native repository
must build, test, package, and validate without a `website/` directory.

## Pinned contract

| Purpose | Canonical location |
| --- | --- |
| Stable release discovery | `https://taobaorun.github.io/keep3/release-channel/current-release.json` |
| Operational state | `https://taobaorun.github.io/keep3/release-channel/release-status.json` |
| Immutable release facts | URL in `current-release.json`, under `https://taobaorun.github.io/keep3/release-channel/releases/vMAJOR.MINOR.PATCH/manifest.json` |
| Sparkle feed | `https://taobaorun.github.io/keep3/release-channel/appcast.xml` |
| Repository identity | `taobaorun/keep3` |
| Metadata public key | `distribution/release-metadata-public-key.pem` |
| Schemas | `distribution/current-release.schema.json`, `distribution/release-status.schema.json`, and `distribution/release-manifest.schema.json` |

The website must embed the reviewed permanent Ed25519 metadata public key at
build or deployment time. It must not fetch a replacement key from the same
channel it is trying to authenticate. The checked-in key is a development
fixture until the release-readiness ledger records permanent key provisioning,
offline backup, key identifier, and fingerprint review.

The Sparkle archive trust root is separate. Installed apps pin it through
`SUPublicEDKey`; the website neither verifies Sparkle archives with the
metadata key nor changes the Sparkle key.

## Consumer verification algorithm

Reject by default. Do not turn an invalid response into a download link.

1. Fetch only the exact HTTPS endpoints above. Reject a different host,
   repository, `canonicalOrigin`, or path family.
2. Limit response size, parse JSON without duplicate keys, and validate the
   complete envelope against its checked-in `schemaVersion` schema. An unknown
   schema is unsupported, not “close enough.”
3. Require `signature.algorithm` to be `Ed25519`, require the envelope and
   signed payload `keyId` values to agree with the pinned key identifier, and
   verify `signature.value` with the pinned public key. Verification covers the
   entire root object after removing `signature`: object keys are recursively
   sorted lexicographically, arrays retain order, and the result is compact
   UTF-8 JSON. This matches `scripts/release/sign-release-metadata.sh`.
4. Require `signed.repository` to equal `taobaorun/keep3` and
   `signed.canonicalOrigin` to equal `https://taobaorun.github.io`. Require
   `publishedAt` not to be unreasonably in the future and require the current
   time to be before `expiresAt`.
5. Persist the greatest accepted `sequence` per document type, a digest of the
   accepted envelope, and the greatest accepted stable numeric `build`. A
   byte-identical cached envelope may be reused while unexpired. A different
   envelope with an equal or lower sequence, or a lower build, is a replay or
   rollback and is rejected. `CURRENT_PROJECT_VERSION` is strictly increasing
   even when the marketing version changes.
6. Verify `release-status.json` first. `NoRelease` and `Candidate` expose no
   public candidate. `Promoting` and `Degraded` retain the last verified stable
   current release and may show the signed status message. `Compromised`
   suppresses automatic discovery and directs users to the project security
   advisory. Only `Converged` permits a new current release.
7. Fetch `current-release.json`. It must be signed, unexpired, and
   `state: Converged`. Fetch its `manifestUrl`; never construct a mutable
   artifact URL or use a GitHub “latest” redirect.
8. Validate and verify the immutable manifest with the same metadata key.
   Require current and manifest `sequence`, `version`, `build`, `tag`,
   `trustState`, `manifestUrl`, and `artifact.url` to agree. The tag must equal
   `v` plus the version.
9. Resolve the primary download only from `artifact.url`. Present its
   `sha256`, size, version, trust state, and source tag link. The artifact URL
   must be the versioned GitHub Release URL allowed by the schema.
10. Present Homebrew only from the verified channel fields. The current command
    is `brew install --cask taobaorun/keep3/keep3`; the appcast remains the
    verified Sparkle feed above. All surfaces must describe the same version and
    build before the site reports channel consistency.

HTTP cache data may be reused only while the signed `expiresAt` remains valid
and it does not roll back the stored sequence or build. Network, parse, schema,
signature, expiry, or consistency failure keeps the last still-valid verified
release; otherwise the site shows release discovery as temporarily unavailable
and links to the generic project Releases page without claiming a current
artifact.

## Website measurement and donations

The primary download is a normal link to the verified immutable artifact. A
measurement request is best-effort and independent of navigation: tracking
failure never gates the download, delays it, changes its target, or substitutes
an intermediary binary. Analytics, blockers, offline use, and script errors
must all leave the direct download usable.

In short: tracking failure never gates the download.

The standalone website must:

- count unique download clicks without requiring a Keep3 account;
- document how “unique” is calculated, collect the minimum data needed, and
  avoid claiming that raw or unique clicks prove installation or usage;
- start the first 90-day validation window at the recorded public-launch time
  and report the target of 100 unique activations only as download interest;
- keep browser measurement out of the macOS app—Keep3 has no app telemetry,
  accounts, analytics SDK, installation tracking, active-use tracking, or
  retention tracking;
- publish a privacy disclosure covering fields collected, processor, purpose,
  retention, deletion, cookies or local storage, and any cross-border transfer;
  and
- expose a voluntary external donation path that never changes product access.

A donation failure affects only the donation flow. It must not disable a
download, create a license state, hide support, or change treatment for donors
and non-donors. Donation-provider privacy and receipts belong to the website
application and provider, never to Keep3's local content store.

## Trust-state copy

Copy is derived from the verified manifest `trustState`, not from funding
totals or a manually edited page.

### Unsigned

Use explicit copy such as: “This Keep3 release is unsigned and not notarized by
Apple. Verify the published SHA-256. macOS may require Control-click → Open and
confirmation in Privacy & Security.” Never claim Apple verification and never
recommend automatic quarantine removal or an `xattr` command.

### Developer ID

Use “Developer ID signed and notarized” only after the release ledger contains
Developer ID signature, notarization, stapling, Gatekeeper, nested-helper, and
cross-channel evidence and the signed manifest says `developer-id`.

The funding trigger—cleared cumulative donations covering the approved USD 99
first-year Apple Developer Program fee—starts separate Developer ID and
notarization work. It does not block implementation or publication preparation
for an unsigned release. After the first verified `developer-id` stable release,
official GitHub, Homebrew, and Sparkle channels must never return to unsigned;
credential or renewal failure freezes new releases instead.

## Identity and migration invariants

The signing transition and every website revision must preserve:

- app bundle identifier `dev.keep3.Keep3`;
- helper identifier and XPC service name `dev.keep3.Keep3MediaService`;
- local state path `~/Library/Application Support/Keep3/state.json`;
- the standard `UserDefaults` application domain `dev.keep3.Keep3` and existing
  preference keys;
- Sparkle feed `https://taobaorun.github.io/keep3/release-channel/appcast.xml`;
- permanent Sparkle `SUPublicEDKey` and its offline backup;
- permanent metadata public key, key identifier, and out-of-band website
  handoff; and
- semantic `MARKETING_VERSION` plus strictly increasing numeric
  `CURRENT_PROJECT_VERSION` ordering.

Changing any invariant requires an explicit migration and recovery plan. A
routine signing or website deployment is not authority to reset identity,
trust roots, preferences, persistence, or version order.

## Website launch acceptance

Before the standalone website becomes the primary entry point, verify with
production fixtures that it rejects tampering, expiration, rollback, unknown
schemas, wrong origins, wrong repositories, key mismatches, inconsistent
channels, and `Compromised` status. Also verify that download navigation works
when analytics and the donation provider are unavailable. Public readiness is
tracked in `docs/verification/keep3-distribution.md`.
