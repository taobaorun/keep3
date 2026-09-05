# Changelog

All notable user-facing changes to Keep3 are recorded here.

## [1.0.5] - 2026-09-05

### Added

- Priorities can be archived without being permanently deleted, reviewed later
  in a read-only History destination, and exported with active items as Markdown.

### Changed

- Refined top-surface motion, press feedback, content-proportionate expansion,
  keyboard accessibility, Settings previews, and Reduce Motion behavior.
- Unified the main-window tab layout, sidebar selection treatments, input focus,
  and restrained Keep3 brand accents while keeping action buttons neutral.

### Fixed

- Compact priority titles now receive a bounded text region, tighten gently, and
  use a tail ellipsis instead of being clipped at the surface edge.

## [1.0.4] - 2026-08-13

### Changed

- Refined the Calendar surface around the physical notch with balanced spacing,
  clearer event-title hierarchy, and a quieter ongoing-event treatment.

### Fixed

- The standard Settings command and Command-comma shortcut now open Keep3's
  populated settings destination instead of an empty system Settings window.

## [1.0.3] - 2026-08-12

### Fixed

- Restored Calendar authorization in hardened distribution builds so enabling
  Calendar can show upcoming events after the user grants access.

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
