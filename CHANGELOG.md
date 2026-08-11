# Changelog

All notable user-facing changes to Keep3 are recorded here.

## [1.0.2] - 2026-08-12

### Changed

- Refined the Calendar surface with a clearer primary-event card, calmer
  secondary-event timeline, and consistent hierarchy between compact and
  expanded presentations.
- Grouped upcoming events by today and tomorrow, and added more polished
  loading, empty, permission, and refresh-failure states.
- Kept event timing intentionally static so the surface stays readable without
  introducing a distracting live countdown.

## [1.0.1] - 2026-08-03

### Fixed

- Homebrew now prints exact first-launch steps for unsigned builds while keeping
  macOS quarantine and Gatekeeper protections enabled.
- The DMG now includes a standalone first-launch guide, and the product website
  presents the same guidance before users attempt to open Keep3.

## [1.0.0] - 2026-08-01

### Added

- A native macOS surface for keeping up to three priorities visible around the
  menu bar notch.
- Media playback status, artwork, progress, and supported playback controls.
- An explicitly enabled local Calendar view that keeps event data on-device.
- Direct DMG packaging, Sparkle update metadata, and Homebrew channel
  projections for GPL-3.0-only distribution.

### Fixed

- Compact artwork now flips in place when tracks change instead of
  intermittently swinging around the notch.
- Media player discovery continues to work with the private MediaRemote helper
  compatibility boundary used by Keep3.
