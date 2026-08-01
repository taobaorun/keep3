# Keep3 update-key incident runbook

Use this procedure for suspected theft, disclosure, unauthorized use, or loss of
either the Sparkle archive key or the Ed25519 release-metadata key.

## Freeze first

1. Stop all candidate and promotion jobs and revoke channel automation tokens.
2. Publish a signed `Compromised` operational-status document with the last
   trusted metadata key when that key is still controlled. If it is not, freeze
   the channel through repository and environment protection immediately.
3. Do not publish an appcast, cask, GitHub release, immutable manifest, or
   current document. `publish-release-channel.sh` treats `Compromised` as a
   hard preflight failure on every retry.
4. Preserve the prior stable current release and evidence: workflow run IDs,
   audit logs, signatures, hashes, affected tags, and credential access history.

## Contain and communicate

Revoke GitHub, tap, channel, and affected signing credentials. Open a GitHub
security advisory describing affected versions and the manual recovery path.
Do not silently rotate a trust root: installed clients pin the old Sparkle key
and metadata consumers pin the checked-in public key.

## Recover through a manual trust-root release

Generate replacement keys offline, retain encrypted backups, and update the
application and external consumer to the new public roots in a higher-version
manual recovery build. Before signed distribution exists, publish explicit
unsigned-install verification. After Developer ID enrollment, the recovery
build must also pass signing, notarization, stapling, Gatekeeper, nested-code,
bundle-identity, permission, and continuity gates.

Old clients must reject content signed only by the replacement key until the
user installs that manual recovery build. Resume automatic updates only after
recovery adoption, channel credentials, immutable artifacts, source links, and
all cross-channel probes are verified. Publish a new signed `Converged` status;
never rewrite or reuse a compromised tag.
