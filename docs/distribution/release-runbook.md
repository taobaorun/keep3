# Keep3 release runbook

Keep3 promotion is a forward-only state machine around one canonical DMG. The
tag job has no publication credentials: it builds once, records the SHA-256,
source commit, timestamps, and build toolchain, obtains GitHub attestations for
both the DMG and receipt, and uploads that private candidate bundle. It must
never rebuild a candidate for the same tag. Promotion reuses those attested
values so a runner upgrade cannot change signed manifest bytes during a retry.
The candidate is eligible for promotion for 30 days. That private limit is not
copied into stable release discovery: only operational status expires.

## Preconditions

1. Create `vMAJOR.MINOR.PATCH` from protected `main`; the numeric app build must
   be above the signed current document.
2. Wait for `Build release candidate` to finish and record its run ID.
3. Create the `gh-pages` branch and configure it as the Pages source; create the
   `taobaorun/homebrew-keep3` tap with a protected `main` branch.
4. Configure the approved `release-production` environment with
   `KEEP3_SPARKLE_PRIVATE_KEY`, `KEEP3_RELEASE_METADATA_PRIVATE_KEY`, and a
   least-privilege `KEEP3_TAP_TOKEN`. Confirm the checked-in metadata and
   Sparkle public keys match the backed-up permanent private roots in a
   reviewed build before creating its tag.
5. Review native, release-contract, GPL/source, media-provider, Sparkle-key,
   and website-handoff contract gates. The separately owned website can launch
   later and is not required to activate the canonical release channels.
6. Confirm the signed operational status is not `Compromised`.
7. Approve the `release-production` environment only after the credential-free
   preflight verifies reachability, digest, attestation, signature, sequence,
   and strict build monotonicity.

## Promotion order

The protected job downloads the attested bytes again and repeats preflight
before reading keys. It extracts the app from the attested DMG, signs the DMG
for Sparkle, derives and signs every metadata projection using the attested
timestamps/toolchain, runs `validate-release.sh`, then stages a draft release
and tap pull request without making either a current update channel.

Public writes then occur exactly once in this order:

1. mark the verified GitHub draft release stable;
2. merge the verified cask pull request in the maintainer-owned tap;
3. publish the immutable manifest and activate the Sparkle appcast;
4. run read-only cross-channel probes for asset SHA, manifest, cask, and feed;
5. publish signed `current-release.json` and signed `Converged` status in one
   Pages commit only after every probe agrees.

Immediately after step 1, publish signed `Promoting`. Any later failure publishes
signed `Degraded`, retains the prior current document (or no current on the
first launch), and stops. The appcast never moves before GitHub and tap pass.

## Retry and recovery

Re-run promotion with the same candidate run ID. The journal pins the original
digest; existing assets must match byte-for-byte and are reused. The scripts
refuse replacement assets, duplicate uploads, tag mutation, build downgrade, or
advancing a later channel past an incomplete earlier step. Recover forward from
an outage. If published bytes are wrong, issue a higher semantic version and
numeric build—never replace tagged bytes or move current backward.

The unsigned cask keeps quarantine enabled and gives truthful Control-click/Open
guidance. It must never execute `xattr`, use `sha256 :no_check`, or claim Apple
notarization. Developer ID/notarization remains the post-funding transition.

## Refresh release status

`.github/workflows/refresh-release-status.yml` runs monthly and may also be
dispatched manually through the protected `release-production` environment. It
verifies the signed `Converged` status and stable current document, advances the
status sequence, and signs a new 90-day operational freshness window. It does
not rewrite current discovery, an immutable manifest, the appcast, cask, or
release asset. A non-Converged status must be investigated or recovered through
the promotion/incident process, never hidden by freshness renewal.

## Commands

- Local state-machine verification: `scripts/tests/channel-promotion-tests.sh`
- Candidate contract: `scripts/tests/release-contract-tests.sh`
- Status freshness: `scripts/release/refresh-release-status.sh --help`
- Read-only convergence: `scripts/release/probe-channels.sh --help`
- Resumable publication: `scripts/release/publish-release-channel.sh --help`

No release operation writes to the standalone website application.
