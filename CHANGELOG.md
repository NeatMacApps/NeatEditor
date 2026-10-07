# Changelog

All notable changes to this project will be documented in this file.

The format loosely follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## 1.0.6 - 2026-10-07

### Fixed

- Autosave, Save, closing a tab and switching apps no longer write uncommitted input-method text (such as pinyin still waiting for a candidate) into the file. Only committed text is saved, and the composition on screen stays untouched.
- Switching tabs mid-composition discards the uncommitted text and resets the input method, so the pinyin lands in neither tab and later keystrokes no longer come out as raw letters.

### 简体中文

- 自动保存、手动保存、关闭标签和切换到其他应用时，不再把还没选字上屏的拼音写进文件；只保存已上屏的文字，屏幕上正在输入的拼音保持不变。
- 输入拼音途中切换标签时，未上屏的拼音会被丢弃并重置输入法，不会落进任何一个标签，之后打字也不会再冒出原始字母。

## 1.0.5 - 2026-10-01

### Fixed

- Failed file reads no longer become document text or overwrite the original file. Save failures keep buffers open and prevent application quit; errors appear in native alerts.
- New documents preserve existing files when names collide. Complete content is written once before claiming an available name, with private file permissions.
- Delayed editor updates cannot write into another tab or replace newer text. Pending input-method composition is committed before save and close.
- Replaced autosave tasks remain cancellable and do not retain closed-tab bookkeeping or their scheduler.
- Workspace restoration opens documents instead of Settings. Zoom commands share the native View menu; search and Settings controls have clearer accessibility labels and no custom outline frames.

### Changed

- New documents use compact local date-time names (`yyyyMMdd-HHmmss`) instead of Untitled; same-second tabs receive a numeric suffix.
- New app-created documents use `~/.config/neateditor/documents/` (or `XDG_CONFIG_HOME`). Existing document locations remain unchanged; empty documents still leave files untouched.
- New-tab naming no longer scans disk synchronously. Release tooling builds committed universal source, keeps packages in a draft until verification, and excludes unsigned CI packages from public releases.

### 简体中文

- 新建文件默认使用简短的本地日期时间命名（`yyyyMMdd-HHmmss`），同一秒新建多个标签时自动添加序号。
- 读取失败不会再把错误提示写入文档或覆盖原文件；保存失败时保留标签与内容，并阻止退出。
- 新文档重名时保留已有文件，完整内容只写入一次，再选择可用名称。
- 修正延迟文本更新、输入法提交和自动保存取消的竞态，避免内容丢失或写错标签。
- 恢复工作区时只打开文档；缩放命令并入系统 View 菜单，改善搜索与设置的无障碍标签。
- 新建文档默认保存在应用配置目录，已有文件不搬迁；新建标签不再同步扫描磁盘。
- 发布流程从已提交源码构建通用安装包，验证完成前保留为草稿，CI 不再公开上传未签名安装包。

## 1.0.4 - 2026-09-26

### Fixed

- Empty title bar double-click now performs the native macOS window action once, preventing enlargement from immediately reverting.

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
