# Changelog

All notable changes to this project will be documented in this file.

The format loosely follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## 1.0.22 - 2026-10-27

### Fixed

- Continue the line under the tab bar across the whole window, including over the sidebar, so the selected tab rises from one unbroken line.
- Fill the top row behind the window controls with the tab bar color when the sidebar is hidden, instead of the editor's background.

### 简体中文

- 标签栏下方的线条贯穿整个窗口，包括侧边栏上方，选中的标签从一条连续的线上凸起。
- 隐藏侧边栏时，红绿灯按钮后面的顶部区域使用标签栏颜色，不再露出编辑区的白色底色。

## 1.0.21 - 2026-10-27

### Fixed

- Let the sidebar reach the top of the window again behind the window controls. Since 1.0.19 the active window showed a white bar above the sidebar.
- Keep double-click and drag on empty parts of the top row working with the restored sidebar, including above the sidebar and beside the window controls when the sidebar is hidden.

### 简体中文

- 侧边栏重新铺到窗口顶部，红绿灯按钮后面也是侧边栏。自 1.0.19 起，激活状态的窗口在侧边栏上方会出现一块白色区域。
- 侧边栏恢复后，双击或拖动顶部一行的空白处仍然有效，包括侧边栏上方，以及隐藏侧边栏时红绿灯按钮旁边的空白处。

## 1.0.20 - 2026-10-27

### Fixed

- Rejoin the lower-left and lower-right curves of the selected tab with the line under the tab bar. In 1.0.19 the titlebar clipped the curves just above the line, so every selected tab's corners looked broken.
- Remove the band-colored strip that 1.0.19 added before the first tab. The first tab's curve now ends exactly at the sidebar edge.

### 简体中文

- 修复选中标签左下角、右下角的弧线与标签栏下方线条断开的问题。1.0.19 中标题栏把弧线最底下一行截掉了，每个选中标签的两个下角看起来都是断的。
- 去掉 1.0.19 在第一个标签前多出的一段色块，第一个标签的弧线现在正好收在侧边栏边缘。

## 1.0.19 - 2026-10-27

### Fixed

- Double-clicking or dragging any empty part of the top row, including above the sidebar, above the tabs and after the last tab, now reaches the native window titlebar: it resizes the window according to your Desktop & Dock setting and moves the window.
- Keep the selected first tab's outline continuous with the editor's top line. The tab's lower curve was clipped at the edge of the editor column, so the line appeared broken next to the sidebar or the sidebar button.

### 简体中文

- 双击或拖动顶部一行的任意空白处（包括侧边栏上方、标签上方和最后一个标签之后）现在都交给系统标题栏处理：按"桌面与程序坞"设置缩放窗口，并可拖动窗口。
- 修复选中第一个标签时轮廓线与编辑区顶部线条断开的问题。此前标签底部的弧线在编辑区边缘被裁掉，侧边栏或侧边栏按钮旁会出现断线。

## 1.0.18 - 2026-10-27

### Changed

- Replace the full-width editor status bar with a non-interactive floating character count; keep the final text line clear of the count and preserve the full-height line-number gutter.
- Count committed characters off the main actor, including spaces, line breaks and composed emoji, and expose the visible count to accessibility.
- Separate sidebar file discovery, bounded previews and legacy migration from core document persistence, and share collision-safe naming across first saves and file duplication.
- Adopt the approved blue rolled-paper app icon with a serif N, its lower third hidden behind the roller.

### Fixed

- Keep legacy document migration retryable when a file copy fails instead of marking an incomplete migration finished. Preserve existing destination files and legacy originals.
- Add regression coverage for numbered copies, extensionless and Unicode filenames, bounded collision retries and immediate propagation of non-collision errors.
- Refuse dirty release checkouts instead of automatically committing another session's unfinished work.

### 简体中文

- 将编辑器整行状态栏改为不可交互的悬浮字数显示；为末行文字保留空间，行号栏仍保持全高。
- 在主线程之外统计已上屏的字符，包含空格、换行和组合表情，并向辅助功能提供当前可见的字数。
- 将侧边栏文件发现、有界预览和旧文档迁移从核心持久化逻辑拆分，首次保存与文件复制共用防覆盖的重名处理。
- 采用已确认的蓝底卷纸图标，纸面为衬线 N，字母下方三分之一由滚轴遮挡。
- 修复文件复制失败后旧文档迁移仍被标记为完成的问题，允许后续重试，同时保留目标目录已有文件和旧目录原件。
- 增加编号副本、无扩展名及中文文件名、重名重试上限和非重名错误立即返回的回归测试。
- 发布时拒绝包含未提交改动的工作区，不再自动提交其他会话尚未完成的工作。

## 1.0.16 - 2026-10-26

### Changed

