# NeatEditor

<p align="center">
  <img src="./docs/images/app-icon.png" width="128" height="128" alt="NeatEditor 应用图标">
</p>

[![Platform](https://img.shields.io/badge/platform-macOS%2015%2B-1f6feb)](https://developer.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6-orange)](https://www.swift.org/)
[![UI](https://img.shields.io/badge/UI-SwiftUI%20%2B%20AppKit-0a7ea4)](https://developer.apple.com/xcode/swiftui/)
[![Project](https://img.shields.io/badge/Project-XcodeGen-6f42c1)](https://github.com/yonaskolb/XcodeGen)
[![License](https://img.shields.io/badge/License-MIT-green)](./LICENSE)

> 一个极简、快速启动的 macOS 纯文本编辑器，基于 SwiftUI 与 AppKit 构建，专注无干扰写作、原生桌面交互和高效多标签编辑。

**语言版本：** [English](./README.md) | [简体中文](./README.zh-CN.md) | [日本語](./README.ja.md) | [한국어](./README.ko.md) | [Español](./README.es.md) | [Français](./README.fr.md) | [Deutsch](./README.de.md)

## 截图

<p align="center">
  <img src="./docs/images/neateditor-main-window.png" alt="NeatEditor 主工作区截图" width="1201" />
</p>

## 为什么是 NeatEditor

NeatEditor 的目标很直接：减少界面噪音，把注意力还给文字本身。

- 快速启动：尽量避免在应用启动路径上做阻塞操作。
- 空间优先：让编辑区域成为主角，而不是被界面装饰分散注意力。
- 原生体验：保留 macOS 用户熟悉的标题栏、菜单、快捷键和窗口行为。
- 纯文本专注：适合做笔记、草稿、临时整理和轻量编辑。

## 主要特性

- 多标签纯文本编辑，启动即创建可用文档。
- 标签切换、关闭、重命名都围绕低延迟交互设计。
- 支持通过 Finder、拖拽和粘贴文件 URL 打开本地文本文件。
- 内置行号 gutter、原生查找、撤销、输入法组合态处理，以及 `Command +/-` 缩放。
- 自动保存带 2 秒 debounce，并会在切换标签和应用失焦时保存。
- 支持窗口置顶以及标题栏空白区域双击缩放窗口。
- 已落盘文档重命名时会同步处理磁盘文件名，并允许编辑扩展名。
- 空白内容不会覆盖已有文件，这是当前产品的明确设计选择。
- 应用创建的文档位于 `~/.config/neateditor/documents/`（或 `XDG_CONFIG_HOME` 对应位置），首次保存时创建。

## 主要快捷键

| 快捷键 | 作用 |
| --- | --- |
| `Command + N` | 新建一个文档。 |
| `Command + T` | 再打开一个新标签页。 |
| `Command + O` | 打开一个或多个本地文本文件。 |
| `Command + S` | 立即保存当前标签页。 |
| `Command + W` | 保存并关闭当前标签页。 |
| `Shift + Command + T` | 重新打开最近关闭的标签页。 |
| `Command + F` | 显示当前编辑器的内嵌查找栏。 |
| `Command + =` 或 `Command + +` | 放大编辑器文字。 |
| `Command + -` | 缩小编辑器文字。 |
| `Command + ,` | 打开设置。 |
| `Shift + Return` | 在当前行末尾另起一行。 |

像 `Command + Z`、`Command + X`、`Command + C`、`Command + V` 这样的 macOS 原生文本快捷键，也会通过系统文本组件正常工作。

## 当前状态

NeatEditor 现在已经可以作为一个轻量 macOS 纯文本编辑器使用。

- 平台目标：macOS 15.0+
- 技术栈：Swift 6、SwiftUI、AppKit bridge、Observation、XcodeGen
- 当前验证方式：`xcodebuild ... test`（单元测试覆盖编辑器文本同步、文档持久化、自动保存调度、工作区失败路径、原生输入法组合提交、字号偏好）、构建校验和手动测试
- 当前分发方式：通过 `scripts/publish-release.sh` 在本机打出 Developer ID 签名 + 公证 DMG（见 [RELEASING.md](./RELEASING.md)）
- 当前范围：专注纯文本，不包含富文本、插件系统或跨平台支持

## 快速开始

### 安装（macOS）

1. 打开 [GitHub Releases](https://github.com/NeatEditor/NeatEditor/releases)，选择发行说明中写明 Developer ID 签名 + 公证的版本。只有签名产物才是安装路径：旧的 `*-macOS-universal.*` 文件（例如 v1.0.3 上的）是未签名 CI 占位文件，不要安装。如提供 `SHA256SUMS.txt` 可自行校验。
2. 打开 DMG，把 `NeatEditor.app` 拖入 `Applications`。
3. 首次启动：

```bash
open -a NeatEditor
```

应用启动即创建可用文档；按 `Command + N` 新建文档。

### 支持的平台

- 支持：macOS 15.0+（Apple silicon 与 Intel，universal 构建）。
- 不支持：Linux 与 Windows。应用依赖 AppKit 与 macOS 专属签名/公证，在这些平台上无法构建也无法运行，不提供安装包。

### 环境要求（从源码构建）

- macOS 15.0+
- Xcode 16.2+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) 2.44+

### 克隆并打开

```bash
git clone <repo-url>
cd NeatEditor
xcodegen generate
open NeatEditor.xcodeproj
```

### 终端构建

```bash
xcodebuild -project "NeatEditor.xcodeproj" \
  -scheme "NeatEditor" \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData \
  build
```

## 开发说明

- `project.yml` 是工程结构的真实来源。
- 新增或删除源文件后，请重新执行 `xcodegen generate`。
- `NeatEditorTests` 覆盖编辑器文本同步、文档持久化、自动保存调度、工作区失败路径、原生输入法组合提交与字号偏好，手动编辑场景见 [docs/editing-text-sync-test-cases.md](./docs/editing-text-sync-test-cases.md)，运行方式：

```bash
xcodebuild -project "NeatEditor.xcodeproj" \
  -scheme "NeatEditor" \
  -configuration Debug \
  -destination 'platform=macOS' \
  test
```
- 如果你修改了运行流程或交互逻辑，优先用构建产物进行实际验证。

## 发布版本

公开安装包来自本机签名发版流程，而不是 CI：

- 维护者在签名 Mac 上用 `scripts/publish-release.sh` 构建 DMG + Sparkle ZIP（Developer ID 签名、公证、装订；三件上传并回读确认后才从草稿转公开）。
- 每个签名公开 Release 包含签名 DMG（首次安装）、签名 Sparkle 更新 ZIP（应用内更新）和 `SHA256SUMS.txt`，双语说明取自该版本的 `CHANGELOG.md` 条目。
- tag 触发的 GitHub Actions 只构建校验打标签源码，未签名包仅作为私有工作流产物保留，不要把它们当作正式版本安装。

完整流程、要求与交付交接见 [RELEASING.md](./RELEASING.md)。本 checkout 不宣称除 Release 说明与校验文件之外的任何交付已验证。

## 仓库文档

- [README.md](./README.md)：英文主 README
- [README.ja.md](./README.ja.md)：日文说明
- [README.ko.md](./README.ko.md)：韩文说明
- [README.es.md](./README.es.md)：西班牙文说明
- [README.fr.md](./README.fr.md)：法文说明
- [README.de.md](./README.de.md)：德文说明
- [CONTRIBUTING.md](./CONTRIBUTING.md)：贡献和开发说明
- [CHANGELOG.md](./CHANGELOG.md)：版本变更记录
- [RELEASING.md](./RELEASING.md)：GitHub Release 流程
- [TabStripGestures.md](./TabStripGestures.md)：标签栏交互设计说明

## 已知后续改进方向

- 补运行截图或演示 GIF，提升 GitHub 首页第一印象。
- 增加常规 CI workflow，覆盖 push 和 pull request（目前只有 tag 校验工作流）。

## 参与贡献

欢迎 issue、建议和 pull request，开始前请先阅读 [CONTRIBUTING.md](./CONTRIBUTING.md)。

## 许可证

NeatEditor 使用 [MIT License](./LICENSE) 开源。
