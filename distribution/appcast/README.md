# Keep3 release appcast

`appcast.xml` is generated from a validated immutable release manifest. It is
not edited by hand and is not activated until GitHub Releases and the
maintainer-owned Homebrew tap already expose the same canonical DMG.

The public feed is fixed at:

`https://taobaorun.github.io/keep3/release-channel/appcast.xml`

Every enclosure must use the immutable tagged GitHub asset URL, the numeric
build version, and the Sparkle EdDSA signature recorded in the corresponding
manifest. Because Keep3 requires a signed feed, protected promotion also signs
the completed appcast XML with the same permanent Sparkle key and verifies that
signature before publication. Generated appcasts belong under
`.build/release/` or the protected release-channel staging area; they are not
committed here.

The app embeds Keep3's permanent Sparkle EdDSA public key. Its private key is
kept outside the repository in the protected release environment, the
maintainer Keychain, and encrypted recovery backups. Production validation
continues to reject Sparkle's documented fixture key.