- Use one native compact 40 pt top row, keeping the sidebar toggle beside the window controls and New Document and Always on Top aligned with the document tabs.
- Reduce document tabs to equal 168 pt slots with 30 pt height, 13 pt regular titles and a lighter separator outline, preserving their stepped join to the editor.
- Move documents-folder selection into Settings and remove the sidebar header's folder actions menu.
- Give sidebar files consistent row heights and keep the selected tab and its connected content surface the same color.

### Fixed

- Repair editor rendering with TextKit 2 so inserting and deleting text no longer leaves stale line fragments; keep wrapped-line numbers, the final line and search highlights aligned with the displayed text.
- Keep the tab strip's available width synchronized with window resizing so widening the window reveals tabs instead of leaving unused space.
- Let blank top-row space use native window dragging and double-click behavior, while preserving tab selection and inline rename.

### 简体中文

- 使用原生 40 pt 紧凑单行顶部栏；侧边栏开关位于窗口控制按钮旁，新建文档与置顶按钮和文档标签保持对齐。
- 文档标签统一为 168 pt 宽、30 pt 高，使用 13 pt 常规字重标题和更轻的分隔线轮廓，保留与编辑区相连的台阶造型。
- 将文档文件夹选择移入设置，移除侧边栏头部的文件夹操作菜单。
- 统一侧边栏文件行高，并让选中标签与其连接的内容区域保持相同背景色。
- 使用 TextKit 2 修复编辑显示，插入或删除文字后不再残留旧行片段；自动换行行号、末行与搜索高亮保持和显示文字对齐。
- 调整窗口大小时同步更新标签栏可用宽度，放大窗口后能显示更多标签，不再留下无法利用的空白。
- 顶部栏空白区域交还系统处理拖窗与双击，同时保留标签选择和行内重命名。

## 1.0.15 - 2026-10-25

### Changed

- Require macOS 26.0 or later and Xcode 26.0 or later to build. Keep universal Apple silicon and Intel packages; CI validates with Xcode 26.0.1 on macOS 26.
- Use the macOS 26 native prominent toolbar style while Always on Top is enabled.
- Replace deprecated SwiftUI text concatenation with a complete localizable sentence and styled shortcut interpolation.

### Fixed

- Keep the selected tab's filename, fill and outline together during rapid window resizing and overflow scrolling. Resize no longer queues competing reveal animations.
- Shift+Enter now inserts at the logical content end without splitting CRLF or overlooking Unicode line terminators. The insertion still supports native undo. Line numbers now count the same native line boundaries, including the final empty line.

### 简体中文

- 最低系统版本提高到 macOS 26.0，构建要求 Xcode 26.0 或更新版本；继续提供 Apple silicon 和 Intel 通用安装包，CI 改用 macOS 26 与 Xcode 26.0.1。
- 置顶启用时使用 macOS 26 原生工具栏强调样式，清楚显示当前状态。
- 用完整句子的本地化插值替换已废弃的 SwiftUI 文本拼接，保留快捷键的加粗显示。
- 修复快速调整窗口大小和溢出滚动时，标签文件名、底色与轮廓各自移动的问题；缩放不再叠加相互竞争的滚动动画。
- 修复 Shift+Enter 拆开 CRLF 或漏判 Unicode 换行符的问题；插入操作仍可原生撤销，行号也按相同的原生换行边界计数（包含末尾空行）。

## 1.0.14 - 2026-10-25

### Fixed

- The native Sidebar toolbar button no longer draws a blue focus ring after accessibility or keyboard activation. Rounded stepped tabs, the continuous editor join, folder selection and window dragging are unchanged.

### 简体中文

- 修复通过辅助功能或键盘激活原生侧边栏按钮后出现蓝色焦点圈的问题；保留圆角台阶标签、连续底边、文件夹切换及拖窗优化。

## 1.0.13 - 2026-10-25

### Fixed

- The selected tab's outline now meets the editor's top rule on the same line, so the tab bar border stays continuous instead of breaking at the tab's bottom corners.
- The tab join is measured from AppKit window frames, so the line stays aligned when the sidebar is shown, hidden, or resized.

### 简体中文

- 选中标签的轮廓与编辑区顶线落在同一条线上，标签栏边框不再在标签底部两角断开。
- 标签开口改用 AppKit 窗口坐标换算，侧边栏显示、隐藏或拖动宽度时仍保持对齐。

## 1.0.12 - 2026-10-24

### Changed

- The sidebar lists your `~/Documents` folder by default and can switch to another folder from its header. New documents save to the current folder, and the choice is remembered across launches.
- Files without an extension are listed when their head looks like plain UTF-8 text, so extensionless notes appear while binaries are still skipped.
- Sidebar rows no longer draw a file icon, giving filenames and previews the full width of the narrow sidebar.
- The toolbar's tab strip and the editor share one continuous top rule that opens under the selected tab, keeping the tab attached to the page.

