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
- App-created documents use `~/.config/neateditor/documents/`, or the equivalent under `XDG_CONFIG_HOME`. Existing open/restored document URLs remain unchanged; this change does not move user files. Directory creation is deferred until the first nonblank save.
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

Keep Settings inside the existing workspace tab, including the application-menu and Command-comma entry points, under the editor exception in the macOS baseline. Use a centered 480-point native grouped `Form`: Editor (tab behavior and language), Updates (the existing two switches), and the app icon/name/version with Check for Updates and Quit. Ordinary settings fit the supported minimum workspace height without scrolling. Remove the custom cards, focus/control borders and orphan update button.

While Settings is selected, the workspace content minimum is 500 × 440 points so these controls remain visible; opening Settings grows a smaller window through the native minimum-size constraint. Document tabs retain their existing minimum. Switching back does not force the user's window to shrink.

Owner correction (2026-10-19): remove Text Softness and all three appearance sliders from Settings. Remove the obsolete interface strings and slider row implementation. Preserve the serialized rendering preferences and document appearance; this request removes the Settings control. The reduced minimum height follows the remaining content, including the language-restart notice. Language-restart guidance remains visible only when applicable. Keep the existing editor tab, document saving/quit guard and update behavior.

References inspected: NeatWebApp's grouped Form/about row and NeatEditor's existing SettingsView and workspace scene. Reuse the existing public Form, Picker and Toggle controls and approved workspace host. Acceptance must inspect the installed Settings tab in dark/light and English/Chinese, check the minimum window size and complete remaining content, and verify Text Softness is absent. Existing model tests verify preference persistence; they do not establish the visual result. Research exemption: this owner-directed removal reuses the inspected existing native Settings and workspace containers and introduces no API semantics.

Historical acceptance for 1.0.8 (8), before the owner removed Text Softness: English dark and Chinese light were inspected at a 500 × 632-point window, including the language-restart notice. All groups and the about row fit without clipping or settings scrolling. Command-comma reopens the Settings tab. The native slider accessibility increment changed the persisted light-appearance preference from 0.16 to 0.26; decrement restored 0.16, while the other two values remained unchanged. Pointer-drag and arrow-key automation did not move the slider, so those methods are not counted as passed evidence. The original language preference and softness values were restored after acceptance.

Diagnostics: 51 tests in six suites passed; the scheduler suite passed again after its weak-reference warning was repaired. Release build and analyze passed. The ineffective Sparkle delegate `@preconcurrency` annotation was removed. The remaining Xcode App Intents metadata-extraction warning comes from the build tool finding no AppIntents dependency in this target: this settings change adds no intents, metadata is not required for these controls, and existing editor behavior is unaffected. Reassess the warning when an App Intents capability is introduced; no diagnostic was suppressed. The Developer ID-signed, stapled universal 1.0.8 app was installed and its Settings tab inspected again. The public [1.0.8 release](https://github.com/NeatMacApps/NeatEditor/releases/tag/v1.0.8) contains the notarized DMG, signed ZIP and SHA256SUMS; all three downloaded bytes matched, and the live Sparkle feed serves build 8. A transient SSH transport failure was recovered from the existing verified artifacts without rebuilding or resubmitting notarization. Distribution requirements remain in `RELEASING.md`.
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
pinned by the unit tests above. If a future "lines disappear" report arrives,
replay TC-01 slowly first: with the fix, any remaining loss must come from a
new external writer of `tabs[].content` (search for assignments) rather than
the bridge.

Current 1.0.9 diagnostics: a fresh Debug clean/build/analyze/test run passed all 51 tests in six suites. The two App Intents metadata notices have the same assessed origin above. Xcode also listed arm64 and x86_64 for the broad local destination and selected the native arm64 destination; this is destination selection, not a compiler warning. The formal archive uses the generic macOS destination and explicitly builds both supported architectures. Installed visual acceptance and public distribution remain pending.
