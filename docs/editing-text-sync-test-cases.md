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