### Fixed

- Documents left in the previous app library (`~/.config/neateditor/documents`) are copied into the current folder once, without overwriting or deleting anything.
- Dragging from a document tab or the empty tab-strip area moves the window again; a click still selects and double-click still renames.

### 简体中文

- 侧边栏默认列出你的 `~/Documents`，可在头部切换到其它文件夹；新文档保存到当前文件夹，选择会在重启后保留。
- 无扩展名文件在开头内容像 UTF-8 纯文本时会显示，因此无扩展名笔记也能列出，二进制文件仍然跳过。
- 侧边栏行不再显示文件图标，文件名和摘要可使用窄栏的全部宽度。
- 工具栏下的标签栏与编辑区共用一条连续顶线，并在选中标签处留出开口，让标签与页面保持相连。
- 旧应用目录（`~/.config/neateditor/documents`）中的文档会一次性复制到当前文件夹，不覆盖、不删除任何文件。
- 从文档标签或标签栏空白处拖动可以重新移动窗口；单击仍选择标签，双击仍重命名。

## 1.0.11 - 2026-10-24

### Changed

- Use a full-height native sidebar with resizable columns and standard list selection. Document tabs and search remain in the editor column; collapsing the sidebar leaves no empty rail.
- Keep window controls, document tabs, new-document and Always on Top actions in one native toolbar row, without a separate row above the tabs.

### Fixed

- Saving and switching tabs no longer reorder the sidebar; filenames use a stable natural descending order.
- Keep the existing rounded, stepped document tabs joined to the editor surface, draw one continuous outline, and keep the tabs visible when the sidebar collapses.
- Background refresh no longer replaces newer live previews or mixes unsaved text into the disk cache.
- Duplicate includes current committed editor text, including unsaved edits. Folder errors remain visible without discarding the previous file list.
- Share rename validation across open and closed documents, preserve remembered font settings, handle Windows line endings, and cap preview reads.

### 简体中文

- 使用贯穿窗口左侧的原生侧边栏，支持系统分栏拖动和列表选中；标签栏与搜索只位于右侧编辑区，收起后不残留空白竖条。
- 窗口按钮、文档标签、新建与置顶共用一行原生工具栏，不再在标签栏上方额外占用一行。
- 保存和切换标签不再改变侧边栏顺序，文件名使用稳定的自然降序。
- 保留与编辑区连成一体的圆角台阶式文档标签，使用一条连续轮廓，并在收起侧边栏后保持标签可见。
- 后台刷新不再覆盖较新的实时摘要，未保存文字不再混入磁盘缓存。
- 复制包含当前已上屏但尚未保存的文字；目录读取失败会保留原列表并显示错误。
- 打开与关闭的文件共用重命名校验并保留字号记忆，修复 Windows 换行摘要，限制预览读取量。

## 1.0.9 - 2026-10-19

### Changed

- Remove Text Softness and its three sliders from Settings. Existing document appearance is preserved.
- Reduce the Settings content minimum to 500 × 440 points; all remaining controls fit without scrolling.

### 简体中文

- 从设置中移除文字柔和度及其三个滑块，保留现有文档显示效果。
- 设置内容最小尺寸缩小为 500 × 440 点，剩余控件完整可见，无需滚动。

## 1.0.8 - 2026-10-18

### Changed

- Settings uses a compact native grouped form with aligned controls, switches and app information. It remains a workspace tab.
- Adjust text softness for light, dark and high-contrast appearances with native percentage sliders; existing preferences and immediate application are preserved.
- Settings has a 500 × 600 point content minimum so all controls remain visible in smaller windows.

### 简体中文

- 设置改为紧凑的原生分组表单，统一对齐控件、开关和应用信息，继续保留在工作区标签中。
- 浅色、深色和高对比度外观的文字柔和度可用系统滑块按百分比调整，沿用现有偏好并即时生效。
- 设置的内容最小尺寸为 500 × 600 点，较小的窗口也能完整显示全部控件。

## 1.0.7 - 2026-10-15

### Fixed

- Pinned windows no longer fight over focus when they overlap: a window behind another window at the mouse position no longer steals key focus, so two overlapping pinned windows stop flickering.
- Hover-to-focus now debounces: the pointer must rest inside the window for 150 ms before takeover, and no steal happens within 350 ms after a focus change, so edges no longer jitter two or three times.

### 简体中文

- 两个置顶窗口交叠时不再来回抢焦点：鼠标位置已被别的窗口盖住时，后窗不再抢 key，重叠区不再闪烁。
- 悬停抢焦点加入防抖：指针持续停留 150 毫秒才接管，焦点变化后 350 毫秒内不再抢，边沿附近不再抖两三次。

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
