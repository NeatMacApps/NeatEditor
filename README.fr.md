# NeatEditor

<p align="center">
  <img src="./docs/images/app-icon.png" width="128" height="128" alt="Icône de NeatEditor">
</p>

[![Platform](https://img.shields.io/badge/platform-macOS%2026%2B-1f6feb)](https://developer.apple.com/macos/)
[![License](https://img.shields.io/badge/License-MIT-green)](./LICENSE)

> Un éditeur de texte brut natif pour macOS.

**Langues :** [English](./README.md) | [简体中文](./README.zh-CN.md) | [日本語](./README.ja.md) | [한국어](./README.ko.md) | [Español](./README.es.md) | [Français](./README.fr.md) | [Deutsch](./README.de.md)

## Capture d'écran

<p align="center">
  <img src="./docs/images/neateditor-main-window.png" alt="Capture de l’espace de travail principal de NeatEditor" width="1120" />
</p>

## Installation

**macOS 26.0+ · Apple silicon et Intel.** Uniquement macOS ; aucune version Linux ou Windows.

```bash
brew install --cask x0c/tap/neateditor
```

Ou [téléchargez le dernier DMG signé et notarié](https://github.com/NeatMacApps/NeatEditor/releases/latest), ouvrez-le et glissez `NeatEditor.app` dans `Applications`.

Au lancement, utilisez `Command + O` pour ouvrir un fichier ou `Command + N` pour créer un document.

## Pourquoi NeatEditor

Pour les notes, les brouillons et les petites modifications de fichiers texte.

## Points forts

- **Onglets :** changez d’onglet, fermez, renommez sur place et rouvrez le dernier onglet fermé.
- **Fichiers locaux :** ouvrez depuis le Finder, par glisser-déposer ou collage d’URL de fichier ; renommer un document enregistré renomme aussi le fichier sur disque.
- **Édition native :** numéros de ligne, recherche, annulation, composition IME et zoom du texte avec `Command +/-`.
- **Sauvegarde automatique :** après 2 secondes sans saisie, au changement d’onglet et lorsque l’app devient inactive. Les écritures sont ordonnées.
- **Modifications externes :** gérez les modifications d’un autre éditeur, d’un script ou d’un agent de programmation. Les tampons non modifiés sont rechargés, les modifications indépendantes fusionnées prudemment, et les conflits détectés conservent les deux versions.
- **Protection du contenu vide :** un texte vide ou composé uniquement d’espaces blancs n’écrase pas un fichier existant. Vider l’éditeur ne vide donc pas le fichier sur disque.
- **Dossier de documents :** `~/Documents` par défaut, modifiable dans Réglages → Éditeur → Dossier de documents. Les nouveaux documents sont enregistrés dans le dossier choisi.
- **Toujours visible :** épinglez la fenêtre au premier plan et profitez des menus et de la barre de titre natifs.

La protection des modifications simultanées n’empêche pas un autre programme d’écrire dans le fichier. Sauvegardez les fichiers importants.

## Raccourcis principaux

| Raccourci | Action |
| --- | --- |
| `Command + N` | Crée un nouveau document. |
| `Command + T` | Ouvre un nouvel onglet supplémentaire. |
| `Command + O` | Ouvre un ou plusieurs fichiers texte locaux. |
| `Command + S` | Sauvegarde immédiatement l’onglet actuel. |
| `Command + W` | Sauvegarde puis ferme l’onglet actuel. |
| `Shift + Command + T` | Rouvre l’onglet fermé le plus récemment. |
| `Command + F` | Affiche la barre de recherche intégrée de l’éditeur courant. |
| `Command + =` ou `Command + +` | Agrandit le texte dans l’éditeur. |
| `Command + -` | Réduit le texte dans l’éditeur. |
| `Command + ,` | Ouvre les réglages. |
| `Shift + Return` | Insère une nouvelle ligne à la fin de la ligne actuelle. |

<details>
<summary>Compiler depuis les sources (Xcode)</summary>

Nécessite macOS 26.0+, Xcode 26.0+ et [XcodeGen](https://github.com/yonaskolb/XcodeGen) 2.44+.

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

Consultez [CONTRIBUTING.md](CONTRIBUTING.md) pour les tests et le développement.

</details>

## Documentation

- [Contributions et tests](CONTRIBUTING.md)
- [Historique des versions](CHANGELOG.md)

Les issues, suggestions et pull requests sont les bienvenues.

## Licence

NeatEditor est distribué sous [MIT License](LICENSE).

## Outils associés

| Outil | Description |
|---|---|
| [NeatPaste](https://github.com/NeatMacApps/NeatPaste) | Historique du presse-papiers macOS dans la barre de menus. |
| [NeatWebApp](https://github.com/NeatMacApps/NeatWebApp) | Transformez des sites en apps macOS avec un lanceur dans l’encoche. |
| [HandySwitch](https://github.com/x0c/HandySwitch) | Changez de mode sombre et empêchez la veille depuis la barre de menus. |
| [MacResourceMonitor](https://github.com/x0c/MacResourceMonitor) | Repérez les processus gourmands en CPU depuis la barre de menus. |
| [Corral](https://github.com/corral-dev/corral) | Gérez les sessions d’agents de programmation dans le terminal et poursuivez sur Mac ou iPhone. |
