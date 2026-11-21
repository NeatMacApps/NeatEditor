# NeatEditor Mac App Store Submission Pack

Ready-to-paste metadata and checklist for the first Mac App Store release (free, non-mainland-China rollout, manual release, Universal Purchase ready for future iOS).

## 1. Frozen Identifiers (Do Not Change After First Upload)

| Field | Value | Notes |
|---|---|---|
| Platform | `macOS` (add `iOS` later to the same App record) | Enables Universal Purchase |
| App Store Connect App ID | `6837635367` | Created 2026-11-21 |
| Bundle ID | `com.caozc.NeatEditor` | Registered as **Universal** (macOS + iOS) |
| SKU | `neateditor` | Immutable after App creation |
| Primary Language | English (U.S.) | Add Simplified Chinese (`zh-Hans`) localization |
| Pricing | Free (No IAP in v1) | IAP/subscriptions can be added in later versions |
| Release Option | **Manually release this version** | Stops at `Pending Developer Release` after approval |

## 2. Storefront & Compliance Selections

- **Availability**: Uncheck **China mainland** for v1 (add later after ICP filing without rebuilding). Uncheck **"Make available in all future countries or regions"**.
- **EU DSA**: For a free non-commercial app, either declare non-trader if eligible or uncheck EU storefronts to avoid publishing a personal address/phone.
- **Made for Kids**: **Unchecked** (irreversible once approved).
- **Age Rating**: Complete the full questionnaire (all answers None/No → `4+`).
- **App Privacy**: **No, we do not collect data from this app**.
- **Export Compliance**: `ITSAppUsesNonExemptEncryption` is already set to `NO` in `Info-AppStore.plist`.

## 3. Store Listing Copy

### English (U.S.)
- **Name**: `NeatEditor`
- **Subtitle**: `Fast, distraction-free plain text` (33 chars, ≤ 30? Use: `Fast plain-text editor` — 22 chars)
- **Promotional Text**: `A lightweight, native macOS plain-text and Markdown editor built for instant launch and effortless auto-save.`
- **Description**:
  > NeatEditor is a fast, native plain-text and Markdown editor designed for macOS.
  >
  > - **Instant launch & multi-tab workspace**: Open and switch between notes cleanly with a compact native tab bar and full-height sidebar.
  > - **Automatic saving with external-change protection**: Edits save automatically with conservative reconciliation and conflict-copy preservation when files change outside the editor.
  > - **Focused reading & writing**: Built-in themes, line numbers, inline find, zoom controls, and native macOS text editing with full IME support.
  > - **Local-first & private**: Works completely offline with no account, no tracking, and no cloud lock-in. Choose any folder on your Mac to organize your text files.
- **Keywords**: `plain text,text editor,markdown,notes,writing,notepad,scratchpad,offline,lightweight`
- **Support URL**: `https://github.com/NeatMacApps/NeatEditor/issues` (or `https://caozc.com/neateditor/support`)
- **Privacy Policy URL**: `https://github.com/NeatMacApps/NeatEditor/blob/main/docs/app-store/PRIVACY_POLICY.md` (or hosted on `https://caozc.com/neateditor/privacy`)

### 简体中文 (`zh-Hans`)
- **名称**: `NeatEditor`（如需中文名，备案前须先固定且不加修饰词）
- **副标题**: `轻量原生纯文本编辑器`
- **宣传文本**: `为 macOS 原生打造的轻量纯文本与 Markdown 编辑器，秒级启动，自动保存。`
- **描述**:
  > NeatEditor 是一款为 macOS 原生打造的轻量纯文本与 Markdown 编辑器。
  >
  > - **极速启动与多标签工作区**：紧凑原生标签栏与全高侧边栏，快速新建与切换文档。
  > - **自动保存与外部变更保护**：自动防抖保存，支持外部修改检测与冲突副本保留，避免误覆盖。
  > - **专注读写体验**：内置多套配色主题、行号、内嵌查找、字号缩放，完整适配原生输入法与 macOS 交互习惯。
  > - **本地优先、零打扰**：完全离线运行，无需登录，无任何数据收集；自由选择本地任意目录管理你的纯文本文件。
- **关键词**: `纯文本,文本编辑器,Markdown,笔记,写作,记事本,离线,轻量`

## 4. App Review Notes

> NeatEditor is a completely offline, local-only plain-text and Markdown editor with no user accounts, no network requests, and no in-app purchases.
>
> How to test:
> 1. Launch NeatEditor — a new blank document opens automatically in the app's sandboxed Documents folder.
> 2. Type any text; it saves automatically after 2 seconds (or press Command-S).
> 3. Use File > Open (Command-O) or Settings > Documents Folder > Choose Folder to grant access to any user-selected file or folder on disk. Access is persisted across relaunches via app-scoped security-scoped bookmarks.
> 4. Press Command-F for inline find, Command-+/Command-- to zoom, and Command-, to open Settings (themes, tab behavior, and English/Simplified Chinese language).

## 5. Build, Audit & Upload Commands

```bash
cd app-macos
xcodegen generate

# Universal Release archive for Mac App Store
xcodebuild -project NeatEditor.xcodeproj \
  -scheme NeatEditorAppStore \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  -archivePath build/app-store/NeatEditor.xcarchive \
  archive

# Audit the archived app (verifies sandbox entitlement, universal binary, zero Sparkle)
python3 tools/macos-distribution/distribution.py audit \
  --app build/app-store/NeatEditor.xcarchive/Products/Applications/NeatEditor.app \
  --channel app-store \
  --bundle-id com.caozc.NeatEditor
```

Then open `build/app-store/NeatEditor.xcarchive` in Xcode Organizer → **Distribute App → App Store Connect → Upload**.
