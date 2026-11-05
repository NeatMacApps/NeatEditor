# NeatEditor

<p align="center">
  <img src="./docs/images/app-icon.png" width="128" height="128" alt="NeatEditor 应用图标">
</p>

[![Platform](https://img.shields.io/badge/platform-macOS%2026%2B-1f6feb)](https://developer.apple.com/macos/)
[![License](https://img.shields.io/badge/License-MIT-green)](./LICENSE)

> 原生 macOS 纯文本编辑器，打开就能写。

**语言版本：** [English](./README.md) | [简体中文](./README.zh-CN.md) | [日本語](./README.ja.md) | [한국어](./README.ko.md) | [Español](./README.es.md) | [Français](./README.fr.md) | [Deutsch](./README.de.md)

## 截图

<p align="center">
  <img src="./docs/images/neateditor-main-window.png" alt="NeatEditor 主工作区截图" width="1120" />
</p>

## 安装

**macOS 26.0+ · 支持 Apple silicon 和 Intel。** 仅支持 macOS，不提供 Linux 或 Windows 版本。

```bash
brew install --cask x0c/tap/neateditor
```

也可以[下载最新版已签名、公证的 DMG](https://github.com/NeatMacApps/NeatEditor/releases/latest)，打开后将 `NeatEditor.app` 拖入 `Applications`。

启动后按 `Command + O` 打开文件，或按 `Command + N` 新建文档。

## 为什么是 NeatEditor

适合记笔记、写草稿，也可以临时改几行文本。

## 主要特性

- **多标签：** 快速切换、关闭、原位重命名，也能重开最近关闭的标签。
- **本地文件：** 通过 Finder、拖拽或粘贴文件 URL 打开；重命名已保存文档时同步修改磁盘文件名。
- **原生编辑：** 行号、查找、撤销、输入法组字，以及 `Command +/-` 文字缩放。
- **自动保存：** 停止输入 2 秒后、切换标签时、应用失焦时保存，写入按序执行。
- **外部修改：** 处理其他编辑器、脚本或编程助手对文件的修改。未修改的正文自动重载，独立改动保守合并，检测到冲突时保留双方版本。
- **空白保护：** 空内容或只有空白字符的内容不会覆盖已有文件。因此，清空编辑区不会清空磁盘上的原文件。
- **文档文件夹：** 默认使用 `~/Documents`，可在「设置 → 编辑器 → 文档文件夹」中切换；新文档保存到选定目录。
- **保持可见：** 支持窗口置顶，保留熟悉的原生菜单和标题栏操作。

其他程序仍可能改写文件，重要内容请自行备份。

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

<details>
<summary>从源码构建（Xcode）</summary>

需要 macOS 26.0+、Xcode 26.0+ 和 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 2.44+。

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

测试和开发说明见 [CONTRIBUTING.md](CONTRIBUTING.md)。

</details>

## 文档

- [贡献与测试](CONTRIBUTING.md)
- [版本记录](CHANGELOG.md)

欢迎提交 issue、建议和 pull request。

## 许可证

NeatEditor 使用 [MIT License](LICENSE) 开源。

## 相关工具

| 工具 | 简介 |
|---|---|
| [NeatPaste](https://github.com/NeatMacApps/NeatPaste) | 菜单栏中的 macOS 剪贴板历史。 |
| [NeatWebApp](https://github.com/NeatMacApps/NeatWebApp) | 将网站变成独立 macOS 应用，从刘海启动器打开。 |
| [HandySwitch](https://github.com/x0c/HandySwitch) | 在菜单栏切换深色模式、防止睡眠。 |
| [MacResourceMonitor](https://github.com/x0c/MacResourceMonitor) | 从菜单栏找出占用 CPU 的进程。 |
| [Corral](https://github.com/corral-dev/corral) | 在终端管理编程助手会话，并从 Mac 或 iPhone 继续。 |
