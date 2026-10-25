# Editing Text-Sync Test Cases

Covers the 2026-09 bugfix round for "cut a few lines, unrelated lines disappear"
plus the removal of Command+scroll / trackpad font zoom. Automated contract
tests live in `Tests/NeatEditorTests/EditorTextSyncStateTests.swift`; this file
records the manual editing scenarios that were reasoned through and verified
against the running app where automation cannot reach AppKit.

## Persistence and scheduling requirements

- Newly created documents, including the initial empty workspace, use the local creation time in the fixed Gregorian 24-hour format `yyyyMMdd-HHmmss` (for example, `20261001-142530`). The time is captured once at creation rather than updating while editing; saving adds `.txt`. If an open document already uses the same base name, append `-2`, `-3`, and so on using in-memory tabs only. Existing documents keep their names; first-save collision handling continues to protect files on disk.
- The first save of an unsaved tab must never overwrite an existing file, including a file created after the tab was named. A collision must leave both the original file and the unsaved buffer intact.
- A tab title represents one file name. Saving and renaming must not allow a title to escape its destination directory.
- App-created documents use the current documents folder, defaulting to `~/Documents`, as adopted on 2026-10-24. The previous XDG app library is migration-only; see the [persistence KB](../../docs/PERSISTENCE_AUTOSAVE_KNOWLEDGE_BASE.md) for its non-destructive copy contract. Existing open/restored document URLs remain unchanged. Directory creation is deferred until the first nonblank save.
- Blank or whitespace-only content must continue to leave existing files untouched.
- Replacing or cancelling a delayed autosave must prevent the old task from clearing the new task's cancellation handle. Completed tasks must not retain their scheduler.
- Each scheduled operation has a unique identity that cannot be reused after completion. Cancellation must release bookkeeping for closed tabs.
- A first save publishes a complete file only after writing succeeds; failed or interrupted writes must not leave a partial document at the final name. App-owned document directories and files are private to the account.
- Startup and new-tab construction must avoid scanning user directories synchronously for file names; first-save collision handling protects files regardless of naming.

Default-name acceptance (2026-10-01): all 42 tests passed, including local-time year rollover, same-second unsaved/saved tab collisions, and existing-file preservation. The committed 1.0.5 (4) build was installed under `/Applications` and verified through the native File > New / New Tab menus, typing, Save, and the two-second autosave path; screenshots confirmed the creation name, `.txt` suffix, and same-second `-2` suffix.

## Workspace failure and editing requirements

- A failed read must never become document content or mark a placeholder as successfully loaded. The failed tab stays unsaveable, reports the error through the existing native alert, and can retry through Open or reselection.
- Save and rename errors must be visible. A failed save keeps the tab and its buffer open, including Close Other Tabs and application quit.
- Editor bindings resolve a stable tab identity on every write; deleting or reordering tabs must not redirect an old editor's final report into another tab.
- Uncommitted input-method text (pinyin or other marked text still waiting for the user to choose characters) is never document content. Autosave, Save, close, tab switches and app deactivation save only the committed text and must not force the composition to commit. Saving leaves an in-progress composition on screen untouched; once the user commits it, the normal edit path schedules autosave. Switching away from or closing the tab discards the composition and resets the input method through `NSTextInputContext.discardMarkedText()`, so the pinyin lands in neither tab and the input method keeps no stale state. If the system or input method commits text on its own (for example, when another app becomes active), that commit arrives as a normal edit and is saved like typing. Use the public `NSTextView` text system and SwiftUI `alert` APIs; no replacement text control or alert is required.
- 2026-10-07 regression: the old rule forced `unmarkText()` before every save, which wrote the pinyin display text (for example `hui` while typing Shuangpin `hv` in Rime) into the file and left Rime composing in the background, so later keystrokes produced raw letters such as `hv`.
- Once AppKit reports an edit, same-tab snapshots cannot overwrite its live text. Lazy initial content can still be pushed before editing; changing tabs resets the ownership decision. The stale-snapshot regression must actually pass an older string.
- Restoring a workspace must select a document and must not open or foreground Settings proactively.
- Tests isolate workspace preferences from the user's actual saved session.
- Search and Settings retain their current product behavior while native controls receive meaningful accessibility labels and no custom control-outline focus frames.

## Settings layout revision (2026-10-18)

Keep Settings inside the existing workspace tab, including the application-menu and Command-comma entry points, under the editor exception in the macOS baseline. Use a centered 480-point native grouped `Form`: Editor (documents folder, tab behavior and language), Updates (the existing two switches), and the app icon/name/version with Check for Updates and Quit. Ordinary settings fit the supported minimum workspace height without scrolling. Remove the custom cards, focus/control borders and orphan update button.

