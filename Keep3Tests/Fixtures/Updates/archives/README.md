# Archive fixture policy

No update archive or private release key is checked in.

`scripts/tests/sparkle-integration-tests.sh` creates a temporary archive,
signs it with Sparkle's public TestApplication fixture key, verifies the
original bytes, then alters the archive and verifies that Sparkle rejects it.
The temporary directory is removed on exit.

U3 packaging replaces this synthetic archive with the canonical built-once
Keep3 DMG. The same `sign_update --verify` boundary must pass before that DMG
can be referenced by an appcast.
