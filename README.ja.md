# NeatEditor

<p align="center">
  <img src="./docs/images/app-icon.png" width="128" height="128" alt="NeatEditor アプリアイコン">
</p>

[![Platform](https://img.shields.io/badge/platform-macOS%2015%2B-1f6feb)](https://developer.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6-orange)](https://www.swift.org/)
[![UI](https://img.shields.io/badge/UI-SwiftUI%20%2B%20AppKit-0a7ea4)](https://developer.apple.com/xcode/swiftui/)
[![Project](https://img.shields.io/badge/Project-XcodeGen-6f42c1)](https://github.com/yonaskolb/XcodeGen)
[![License](https://img.shields.io/badge/License-MIT-green)](./LICENSE)

> SwiftUI と AppKit で構築された、起動が速くミニマルな macOS 向けプレーンテキストエディタです。集中しやすい執筆体験、macOS らしい操作感、効率的なマルチタブ編集を提供します。

**言語:** [English](./README.md) | [简体中文](./README.zh-CN.md) | [日本語](./README.ja.md) | [한국어](./README.ko.md) | [Español](./README.es.md) | [Français](./README.fr.md) | [Deutsch](./README.de.md)

## スクリーンショット

<p align="center">
  <img src="./docs/images/neateditor-main-window.png" alt="NeatEditor のメインワークスペース" width="1201" />
</p>

## NeatEditor を作った理由

NeatEditor は、インターフェースのノイズを減らし、意識を文章そのものに戻すことを目標にしています。

- 高速起動: アプリ起動時の不要なブロッキング処理を避けます。
- 余白を優先した UI: 周辺の装飾よりエディタ面を主役にします。
- macOS らしい挙動: タイトルバー、メニュー、ショートカット、ウインドウ操作を自然に保ちます。
- プレーンテキスト重視: メモ、下書き、一時的な整理、軽い編集に向いています。

## 主な特徴

- 起動時から使えるドキュメントを備えたマルチタブ編集。
- タブの選択、クローズ、インラインリネームを低遅延で実現。
- Finder、ドラッグ＆ドロップ、ファイル URL の貼り付けでローカルテキストファイルを開けます。
- 行番号、ネイティブ検索、Undo、IME 変換中の入力処理、`Command +/-` ズームを搭載。
- 2 秒 debounce の自動保存に加え、タブ切り替え時やアプリ非アクティブ時にも保存。
- 常に手前に表示するピン留めと、タイトルバーのダブルクリックによるズームに対応。
- 保存済みドキュメントのリネーム時は、拡張子を保ったままディスク上のファイル名も同期。
- 空白のみの内容では既存ファイルを上書きしない設計です。

## 主なショートカット

| ショートカット | 動作 |
| --- | --- |
| `Command + N` | 新しいドキュメントを作成します。 |
| `Command + T` | 新しいタブを追加で開きます。 |
| `Command + O` | 1 つ以上のローカルテキストファイルを開きます。 |
| `Command + S` | 現在のタブをすぐに保存します。 |
| `Command + W` | 現在のタブを保存して閉じます。 |
| `Shift + Command + T` | 直前に閉じたタブを再度開きます。 |
| `Command + F` | 現在のエディタでインライン検索バーを表示します。 |
| `Command + =` または `Command + +` | エディタ文字を拡大します。 |
| `Command + -` | エディタ文字を縮小します。 |
| `Command + ,` | 設定を開きます。 |
| `Shift + Return` | 現在の行末に移動して改行を挿入します。 |

`Command + Z`、`Command + X`、`Command + C`、`Command + V` などの macOS 標準テキストショートカットも、ネイティブなテキストシステム経由でそのまま利用できます。

## 現在の状態

NeatEditor は、軽量な macOS 向けプレーンテキストエディタとしてすでに利用でき、`1.0.0` として公開されています。

- 対応プラットフォーム: macOS 15.0+
- 技術スタック: Swift 6、SwiftUI、AppKit bridge、Observation、XcodeGen
- 現在の検証方法: `xcodebuild ... test`（単体テスト18件: テキスト同期、永続化、設定）、ビルド確認と手動テスト
- 現在の対象範囲: プレーンテキスト中心、リッチテキストやプラグイン、クロスプラットフォーム対応は未実装

## クイックスタート

### 必要条件

- macOS 15.0+
- Xcode 16.2+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) 2.44+

### クローンして開く

```bash
git clone <repo-url>
cd NeatEditor
xcodegen generate
open NeatEditor.xcodeproj
```

### ターミナルでビルド

```bash
xcodebuild -project "NeatEditor.xcodeproj" \
  -scheme "NeatEditor" \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData \
  build
```

## 開発メモ

- `project.yml` がプロジェクト構成の唯一のソースです。
- ソースファイルを追加または削除したら `xcodegen generate` を実行してください。
- `NeatEditorTests` はテキスト同期、永続化、設定をカバーしています（18件）。`xcodebuild ... test` で実行できます（英語 README 参照）。
- 挙動変更の確認は、プレビューだけでなくビルド済みアプリで行うことを推奨します。

## リリース

このリポジトリは CI ではなく署名済みローカルリリースで公開しています。

- メンテナは `scripts/publish-release.sh` で DMG + Sparkle ZIP をローカルビルドします（Developer ID 署名、公証済み）。
- 公開リリースには署名済み DMG（初回インストール用）、署名済み Sparkle ZIP（アプリ内更新用）、`SHA256SUMS.txt` が含まれます。
- tag 起点の GitHub Actions は未署名のプレースホルダのみを上げます。リリースとしてインストールしないでください。

最もシンプルな導入手順: Releases から署名済み DMG を取得し `Applications` にドラッグ後、`open -a NeatEditor` で起動します。対応は macOS 15.0+ のみです。

詳細は [RELEASING.md](./RELEASING.md) を参照してください。

## リポジトリ文書

- [README.md](./README.md): 英語版 README
- [README.zh-CN.md](./README.zh-CN.md): 簡体字中国語版 README
- [README.ko.md](./README.ko.md): 韓国語版 README
- [README.es.md](./README.es.md): スペイン語版 README
- [README.fr.md](./README.fr.md): フランス語版 README
- [README.de.md](./README.de.md): ドイツ語版 README
- [CONTRIBUTING.md](./CONTRIBUTING.md): 開発環境とコントリビュート手順
- [CHANGELOG.md](./CHANGELOG.md): リリース履歴
- [RELEASING.md](./RELEASING.md): GitHub Release の流れ
- [TabStripGestures.md](./TabStripGestures.md): タブ操作設計メモ

## 今後の改善候補

- push と pull request を対象にした一般的な CI ワークフローを追加する（現在は未署名の tag ワークフローのみ）。

## コントリビュート

Issue、提案、Pull Request を歓迎します。まずは [CONTRIBUTING.md](./CONTRIBUTING.md) をご覧ください。

## ライセンス

NeatEditor は [MIT License](./LICENSE) の下で公開されています。