While Settings is selected, the workspace content has a 500-point width floor and a 440-point height floor, each subject to the existing tab-strip minimum. Opening Settings grows a smaller window through the native minimum-size constraint. Document tabs retain their existing minimum. Switching back does not force the user's window to shrink.

Owner correction (2026-10-19): remove Text Softness and all three appearance sliders from Settings. Remove the obsolete interface strings and slider row implementation. Preserve the serialized rendering preferences and document appearance; this request removes the Settings control. The reduced minimum height follows the remaining content, including the language-restart notice. Language-restart guidance remains visible only when applicable. Keep the existing editor tab, document saving/quit guard and update behavior.

Owner correction (2026-10-25): choosing the documents folder is a Settings preference, not a sidebar action. Add one native labeled row to the existing Editor group, displaying the current folder name with the complete path available to accessibility and hover, plus “Choose Folder…”. Reuse `WorkspaceStore.chooseDocumentsFolder()` and its native `NSOpenPanel`, validation, immediate refresh and existing persisted `documentsFolderPath`; do not add a second preference or move existing documents. Remove the chooser from the sidebar header menu, background context menu and empty/error actions. Retain Show in Finder, Refresh and file actions. Cancelling the chooser changes nothing. Keep the complete Settings form visible without scrolling at its minimum size, including the conditional restart notice.

