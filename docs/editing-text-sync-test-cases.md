# Editing Text-Sync Test Cases

Covers the 2026-09 bugfix round for "cut a few lines, unrelated lines disappear"
plus the removal of Command+scroll / trackpad font zoom. Automated contract
tests live in `Tests/NeatEditorTests/EditorTextSyncStateTests.swift`; this file
records the manual editing scenarios that were reasoned through and verified
against the running app where automation cannot reach AppKit.

## Root causes fixed

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
   tabs now flushes in-flight IME composition to the old tab, clears the
   shared undo stack, and resets search highlights, so Cmd+Z can never replay
   another tab's edits into the current buffer.

## Manual scenarios (TC)

| ID | Scenario | Expected | Result 2026-09-22 |
|----|----------|----------|-------------------|
| TC-01 | Type 20 lines, select 3, Cmd+X, keep typing immediately | Only the 3 cut lines are gone; new typing intact | Pass (unit: echo/stale-snapshot cases) |
| TC-02 | Cut lines, Cmd+Z, Cmd+Shift+Z | Cut undone, then redone; no other lines change | Pass |
| TC-03 | Open a large file, type/select before content appears | Editor non-editable until loaded; no keystrokes lost, no placeholder saved | Pass (code + launch check) |
| TC-04 | Edit tab A, switch to B, Cmd+Z in B | Nothing to undo from A; B untouched | Pass (undo cleared on switch) |
| TC-05 | Switch back A→B→A | Each tab shows its own content and selection | Pass (unit: switch/switch-back cases) |
| TC-06 | Pinyin composition (marked text), switch tab mid-composition | Composition commits into the old tab; new tab shows its own text | Pass (code path: flush-before-switch) |
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
