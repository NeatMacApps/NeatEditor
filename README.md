# NeatEditor

<p align="center">
  <img src="./docs/images/app-icon.png" width="128" height="128" alt="NeatEditor app icon">
</p>

[![Platform](https://img.shields.io/badge/platform-macOS%2015%2B-1f6feb)](https://developer.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6-orange)](https://www.swift.org/)
[![UI](https://img.shields.io/badge/UI-SwiftUI%20%2B%20AppKit-0a7ea4)](https://developer.apple.com/xcode/swiftui/)
[![Project](https://img.shields.io/badge/Project-XcodeGen-6f42c1)](https://github.com/yonaskolb/XcodeGen)
[![License](https://img.shields.io/badge/License-MIT-green)](./LICENSE)

> A minimal, fast-launching macOS plain text editor built with SwiftUI and AppKit for distraction-free writing, native desktop interactions, and efficient multi-tab editing.

**Languages:** [English](./README.md) | [Simplified Chinese](./README.zh-CN.md) | [Japanese](./README.ja.md) | [Korean](./README.ko.md) | [Spanish](./README.es.md) | [French](./README.fr.md) | [German](./README.de.md)

## Screenshot

<p align="center">
  <img src="./docs/images/neateditor-main-window.png" alt="NeatEditor screenshot showing the main writing workspace on macOS" width="1201" />
</p>

## Why NeatEditor

NeatEditor is built around a simple goal: reduce interface noise and keep your attention on the text.

- Fast launch: avoid unnecessary blocking work on the app startup path.
- Space-first UI: keep the editor surface front and center instead of surrounding it with chrome.
- Native macOS behavior: preserve familiar title bar, menus, shortcuts, and window interactions.
- Plain-text focus: ideal for notes, drafts, scratch writing, and lightweight editing.

## Highlights

- Multi-tab plain text editing with a ready-to-use document on launch.
- Low-latency tab selection, closing, and in-place renaming.
- Open local text files through Finder, drag and drop, or pasted file URLs.
- Built-in line numbers, native find, undo, IME composition handling, and `Command +/-` zooming.
- Debounced autosave plus save-on-tab-switch and save-on-app-deactivation behavior.
- Pin-to-top window support and native title bar double-click zoom behavior.
- Disk-backed rename behavior that preserves editable file extensions.
- Blank content never overwrites existing files by design.

## Main Shortcuts

| Shortcut | Action |
| --- | --- |
| `Command + N` | Create a new document. |
| `Command + T` | Open another new tab. |
| `Command + O` | Open one or more local text files. |
| `Command + S` | Save the current tab immediately. |
| `Command + W` | Save and close the current tab. |
| `Shift + Command + T` | Reopen the most recently closed tab. |
| `Command + F` | Show the inline find bar for the current editor. |
| `Command + =` or `Command + +` | Zoom in the editor text. |
| `Command + -` | Zoom out the editor text. |
| `Command + ,` | Open Settings. |
| `Shift + Return` | Insert a new line at the end of the current line. |

Standard macOS text shortcuts such as `Command + Z`, `Command + X`, `Command + C`, and `Command + V` also work through the native text system.

## Current Status

NeatEditor is ready to use as a lightweight macOS plain text editor; the current marketing version is `1.0.4` (build `3`).

- Platform target: macOS 15.0+
- Stack: Swift 6, SwiftUI, AppKit bridge, Observation, XcodeGen
- Validation today: `xcodebuild ... test` (18 unit tests: editor text sync, document persistence, preferences), build verification, and manual testing
- Distribution today: Developer ID-signed + notarized DMG built locally via `scripts/publish-release.sh` (see [RELEASING.md](./RELEASING.md))
- Scope today: plain text workflow, no rich text, plugins, or cross-platform support

## Quick Start

### Install (macOS)

1. Download the latest signed `NeatEditor-<version>.dmg` from [GitHub Releases](https://github.com/NeatEditor/NeatEditor/releases/latest) (optionally verify with `SHA256SUMS.txt`).
2. Open the DMG and drag `NeatEditor.app` to `Applications`.
3. First launch:

```bash
open -a NeatEditor
```

The app opens with a ready-to-use document; press `Command + N` for a new one.

### Supported Platforms

- Supported: macOS 15.0+ (Apple silicon and Intel, universal build).
- Not supported: Linux and Windows. The app depends on AppKit and macOS-only code signing/notarization, so it neither builds nor runs there and no packages are provided.

### Requirements (Building From Source)

- macOS 15.0+
- Xcode 16.2+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) 2.44+

### Clone And Open

```bash
git clone <repo-url>
cd NeatEditor
xcodegen generate
open NeatEditor.xcodeproj
```

### Build From Terminal

```bash
xcodebuild -project "NeatEditor.xcodeproj" \
  -scheme "NeatEditor" \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData \
  build
```

## Development Notes

- `project.yml` is the source of truth for the project structure.
- Run `xcodegen generate` after adding or removing source files.
- `NeatEditorTests` covers editor text sync, document persistence, and preferences (18 tests). Run them with:

```bash
xcodebuild -project "NeatEditor.xcodeproj" \
  -scheme "NeatEditor" \
  -configuration Debug \
  -destination 'platform=macOS' \
  test
```
- For behavior changes, prefer validating with the built app rather than relying on previews alone.

## Releases

Public installs come from the signed local release route, not from CI:

- The maintainer builds the DMG + Sparkle ZIP on the signing Mac with `scripts/publish-release.sh` (Developer ID-signed, notarized, stapled).
- Each public Release holds the signed DMG (first install), the signed Sparkle update ZIP (in-app updates), and `SHA256SUMS.txt`.
- The tag-triggered GitHub Actions workflow only uploads unsigned build placeholders; never install those as a release.

The full route, requirements, and coordinator handoff are documented in [RELEASING.md](./RELEASING.md).

## Project Structure

```text
NeatEditor/
├── docs/
│   └── images/
│       └── neateditor-main-window.png
├── project.yml
├── README.md
├── CONTRIBUTING.md
├── CHANGELOG.md
└── Sources/
    └── NeatEditor/
        ├── App/             # App entry point, commands, and external file opening
        ├── Features/
        │   ├── Editor/      # AppKit bridge editor, line numbers, and zoom
        │   └── Workspace/   # Tab strip, workspace state, and main UI
        ├── Services/        # Autosave and document persistence
        ├── SharedUI/        # Shared styling and title bar helper views
        ├── Resources/       # Localization resources
        └── Assets.xcassets  # Image assets
```

## Repository Docs

- [README.ja.md](./README.ja.md): Japanese overview
- [README.ko.md](./README.ko.md): Korean overview
- [README.es.md](./README.es.md): Spanish overview
- [README.fr.md](./README.fr.md): French overview
- [README.de.md](./README.de.md): German overview
- [README.zh-CN.md](./README.zh-CN.md): Simplified Chinese overview
- [CONTRIBUTING.md](./CONTRIBUTING.md): development environment and contribution notes
- [CHANGELOG.md](./CHANGELOG.md): project release history
- [RELEASING.md](./RELEASING.md): tag-driven GitHub Release workflow
- [TabStripGestures.md](./TabStripGestures.md): design notes for tab click and rename interactions

## Known Gaps

- Add a general CI workflow for pushes and pull requests (today only the unsigned tag workflow exists).

## Contributing

Issues, suggestions, and pull requests are welcome. Please read [CONTRIBUTING.md](./CONTRIBUTING.md) first.

## License

NeatEditor is released under the [MIT License](./LICENSE).
