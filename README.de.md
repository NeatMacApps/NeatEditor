# NeatEditor

<p align="center">
  <img src="./docs/images/app-icon-rounded.png" width="128" height="128" alt="NeatEditor-App-Symbol">
</p>

[![Platform](https://img.shields.io/badge/platform-macOS%2026%2B-1f6feb)](https://developer.apple.com/macos/)
[![License](https://img.shields.io/badge/License-MIT-green)](./LICENSE)

> Ein nativer Klartexteditor für macOS.

**Sprachen:** [English](./README.md) | [简体中文](./README.zh-CN.md) | [日本語](./README.ja.md) | [한국어](./README.ko.md) | [Español](./README.es.md) | [Français](./README.fr.md) | [Deutsch](./README.de.md)

## Screenshot

<p align="center">
  <img src="./docs/images/neateditor-main-window.png" alt="Screenshot des NeatEditor-Hauptfensters" width="1120" />
</p>

## Installation

**macOS 26.0+ · Apple silicon und Intel.** Nur macOS; keine Linux- oder Windows-Version.

```bash
brew install --cask x0c/tap/neateditor
```

Oder [das neueste signierte und notarisierte DMG herunterladen](https://github.com/NeatMacApps/NeatEditor/releases/latest), öffnen und `NeatEditor.app` nach `Applications` ziehen.

Nach dem Start öffnest du mit `Command + O` eine Datei oder erstellst mit `Command + N` ein neues Dokument.

## Warum NeatEditor

Für Notizen, Entwürfe und schnelle Änderungen an Textdateien.

## Highlights

- **Tabs:** wechseln, schließen, direkt umbenennen und den zuletzt geschlossenen Tab wieder öffnen.
- **Lokale Dateien:** über Finder, Drag-and-drop oder eingefügte Datei-URLs öffnen; das Umbenennen gespeicherter Dokumente ändert auch den Dateinamen auf dem Datenträger.
- **Native Bearbeitung:** Zeilennummern, Suche, Rückgängig, IME-Eingabe und Textzoom mit `Command +/-`.
- **Automatisches Speichern:** nach 2 Sekunden Eingabepause, beim Tab-Wechsel und wenn die App inaktiv wird. Schreibvorgänge erfolgen der Reihe nach.
- **Externe Änderungen:** Änderungen durch einen anderen Editor, ein Skript oder einen Coding-Agenten übernehmen. Unveränderte Puffer werden neu geladen, unabhängige Änderungen vorsichtig zusammengeführt; bei erkannten Konflikten bleiben beide Versionen erhalten.
- **Schutz bei leerem Inhalt:** leerer Text oder reine Leerraumzeichen überschreiben keine vorhandene Datei. Das Leeren des Editors leert daher nicht die Datei auf dem Datenträger.
- **Dokumentordner:** standardmäßig `~/Documents`, änderbar unter Einstellungen → Editor → Dokumentordner. Neue Dokumente werden im gewählten Ordner gespeichert.
- **Im Blick behalten:** Fenster im Vordergrund anheften und native Menüs und Titelleistenaktionen nutzen.

Der Schutz bei gleichzeitiger Bearbeitung verhindert keine Schreibzugriffe anderer Programme. Wichtige Dateien solltest du zusätzlich sichern.

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

<details>
<summary>Aus dem Quellcode bauen (Xcode)</summary>

Benötigt macOS 26.0+, Xcode 26.0+ und [XcodeGen](https://github.com/yonaskolb/XcodeGen) 2.44+.

```bash
git clone https://github.com/NeatMacApps/NeatEditor.git
cd NeatEditor
xcodegen generate
open NeatEditor.xcodeproj
```

```bash
xcodebuild -project "NeatEditor.xcodeproj" \
  -scheme "NeatEditor" \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData \
  build
```

Tests und Entwicklung sind in [CONTRIBUTING.md](CONTRIBUTING.md) beschrieben.

</details>

## Dokumentation

- [Mitwirken und Tests](CONTRIBUTING.md)
- [Versionsverlauf](CHANGELOG.md)

Issues, Vorschläge und Pull Requests sind willkommen.

## Lizenz

NeatEditor wird unter der [MIT License](LICENSE) veröffentlicht.

## Verwandte Werkzeuge

| Werkzeug | Beschreibung |
|---|---|
| [NeatPaste](https://github.com/NeatMacApps/NeatPaste) | macOS-Zwischenablageverlauf in der Menüleiste. |
| [NeatWebApp](https://github.com/NeatMacApps/NeatWebApp) | Websites als eigene macOS-Apps mit Notch-Launcher öffnen. |
| [HandySwitch](https://github.com/x0c/HandySwitch) | Dunkelmodus umschalten und Ruhezustand über die Menüleiste verhindern. |
| [MacResourceMonitor](https://github.com/x0c/MacResourceMonitor) | CPU-intensive Prozesse über die Menüleiste finden. |
| [Corral](https://github.com/corral-dev/corral) | Coding-Agent-Sitzungen im Terminal verwalten und auf Mac oder iPhone fortsetzen. |
