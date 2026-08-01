# Keep3 release appcast

`appcast.xml` is generated from a validated immutable release manifest. It is
not edited by hand and is not activated until GitHub Releases and the
maintainer-owned Homebrew tap already expose the same canonical DMG.

The public feed is fixed at:

`https://taobaorun.github.io/keep3/release-channel/appcast.xml`

Every enclosure must use the immutable tagged GitHub asset URL, the numeric
build version, and the Sparkle EdDSA signature recorded in the corresponding
manifest. Generated appcasts belong under `.build/release/` or the protected
release-channel staging area; they are not committed here.

The app currently embeds Sparkle's documented fixture key. Production
validation intentionally rejects that key. Provision and back up the permanent
Sparkle EdDSA key before any public appcast is promoted.
