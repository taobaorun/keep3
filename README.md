# Keep3

Keep3 is a quiet, native macOS event surface for keeping up to three priorities
in sight while yielding to active media and an explicitly enabled local
Calendar view.

## Requirements

- macOS 14 or later
- Xcode 16.4 or later

## Build from source

```sh
xcodebuild build \
  -project Keep3.xcodeproj \
  -scheme Keep3 \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath .build/DerivedData \
  CODE_SIGNING_ALLOWED=NO
```

The canonical app version is `MARKETING_VERSION` and its strictly increasing
numeric build is `CURRENT_PROJECT_VERSION` in the Xcode project. A published
binary must link to its exact source tag; check out that tag to inspect or
rebuild the corresponding source.

## Distribution

Keep3 is distributed directly for free. Every user receives the complete
application: there is no trial expiry, license key, subscription, payment gate,
or donor-only functionality. Voluntary donations do not change the software.

Release artifacts, checksums, update metadata, and custom Homebrew tap details
will be documented with each release. The initial direct-distribution builds
may be unsigned until the documented Apple Developer funding gate is met.

## License

Copyright © 2026 taobaorun.

Keep3 is free software licensed under the GNU General Public License,
GPL-3.0-only. See [LICENSE](LICENSE). Third-party attributions are in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
