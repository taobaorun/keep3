# Sparkle update fixtures

These fixtures exercise Keep3's update contract without contacting the
production feed.

- `appcasts/no-update.xml` has the installed build (`1`) and must not advance
  the app.
- `appcasts/valid-update.xml` has a strictly higher build (`2`) and a
  well-formed EdDSA enclosure-signature field.
- `appcasts/invalid-signature.xml` has the same candidate version but an
  intentionally invalid signature.
- `archives/README.md` describes the temporary archive produced by the
  integration test.

The XML files are templates, not publishable appcasts. The integration script
uses Sparkle 2.9.4's own `sign_update` executable to sign temporary copies and
to prove that tampering fails verification. Its key material is Sparkle's
publicly documented TestApplication fixture key. It is not a secret and must
never be used for a Keep3 release.

The integration test alone uses the matching upstream fixture public key:

```text
eRFPLZuNM6m8bltmtpPX4fzKbufI1z6rKJHtgIIsllk=
```

Release validation must reject this exact value in a built Keep3 app. The
production `KEEP3_SPARKLE_PUBLIC_ED_KEY` is a separate permanent public root;
no production private key belongs in this repository.