Installed folder-setting acceptance (`a8d526e`, 2026-10-25): the Developer ID-signed universal Release at `/Applications/NeatEditor.app` matches the built executable. The actual Settings menu opens the new row; its button opens the existing native directory panel. Selecting a temporary empty folder updates both Settings and the sidebar, persists after restart, and remains unchanged after cancelling another selection. At that revision the sidebar header menu contained only Show in Finder and Refresh (removed by the follow-up correction below); the empty sidebar has no chooser. Inspected English/dark and Chinese/light captures at the native minimum 700 × 522 pt window (200 pt sidebar, 500 pt detail), plus the English restart-notice state: the full form and about row remain visible without scrolling. Evidence is under `build/FolderSettings/`. Restored the original folder, system-language preference, normal launch arguments and 1284 × 777 pt window size; removed the empty fixture directory. No document text was edited. The 94-test arm64 suite, universal Debug analysis and universal Release build pass; complete logs are in `build/FolderSettings/logs/`. No Swift compiler/analyzer diagnostics remain; the only metadata-step warning is the existing AppIntents diagnostic assessed in [code-review.md](code-review.md#sidebar-review-2026-10-24). Native Intel/minimum-macOS execution and VoiceOver were not tested.

Component reference inspected for this row: the existing `SettingsView` grouped Form and NeatWebApp's `SettingsPanes.swift` `LabeledContent` action row; reuse its native label/control ownership, not its unrelated settings or state model. Apple's [LabeledContent](https://developer.apple.com/documentation/swiftui/labeledcontent) and [Form](https://developer.apple.com/documentation/swiftui/form) document the native settings layout; `LabeledContent` is present in the installed Xcode 27.2 SwiftUI interface. Acceptance: open Settings through the application menu/Command-comma, choose a temporary folder, inspect the sidebar update and setting readback, cancel a second selection, restart and verify persistence, then restore the original folder. Inspect the sidebar header to confirm no folder-setting entry remains.

Owner correction (2026-10-25, sidebar header follow-up): delete the ellipsis actions icon and its menu from the sidebar section header. The header shows only the current documents-folder name; choosing the folder stays a Settings preference. Keep Show in Finder (folder and files) and Refresh reachable from the sidebar's native context menus, and leave file actions unchanged. Retain the one-line middle truncation and the full path in hover/accessibility text, with no added control chrome or replacement icon. Verify the installed header in English and Chinese: the icon and its menu are absent, the folder name remains readable, and right-click still offers Show in Finder and Refresh.

References inspected: NeatWebApp's grouped Form/about row and NeatEditor's existing SettingsView and workspace scene. Reuse the existing public Form, Picker and Toggle controls and approved workspace host. Acceptance must inspect the installed Settings tab in dark/light and English/Chinese, check the minimum window size and complete remaining content, and verify Text Softness is absent. Existing model tests verify preference persistence; they do not establish the visual result. Research exemption: this owner-directed removal reuses the inspected existing native Settings and workspace containers and introduces no API semantics.

Current 1.0.9 diagnostics: a fresh Debug clean/build/analyze/test run passed all 51 tests in six suites. Debug reports the App Intents metadata notice assessed below; the universal Release archive additionally reports the pre-existing absent application category. The previous 1.0.8 source has no `LSApplicationCategoryType` either. Apple defines that key as the [App Store category](https://developer.apple.com/documentation/bundleresources/information-property-list/lsapplicationcategorytype); this Developer ID release retains the existing distribution metadata. Residual limitation: no declared store category; select and validate it when introducing a Mac App Store route. Xcode listed arm64 and x86_64 for the broad local Debug destination and selected native arm64; this is destination selection, not a compiler warning. The formal archive uses the generic macOS destination and explicitly builds both supported architectures. No diagnostics were suppressed.

Installed 1.0.9 (9) acceptance: the primary inspected the final stapled app's English and Chinese Settings at 500 × 502 points. Text Softness and all three sliders are absent; Editor, Updates and the complete about/update/quit row remain visible without clipping or scrollbars. This is static evidence under lock. The lock shield prevented direct resize and body-control actions; a launch-only native frame override exercised the smaller window. Dark appearance, the language-restart notice and physical interaction were not revalidated on this artifact. The launch-only dark request still rendered light and is not dark evidence. The three persisted softness values remain unchanged; opening a document can update its remembered-font recency bookkeeping. Original saved window frames were restored and the app relaunched without inspection arguments.

The public [1.0.9 release](https://github.com/NeatMacApps/NeatEditor/releases/tag/v1.0.9) contains the notarized DMG, signed ZIP and SHA256SUMS. All three complete anonymous downloads match the local artifacts; the live Sparkle feed serves build 9. The final installed app passes strict signature and stapled-ticket validation and has the same executable as the exported release. Its source snapshot is `ed157d43264d0cb6c1081e188924902d894db289`; installation did not reset rendering preferences or alter the save/quit guard.

Historical acceptance for 1.0.8 (8), before the owner removed Text Softness: English dark and Chinese light were inspected at a 500 × 632-point window, including the language-restart notice. All groups and the about row fit without clipping or settings scrolling. Command-comma reopens the Settings tab. The native slider accessibility increment changed the persisted light-appearance preference from 0.16 to 0.26; decrement restored 0.16, while the other two values remained unchanged. Pointer-drag and arrow-key automation did not move the slider, so those methods are not counted as passed evidence. The original language preference and softness values were restored after acceptance.

Historical 1.0.8 diagnostics: 51 tests in six suites passed; the scheduler suite passed again after its weak-reference warning was repaired. Release build and analyze passed. The ineffective Sparkle delegate `@preconcurrency` annotation was removed. The remaining Xcode App Intents metadata-extraction warning comes from the build tool finding no AppIntents dependency in this target: this settings change adds no intents, metadata is not required for these controls, and existing editor behavior is unaffected. Reassess the warning when an App Intents capability is introduced; no diagnostic was suppressed. The Developer ID-signed, stapled universal 1.0.8 app was installed and its Settings tab inspected again. The public [1.0.8 release](https://github.com/NeatMacApps/NeatEditor/releases/tag/v1.0.8) contains the notarized DMG, signed ZIP and SHA256SUMS; all three downloaded bytes matched, and its release-time Sparkle feed served build 8. A transient SSH transport failure was recovered from the existing verified artifacts without rebuilding or resubmitting notarization. Distribution requirements remain in `RELEASING.md`.
- Zoom commands belong to the existing native View menu, using `CommandGroup`; the app must not create a second View menu. Existing zoom shortcuts remain available.

## Text synchronization history

1. **Stale-snapshot overwrite** — `updateNSView` used to assign
   `textView.string = text` whenever the two differed. After rapid edits the
   binding snapshot can lag behind the live buffer, so an old value clobbered
   newer content. Fixed by `EditorTextSyncState`: same-tab echoes never push.
2. **Lazy-load overwrite** — the async file load unconditionally replaced
   `tabs[].content`, discarding edits typed during the load window, and
   `isContentLoaded` was flipped before the load finished. Now the flag flips
   at completion, the editor is non-editable until then, and a non-empty
   buffer is never overwritten by a stale load.
3. **Cross-tab pollution** — one `NSTextView` is shared by all tabs. Switching
   tabs now discards in-flight IME composition (it belongs to neither tab;
   see the input-method requirement above), clears the shared undo stack, and resets search highlights, so Cmd+Z can never replay
   another tab's edits into the current buffer.

## Manual scenarios (TC)

| ID | Scenario | Expected | Result 2026-09-22 |
|----|----------|----------|-------------------|
| TC-01 | Type 20 lines, select 3, Cmd+X, keep typing immediately | Only the 3 cut lines are gone; new typing intact | Pass (unit: echo/stale-snapshot cases) |
| TC-02 | Cut lines, Cmd+Z, Cmd+Shift+Z | Cut undone, then redone; no other lines change | Pass |
| TC-03 | Open a large file, type/select before content appears | Editor non-editable until loaded; no keystrokes lost, no placeholder saved | Pass (code + launch check) |
| TC-04 | Edit tab A, switch to B, Cmd+Z in B | Nothing to undo from A; B untouched | Pass (undo cleared on switch) |
| TC-05 | Switch back A→B→A | Each tab shows its own content and selection | Pass (unit: switch/switch-back cases) |
| TC-06 | Pinyin composition (marked text), switch tab mid-composition | Composition is discarded; old tab and its file keep only committed text; new tab shows its own text and the next keystroke starts a fresh composition | 2026-10-07: unit test + code path |
| TC-13 | Type pinyin without committing, wait past the 2-second autosave, press Cmd+S, then switch to another app | File holds only committed text while the pinyin stays on screen as marked text; any text the input method commits later is saved like typing | 2026-10-07: unit test + installed-app check |
| TC-07 | Search open, edit text | Highlights follow the new matches, selection does not jump | Pass |
| TC-08 | Search open, switch tab | Old highlights cleared; current query applies to the new tab without jumping | Pass |
| TC-09 | Cmd+= / Cmd+- and View menu Zoom In/Out | Font size steps 10…36, remembered per file | Pass (unit: stepping/clamp/remember) |
| TC-10 | Hold Cmd + scroll mouse / two-finger scroll on trackpad | **Scrolls normally; font size unchanged** (feature removed) | Pass (launch check) |
| TC-11 | Save empty / whitespace-only tab | No file created, existing file untouched | Pass (unit: blank-content case) |
| TC-12 | Rename onto an existing file name | Error alert, no overwrite | Pass (unit: collision case) |

## What automation cannot cover here

Driving real keystrokes/cuts inside `NSTextView` needs accessibility-driven UI
scripting (TCC-gated in agent sessions), so TC-01/02/04/06/10 were verified by
code-path review plus launch smoke test; the sync *decision* behind them is
pinned by the unit tests above. These checks do not establish correct incremental
painting. For a new "lines disappear" report, distinguish the live buffer and
saved bytes from the displayed pixels before choosing a repair. Correct content
with a repeated or missing displayed line requires layout/painting investigation;
it is not evidence of another writer of `tabs[].content`. Re-run TC-01/02 for
actual content loss, and TC-14 below for display-only artifacts.

## Display-only editing acceptance

Owner report (2026-10-25): deleting a line can leave the last line displayed twice;
inserting a line can hide the last line, while the text itself remains correct.
The editor must update continuously without requiring scrolling, resizing,
switching tabs or forcing a full redraw. Previous synchronization and line-ending
fixes do not establish coverage of this symptom.

**TC-14 (partially verified; manual actual-app keystroke matrix pending):** Start
with `"\naaaaa\nbbbbbb"` without a final newline. Repeatedly insert and delete
newlines in the first empty line, then repeat in the middle of a longer document
and near the viewport's bottom edge. At each step, compare the native buffer,
native layout geometry and sequential window captures. The unchanged last line
must appear exactly once in its current position. Repeat with a final newline,
wrapped lines, CJK/emoji, search both open and closed, undo/redo, font zoom and
window resizing. Check autosaved bytes and existing IME/tab-isolation contracts
independently. A resized or forcibly redrawn final screenshot cannot establish
incremental-paint correctness.

The editor now uses a native TextKit 2 network. A native probe on macOS 27.2 /
Xcode 27.2 confirmed that reading `layoutManager` switches such a text view back
to TextKit 1; no product source performs that read. The production AppKit views
passed sequential unforced captures for start-of-document insert/delete,
middle-line insertion, a 200-line bottom viewport, final-line insert/delete,
search highlight and post-edit re-highlight. The integrated app's initial file
surface was also inspected. Details and evidence paths are recorded in the parent
workspace's `docs/EDITOR_SYNC_KNOWLEDGE_BASE.md`, §7.1.

Still pending for a full TC-14 pass: manual actual-app keystroke replay covering
IME, undo/redo, wrapped CJK/emoji, search open/closed, font zoom, resize and
autosaved bytes; repeat on macOS 26.

## Shift+Enter line boundaries

Shift+Enter inserts the existing LF newline at the current logical line's content
end, leaving an existing LF, CR, CRLF, NEL, line separator or paragraph separator
intact. UTF-16 selection positions (including emoji/CJK prefixes), an empty buffer
and an unterminated last line follow the same rule. The insertion participates
in native undo. Marked input continues to belong to the input method.

The line-number gutter uses the same native logical-line boundaries, including
CR-only and Unicode separators. CRLF counts once; a terminated final line has
one empty trailing line. Number width and visible labels must agree.
