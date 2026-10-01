# NeatEditor

<p align="center">
  <img src="./docs/images/app-icon.png" width="128" height="128" alt="NeatEditor-App-Symbol">
</p>

[![Platform](https://img.shields.io/badge/platform-macOS%2015%2B-1f6feb)](https://developer.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6-orange)](https://www.swift.org/)
[![UI](https://img.shields.io/badge/UI-SwiftUI%20%2B%20AppKit-0a7ea4)](https://developer.apple.com/xcode/swiftui/)
[![Project](https://img.shields.io/badge/Project-XcodeGen-6f42c1)](https://github.com/yonaskolb/XcodeGen)
[![License](https://img.shields.io/badge/License-MIT-green)](./LICENSE)

> Ein minimalistischer, schnell startender Plain-Text-Editor für macOS, gebaut mit SwiftUI und AppKit für ablenkungsfreies Schreiben, native Desktop-Interaktionen und effizientes Arbeiten mit mehreren Tabs.

**Sprachen:** [English](./README.md) | [简体中文](./README.zh-CN.md) | [日本語](./README.ja.md) | [한국어](./README.ko.md) | [Español](./README.es.md) | [Français](./README.fr.md) | [Deutsch](./README.de.md)

## Screenshot

<p align="center">
  <img src="./docs/images/neateditor-main-window.png" alt="Screenshot des NeatEditor-Hauptfensters" width="1201" />
</p>

## Warum NeatEditor

NeatEditor folgt einem einfachen Ziel: weniger UI-Rauschen und mehr Fokus auf den eigentlichen Text.

- Schneller Start: vermeidet unnötige blockierende Arbeit auf dem Startup-Pfad.
- Raumorientierte UI: die Editorfläche steht im Mittelpunkt statt zusätzlicher Oberfläche.
- Natives macOS-Verhalten: Titelleiste, Menüs, Shortcuts und Fensterinteraktionen bleiben vertraut.
- Fokus auf Plain Text: ideal für Notizen, Entwürfe, schnelle Texte und leichtes Editieren.

## Highlights

- Mehrtabbige Plain-Text-Bearbeitung mit sofort nutzbarem Dokument beim Start.
- Niedrige Latenz beim Tab-Wechsel, Schließen und direkten Umbenennen.
- Öffnet lokale Textdateien über Finder, Drag-and-drop oder eingefügte Datei-URLs.
- Eingebaute Zeilennummern, native Suche, Undo, IME-Unterstützung und Zoom mit `Command +/-`.
- Autosave mit 2-Sekunden-Debounce sowie Speichern beim Tab-Wechsel und beim Deaktivieren der App.
- Fenster anheften, damit es im Vordergrund bleibt, plus natives Zoom-Verhalten per Doppelklick in die Titelleiste.
- Umbenennen gespeicherter Dokumente synchronisiert den Dateinamen auf der Festplatte und erhält bearbeitbare Endungen.
- Leerer Inhalt überschreibt vorhandene Dateien absichtlich nicht.

## Wichtige Kurzbefehle

| Kurzbefehl | Aktion |
| --- | --- |
| `Command + N` | Erstellt ein neues Dokument. |
| `Command + T` | Öffnet einen weiteren neuen Tab. |
| `Command + O` | Öffnet eine oder mehrere lokale Textdateien. |
| `Command + S` | Speichert den aktuellen Tab sofort. |
| `Command + W` | Speichert und schließt den aktuellen Tab. |
| `Shift + Command + T` | Öffnet den zuletzt geschlossenen Tab erneut. |
| `Command + F` | Zeigt die integrierte Suchleiste des aktuellen Editors an. |
| `Command + =` oder `Command + +` | Vergrößert den Editor-Text. |
| `Command + -` | Verkleinert den Editor-Text. |
| `Command + ,` | Öffnet die Einstellungen. |
| `Shift + Return` | Fügt am Ende der aktuellen Zeile eine neue Zeile ein. |

Native macOS-Textkurzbefehle wie `Command + Z`, `Command + X`, `Command + C` und `Command + V` funktionieren ebenfalls über das native Textsystem.

## Aktueller Stand

NeatEditor ist als leichter Plain-Text-Editor für macOS einsatzbereit und wird als `1.0.0` veröffentlicht.

- Zielplattform: macOS 15.0+
- Stack: Swift 6, SwiftUI, AppKit bridge, Observation, XcodeGen
- Aktuelle Validierung: `xcodebuild ... test` (Unit-Tests: Text-Sync, Persistenz, Autosave-Planung, Workspace-Fehlerpfade, native IME-Commits, Schriftgrößen-Einstellungen), Build-Prüfung und manuelle Tests
- Aktueller Umfang: Plain-Text-Workflow, kein Rich Text, keine Plugins, keine plattformübergreifende Unterstützung

## Schnellstart

### Voraussetzungen

- macOS 15.0+
- Xcode 16.2+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) 2.44+

### Klonen und öffnen

```bash
git clone <repo-url>
cd NeatEditor
xcodegen generate
open NeatEditor.xcodeproj
```

### Build im Terminal

```bash
xcodebuild -project "NeatEditor.xcodeproj" \
  -scheme "NeatEditor" \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData \
  build
```

## Entwicklungshinweise

- `project.yml` ist die Quelle der Wahrheit für die Projektstruktur.
- Führe `xcodegen generate` nach dem Hinzufügen oder Entfernen von Quelldateien aus.
- `NeatEditorTests` deckt Text-Sync, Persistenz, Autosave-Planung, Workspace-Fehlerpfade, native IME-Commits und Schriftgrößen-Einstellungen ab; ausführen mit `xcodebuild ... test` (siehe englisches README).
- Bei Verhaltensänderungen sollte möglichst mit der gebauten App statt nur mit Previews validiert werden.

## Releases

Dieses Repository veröffentlicht über signierte lokale Releases, nicht über CI.

- Der Maintainer baut DMG + Sparkle-ZIP lokal mit `scripts/publish-release.sh` (Developer-ID-signiert, notarisiert; erst nach Upload plus Rücklesen aus dem Entwurf veröffentlicht).
- Jede signierte öffentliche Release enthält das signierte DMG (Erstinstallation), das signierte Sparkle-ZIP (In-App-Updates) und `SHA256SUMS.txt`, mit zweisprachigen Hinweisen aus dem `CHANGELOG.md`-Eintrag der Version.
- Der tagbasierte GitHub-Actions-Workflow baut nur zur Validierung und behält unsignierte Pakete als private Workflow-Artefakte; diese nicht als Release installieren.

Installationsweg: Auf der Releases-Seite eine Version wählen, deren Hinweise Developer-ID-Signierung + Notarisierung nennen — nur signierte Dateien installieren (ältere `*-macOS-universal.*`-Dateien, z. B. unter v1.0.3, sind unsignierte CI-Platzhalter). Nach `Applications` ziehen, dann `open -a NeatEditor`. Nur macOS 15.0+ wird unterstützt.

Details stehen in [RELEASING.md](./RELEASING.md).

## Repository-Dokumentation

- [README.md](./README.md): englische Übersicht
- [README.zh-CN.md](./README.zh-CN.md): chinesische Übersicht
- [README.ja.md](./README.ja.md): japanische Übersicht
- [README.ko.md](./README.ko.md): koreanische Übersicht
- [README.es.md](./README.es.md): spanische Übersicht
- [README.fr.md](./README.fr.md): französische Übersicht
- [CONTRIBUTING.md](./CONTRIBUTING.md): Entwicklungsumgebung und Beitragsinfos
- [CHANGELOG.md](./CHANGELOG.md): Release-Historie
- [RELEASING.md](./RELEASING.md): GitHub-Release-Workflow
- [TabStripGestures.md](./TabStripGestures.md): Designnotizen zu Tab-Gesten

## Bekannte Lücken

- Einen allgemeinen CI-Workflow für Pushes und Pull Requests hinzufügen (derzeit nur der Tag-Validierungs-Workflow).

## Mitwirken

Issues, Vorschläge und Pull Requests sind willkommen. Bitte zuerst [CONTRIBUTING.md](./CONTRIBUTING.md) lesen.

## Lizenz

NeatEditor wird unter der [MIT License](./LICENSE) veröffentlicht.
