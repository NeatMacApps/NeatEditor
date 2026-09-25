# Changelog

All notable changes to this project will be documented in this file.

The format loosely follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Unreleased

### Added

- Pinned window follows mouse to focus: when Always on Top is enabled, moving the mouse over the window activates it and takes key focus, so typing can continue immediately when switching between tiled apps. No hover delay; suppressed while dragging/resizing, when a sheet or modal is open, or when the mouse buttons are pressed.

## 1.0.3 - 2026-09-23

### Added

- Drag-install dmg (`NeatEditor-<tag>-macOS-universal.dmg`, app plus `Applications` symlink) published alongside the zip on every release; `SHA256SUMS.txt` now covers both.

## 1.0.2 - 2026-09-23

### Fixed

- Editor no longer loses unrelated lines after cut/paste or rapid typing: the AppKit–SwiftUI text bridge only pushes external or tab-switch changes, lazy file loads cannot overwrite edits in flight, and switching tabs flushes IME composition plus clears the shared undo stack.
- Search highlights now follow text edits and re-apply (without jumping) after tab switches and file loads.

### Removed

- Command+scroll / trackpad gesture font zoom. Font size is adjusted only via `Command + =` / `Command + -` (and the View menu).

### Added

- `NeatEditorTests` unit test target covering the text-sync contract, document persistence, and font-size preferences.

## 1.0.0 - 2026-04-03

### Added

- Initial public-facing repository documentation, including license and contribution guide.
- GitHub Actions release workflow for tag-driven macOS build artifacts.
- Simplified Chinese companion README for bilingual project documentation.

### Changed

- README reorganized into an English-first public project homepage.
- App bundle version metadata is now wired through Xcode settings for the 1.0.0 release.
