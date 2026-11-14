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
- Persistence cleanup (2026-10-27): keep the existing service API and split sidebar enumeration/preview/migration from core saves and naming. First saves and both live-buffer/disk duplication share the same bounded, no-overwrite candidate policy: original name, then ` 2` through ` 1000` before the final extension. Non-collision errors propagate immediately; do not rewrite staged content on each collision.
- Review-fix requirement (2026-11-05): duplicating an unopened document must retain coordinated source reads and complete, no-overwrite publication on destinations without hard-link support, including exFAT/FAT32 when an exclusive publication primitive is available. Preserve the existing bounded collision naming, original bytes and attributes, and staging cleanup; a check-then-overwrite fallback or a partially visible final file is not acceptable. Unsupported exclusive operations fail closed, never fall back to ordinary move/rename. Reuse the existing staging/publication flow rather than adding a separate duplication implementation. The same safety applies to existing-document rename: use an atomic exclusive primitive, preserve the source and competitor on a raced collision, map that collision to the existing error, and retarget document identity only after a successful move. Only a recognized unsupported-link capability error may select an alternative primitive; unrelated permission/I/O errors still propagate.
- Legacy migration must remain retryable after any copy failure, not just enumeration failure. Successful copies and existing destinations stay intact, remaining files are still attempted, and the migration-complete marker may be set only when every candidate is copied or already present. A destination created concurrently is a resolved collision, not a reason to overwrite or block migration.

Default-name acceptance (2026-10-01): all 42 tests passed, including local-time year rollover, same-second unsaved/saved tab collisions, and existing-file preservation. The committed 1.0.5 (4) build was installed under `/Applications` and verified through the native File > New / New Tab menus, typing, Save, and the two-second autosave path; screenshots confirmed the creation name, `.txt` suffix, and same-second `-2` suffix.

## External-writer safety (owner approved 2026-10-30)

Owner report (2026-11-07): after an open file is edited in another application,
the Mac editor can continue to show its old text and can report that a sibling
`<original-name>.sb-*` file no longer exists. A native TextEdit reproduction on
2026-11-07 emitted `presentedItemDidMove` to that temporary backup while the
newly saved document remained at the original path. Do not persist the temporary
backup as the tab's identity or show a destructive Save Failed action for this
transient safe-save phase; refresh the original path after the writer finishes.
Preserve intentional external rename tracking, local-edit conflict handling,
marked-text deferral, explicit external revisions and stable observation of the
new original inode. Add a competing-writer regression using the same
move-to-backup/replacement/backup-removal sequence.

Acceptance (2026-11-07, Debug build installed at `/Applications/NeatEditor.app`):
the two new regressions pass, the full suite reports 202 tests in 23 suites with
no failure, and `analyze` adds no diagnostic. On the installed app a disposable
tab showing `LIVE-BEFORE refresh check` displayed `LIVE-AFTER external TextEdit
save` after TextEdit saved that file, in the same tab and window, with no alert;
the previously failing `.sb-` tab reopened on the real original. Captures:
`build/external-refresh/live-{1-before,2-after,3-closed}.png` and
`installed-healed.png`.

- All document reads/writes and rename/trash operations share an ordered I/O lane. Background saves are enqueued before returning; later synchronous lifecycle saves drain that same lane. Late completions cannot publish stale content or file identity.
- Retain an accepted content baseline, independent of timestamps and file size. Recheck disk bytes inside native coordinated access before replacement. A clean buffer accepts external updates; equal content is not a conflict. Three-way line reconciliation merges independent edits conservatively, preserving original line terminators; ambiguous/overlapping edits never silently overwrite either side.
- On conflict, preserve the original disk file and save the local version at a fresh conflict sibling using existing no-clobber publication. Persist a private recovery record containing baseline/local/disk content before publishing a merged or conflicting result. Inform the user with the existing native alert and an action to open the other version. Recovery must survive restart without opening a recovery window proactively. Save failures retain the buffer and offer an explicit Save Copy action using `NSSavePanel`; cancellation changes nothing and publication never clobbers an existing destination. The only explicit discard exception is Don't Save in the failed document's alert, defined below. This is the escape path for deleted/missing originals, not an automatic recovery window.
- Conflict notification metadata is transient: dismissing a Keep Both alert must not make a later blank-content save repeat the old notification. The preserved documents/recovery remain intact.
- Automatic three-way reconciliation is bounded to 20,000 lines per input. Larger simultaneously changed files use Keep Both with recovery instead of unbounded worst-case diff work; clean/one-sided changes still reconcile directly.
- Use explicit `NSFileCoordinator`/`NSFilePresenter`, with independent file and parent-directory observation for direct-writing applications and atomic replacement. Events wake content reconciliation; active-scene/save checks cover missed events. Moving/deleting an external file must not silently recreate its old path. Preserve iCloud conflict versions as separate files before resolving their version metadata.
- Native `NSDocument` was evaluated against CotEditor's implementation. Its default automatic revert/autosave policy does not directly preserve this application's lazy placeholders, first-save naming, blank exception and existing workspace ownership; retain the workspace and explicit native coordination rather than migrate the document framework in this fix.
- External updates are explicit editor revisions, not ordinary same-tab binding echoes. Apply them as native undoable text replacements, preserving selection/scroll and delaying replacement during marked text. Existing stale-snapshot and uncommitted-IME protections remain mandatory.
- Acceptance covers content-preserving/reversing timestamps, equal-length edits, direct writes, atomic replacement, clean/dirty/disjoint/overlapping edits, pending first save, slow old autosave versus newer manual/close/quit save, rename/delete, symlink aliases, failure retention, restart recovery, resource cleanup, IME, native undo and installed editor pixels. Test fixtures use disposable directories and isolated preferences; physical iCloud two-device acceptance is reported separately from injected/version or local competing-writer tests.

Reference/reuse: the [inspected implementations](code-review.md#external-writer-safety-research-2026-10-30) supply save ordering, baseline checks and CotEditor's native alert/content-check pattern. Reuse `NSFileCoordinator`, `NSFilePresenter`, `NSTextView.shouldChangeText(in:replacementString:)` / `textStorage.replaceCharacters` / `didChangeText()` and the existing SwiftUI native alert directly; no copied cross-platform services, custom alert or new dependency.

## Workspace failure and editing requirements

- A failed read must never become document content or mark a placeholder as successfully loaded. The failed tab stays unsaveable, reports the error through the existing native alert, and can retry through Open or reselection.
- Save and rename errors must be visible. A failed save keeps the tab and its buffer open, including Close Other Tabs and application quit, unless the user explicitly chooses Don't Save in that failed document's alert.
- Owner request (2026-11-03): save-failure alerts that offer Save Copy also offer Don't Save (Chinese: 放弃保存), using a native destructive button and a concise warning that this closes the document and discards unsaved changes. Only that explicit action bypasses saving: cancel its autosave, invalidate late completions, stop observation, close only the alert's document, and select the normal adjacent tab. Do not delete/recreate/overwrite the disk file or add discarded text to Reopen Closed Tab. Stale/absent alerts cannot discard a different tab. OK remains non-destructive and Save Copy retains its existing behavior. Never exercise Don't Save on real user content during automated acceptance.
- Reference inspected: `WorkspaceView`'s existing SwiftUI alert and `WorkspaceStore.closeDocument`'s removal/selection path. Reuse those native alert/buttons and shared cleanup, with SwiftUI [`ButtonRole.destructive`](https://developer.apple.com/documentation/swiftui/buttonrole/destructive); no custom dialog or global ignore-save-errors preference. Verify missing files, new unsaved files, wrong/stale IDs, pending autosave, adjacent selection, normal-close/reopen preservation and installed alert pixels/action on disposable fixtures.
- Editor bindings resolve a stable tab identity on every write; deleting or reordering tabs must not redirect an old editor's final report into another tab.
- Uncommitted input-method text (pinyin or other marked text still waiting for the user to choose characters) is never document content. Autosave, Save, close, tab switches and app deactivation save only the committed text and must not force the composition to commit. Saving leaves an in-progress composition on screen untouched; once the user commits it, the normal edit path schedules autosave. Switching away from or closing the tab discards the composition and resets the input method through `NSTextInputContext.discardMarkedText()`, so the pinyin lands in neither tab and the input method keeps no stale state. If the system or input method commits text on its own (for example, when another app becomes active), that commit arrives as a normal edit and is saved like typing. Use the public `NSTextView` text system and SwiftUI `alert` APIs; no replacement text control or alert is required.
- 2026-10-07 regression: the old rule forced `unmarkText()` before every save, which wrote the pinyin display text (for example `hui` while typing Shuangpin `hv` in Rime) into the file and left Rime composing in the background, so later keystrokes produced raw letters such as `hv`.
- Once AppKit reports an edit, same-tab snapshots cannot overwrite its live text. Lazy initial content can still be pushed before editing; changing tabs resets the ownership decision. The stale-snapshot regression must actually pass an older string.
- Restoring a workspace must select a document and must not open or foreground Settings proactively.
- Tests isolate workspace preferences from the user's actual saved session. Coordination-test deadlines must return a failure even while an underlying detached operation remains blocked; cancellation must not rejoin that non-cooperative operation. Exercise this deadline branch with a controlled, releasable fixture, not only successful operation completion.
- Search and Settings retain their current product behavior while native controls receive meaningful accessibility labels and no custom control-outline focus frames.
- Review-fix requirement (2026-11-05): regex search must bound actual active computation and retained pending requests, not only the time spent awaiting results. Edits, query changes and dismissal supersede obsolete work without accumulating abandoned evaluations. Timeout remains a non-beeping status and a later valid query must recover. The 2,000-range painting budget must never limit Find Next: literal and regex navigation retain access to every match.
- Search repair reference/API: reuse the existing `EditorTextContainerView`/`EditorTextView` search requests, native `NSTextView` selection and text-storage highlights; do not add controls, copy or styling. This product now uses case-insensitive Foundation `NSRegularExpression` with system ICU pattern syntax instead of dynamic Swift Regex. Reuse the native progress/stop implementation described in the [shared cancellable-regex recipe](~/Codes/_standards/swift.md#cancellable-regular-expression-work), based on the inspected Apple enumeration block and installed SDK. Keep one active evaluation and at most one latest pending request, including when an injected evaluator ignores cancellation. Discard stale generations and retain the active task until computation actually ends. This parser switch is not a claim of exact equivalence with Swift-specific regex syntax.

Don't Save verification (2026-11-03, source `2b931a6`): the full native arm64
suite passes 152 tests in 19 suites; Debug/Release universal builds and analysis
pass on macOS 27.2 / Xcode 27.2. No Swift compiler/analyzer diagnostics remain;
the existing AppIntents metadata-step notice is assessed in
[code-review.md](code-review.md#sidebar-review-2026-10-24). Full diagnostics are
under `build/tab-switch/logs/discard-*`.

The Developer ID-signed universal Release is installed at
`/Applications/NeatEditor.app`, retaining version/build 1.0.27/27 with no public
release. A separately identified, re-signed validation installation using the
same compiled Release code and isolated preferences reproduced a missing
**disposable** original. Fresh inspected English/Chinese dark captures show Save
Copy, the destructive Don't Save button, OK and the discard consequence. Native
AXPress on Don't Save removed exactly that fixture tab; preference readback was
empty and the missing file remained absent. Evidence is in
`build/tab-switch/discard-alert-*.png` and `discard-action-receipt.json`.

Historical activation limit before the performance correction: the existing
process's guarded quit returned Apple Event error -128 for an unsaveable real
document. That process was not force-quit; no real buffer was discarded and no
Save Copy action was exercised on real content. The later performance installation
completed through a successful normal quit, and the current app runs the new
source. Fresh pre-install workspace/preferences were restored after fixture
acceptance; no old session snapshot was used to overwrite later user changes. Native Intel and
minimum-macOS execution, and a light-appearance alert capture remain unverified.

## Document-switch rendering continuity

Owner report (2026-11-03): switching between files briefly clears the editor to a
blank surface before the new content appears. Loaded documents must switch without
an intermediate blank frame. Preserve the native TextKit 2 editor, stable binding
identity, IME discard, undo isolation, search and save-before-switch behavior.
Owner correction (2026-11-03, after trying the earlier repair): ordinary local
text documents of a few hundred KB must open promptly without a spinner or a
visible loading mode. Adding ProgressView to hide a slow open was rejected as a
performance/design failure. Measure the complete sidebar-click → outgoing save →
queue wait → read/decode → native presentation path, including repeat opens and
representative small/medium documents; optimize the cause, not just the feedback.
Keep file I/O asynchronous and preserve save ordering, external-writer checks,
IME ownership and failure recovery. Before a workspace transition, commit the live
editor snapshot, but do not request a coordinated write for a loaded document
whose committed text still equals its accepted disk baseline and has no pending
background write. Cancel redundant debounced saves on that clean transition.
An older queued write followed by a user reverting to the baseline still requires
an ordered save of the newest text; equality with the old baseline alone is not
a safe skip condition. Dirty/new documents retain the ordered save path; explicit Save/close/quit and external reconciliation
retain their full disk validation. A no-op transition save is not a replacement
and must not generate self-write notifications or a redundant sidebar refresh.
Do not bypass coordination or alter initial Open's presenter-flush semantics to
make the benchmark faster. Reconciliation and real writes retain native exclusion
and current content/version validation. For an app-owned save/reconciliation,
initialize the coordinator with the existing observing presenter, as prescribed by
[NSFileCoordinator.init(filePresenter:)](https://developer.apple.com/documentation/foundation/nsfilecoordinator/init(filepresenter:)),
so our own write claim is not reported back as an external change. The existing
FIFO lane still serializes our operations; other presenters and filesystem
observations remain active. No time-window suppression or stamp-only filter is
allowed. Validate dirty transitions as well as clean switches; the clean-only
optimization alone did not remove the roughly 0.5-second self-coordination delay.
Keep the same native presenter registered while a tab still owns the same URL;
saves/reconciliations must not remove and recreate it. Refresh only the file vnode
watch after atomic replacement, retaining the parent-directory watch and presenter.
Stop/rebind the presenter only when closing or changing file identity. Verify
stable observer identity and continued detection of both atomic and direct writes.
A parent-directory write for an unrelated sibling need not reconcile every open
file when the target's device/inode still matches its active vnode watch. Never
apply this filter to target-file events or other directory event types. When
re-arming onto a different inode, always request a fresh content reconciliation;
otherwise an atomic replacement racing the re-arm could be missed. Timestamp/size
preservation must not suppress a real target update.
Keep editor-to-model snapshots as owned contiguous UTF-8 with Swift's public
`String.makeContiguousUTF8()`, rather than repeatedly comparing opaque bridged
NSString buffers across the model/save boundaries. This changes storage only,
not Unicode scalars, normalization, selection or native text. References:
[Swift's UTF-8 string model](https://www.swift.org/blog/utf8-string/) and
[SE-0247](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0247-contiguous-strings.md).
The API is declared in the installed Swift SDK. Native-buffer readiness timing
is not a physical display-frame measurement; include actual installed captures. No unbounded eager loading or synchronous
disk reads on the main actor. True external waits/errors are not evidence of
ordinary local-open performance.

While a destination is not ready, preserve the outgoing committed content without
enabling edits or selection. Keep its original binding owner until the destination is ready;
never bind the outgoing string to the loading document. Discard marked IME text
without committing it. Rapid selections, failed loads, closing and returning to the
outgoing tab must not publish stale text. Replace the buffer once with the loaded
destination. Do not use a fade, synchronous disk I/O or a replacement text control.

Reference inspected: the existing `EditorTextView.updateNSView` rebind/IME path,
`EditorTextContainerView` TextKit 2 network and workspace bottom-trailing overlay.
Reuse the native editor and [NSTextView.isSelectable](https://developer.apple.com/documentation/appkit/nstextview/isselectable)
for suspension. The earlier ProgressView overlay is explicitly rejected and must
be removed, not delayed or replaced with another spinner. No new text engine,
whole-document layout or third-party dependency is authorized.

Acceptance must cover repeated short/long, wrapped and scrolled document switches
through the production workspace host, with sequential frames as well as buffer
readbacks. A final screenshot or successful model test alone cannot prove continuity.

Historical partial repair (2026-11-03, source `1680f6b`; spinner rejected by owner): the reproduced cause was
pushing a lazy placeholder's empty string before asynchronous read completion,
not an established TextKit defect. The realistic full-workspace regression
covers loaded short/long/wrapped switches, outgoing content during a pending
load, IME discard, returning to the outgoing document, rapid requests and stale
completion/close paths. It failed before the fix and the 150-test suite passed
after it. The native TextKit 2 network and ordinary same-tab synchronization
remain unchanged.

The signed Release was launched from `/Applications/NeatEditor.app` and a
native coordinated-write hold delayed a disposable destination's read. Five
sequential captures were inspected: outgoing A, three pending states retaining
A with the native spinner, then loaded B. See `build/tab-switch/frames/` and the
matching executable receipt. These sampled frames establish buffer retention during an artificially delayed
read only. They do not establish acceptable ordinary-file open latency or owner
acceptance, nor a frame-by-frame guarantee for every file size or physical IME.
Reusable ownership/diagnostic guidance lives in the shared
[AppKit guide](~/Codes/_standards/workspace-docs/swift-docs/macos-appkit-gotchas.md#reusing-a-native-editor-during-lazy-document-loading-2026-11-03).

### Small-local-file correction acceptance (2026-11-03)

Source `3d2c26e` removes the editor ProgressView and its localization key. It
skips only clean transition writes with no pending background write, preserves
native presenter identity while refreshing replaced vnode watches, filters
unrelated sibling-directory events without filtering target-file events, and
materializes editor snapshots as contiguous UTF-8. Dirty/new and pending-write
transitions retain ordered persistence and external-content validation.

The optimized production-workspace probe used four warmed local CJK/emoji
fixtures per size and no forced layout. Median call-to-native-buffer readiness:

| Text size | Before, ordinary open | Fixed, clean outgoing | Fixed, just-edited outgoing |
|---|---:|---:|---:|
| 100 KB | about 593 ms | 47.7 ms | 60.9 ms |
| 500 KB | about 612 ms | 67.2 ms | 85.9 ms |

The maximum fixed 500 KB just-edited sample was 103.5 ms. These are small-sample
native-buffer timings, not cold-storage, cloud-provider or physical display-frame
latencies. Raw phases, source fingerprints, probe and earlier rejected trials
remain under `build/open-latency/`; final results are `utf8-clean*.json` and
`utf8-dirty*.json`. A standalone observed bridged NSString comparison probe
supported the UTF-8 storage optimization; document scalars and selection are
pinned by a native regression test.

The full Mac suite passes 158 tests in 19 suites. The shared-service iOS consumer
passes 10 simulator tests in 2 suites. Universal Mac Debug/Release build/analyze
and generic iOS-device Debug/Release build/analyze pass. Complete diagnostics are
under `build/open-latency/logs/`; only the previously assessed AppIntents metadata
notice remains. A stale generated Sparkle `.cstemp` initially blocked signing;
removing that generated temporary artifact allowed the unchanged signing checks
to pass. No diagnostics or data-safety checks were suppressed. Native Intel,
minimum-OS and physical iOS execution were not covered. The iOS caller already
avoids the Mac's per-save presenter recreation; no iOS UI/performance change is
claimed.

The same Developer ID-signed universal Release was installed and launched from
`/Applications/NeatEditor.app` (version/build remain 1.0.27/27; no public release).
Native sidebar selections opened 500 KB, 1 KB and 100 KB disposable files; selected
URL readbacks and inspected fresh screenshots agree on each destination, with
no editor loading indicator. Evidence: `installed-frames/`,
`installed-action-receipt.json` and `installation.json` under the same evidence
directory. Normal guarded quit succeeded; the fresh original workspace, folder,
tabs and selected file were restored and the installed app relaunched. No real
content was discarded, no virtual display was attached, and the task-booted
simulator was shut down.

## Settings layout revision (2026-10-18)

Keep Settings inside the existing workspace tab, including the application-menu and Command-comma entry points, under the editor exception in the macOS baseline. Use a centered 480-point native grouped `Form`: Editor (documents folder, tab behavior and language), Updates (the existing two switches), and the app icon/name/version with Check for Updates and Quit. Ordinary settings fit the supported minimum workspace height without scrolling. Remove the custom cards, focus/control borders and orphan update button.

While Settings is selected, the workspace content has a 500-point width floor and a 480-point height floor, each subject to the existing tab-strip minimum. Opening Settings grows a smaller window through the native minimum-size constraint. Document tabs retain their existing minimum. Switching back does not force the user's window to shrink.

Owner correction (2026-10-19): remove Text Softness and all three appearance sliders from Settings. Remove the obsolete interface strings and slider row implementation. Preserve the serialized rendering preferences and document appearance; this request removes the Settings control. The reduced minimum height follows the remaining content, including the language-restart notice. Language-restart guidance remains visible only when applicable. Keep the existing editor tab, document saving/quit guard and update behavior.

Owner correction (2026-10-25): choosing the documents folder is a Settings preference, not a sidebar action. Add one native labeled row to the existing Editor group, displaying the current folder name with the complete path available to accessibility and hover, plus “Choose Folder…”. Reuse `WorkspaceStore.chooseDocumentsFolder()` and its native `NSOpenPanel`, validation, immediate refresh and existing persisted `documentsFolderPath`; do not add a second preference or move existing documents. Remove the chooser from the sidebar header menu, background context menu and empty/error actions. Retain Show in Finder, Refresh and file actions. Cancelling the chooser changes nothing. Keep the complete Settings form visible without scrolling at its minimum size, including the conditional restart notice.

Installed folder-setting acceptance (`a8d526e`, 2026-10-25): the Developer ID-signed universal Release at `/Applications/NeatEditor.app` matches the built executable. The actual Settings menu opens the new row; its button opens the existing native directory panel. Selecting a temporary empty folder updates both Settings and the sidebar, persists after restart, and remains unchanged after cancelling another selection. At that revision the sidebar header menu contained only Show in Finder and Refresh (removed by the follow-up correction below); the empty sidebar has no chooser. Inspected English/dark and Chinese/light captures at the native minimum 700 × 522 pt window (200 pt sidebar, 500 pt detail), plus the English restart-notice state: the full form and about row remain visible without scrolling. Evidence is under `build/FolderSettings/`. Restored the original folder, system-language preference, normal launch arguments and 1284 × 777 pt window size; removed the empty fixture directory. No document text was edited. The 94-test arm64 suite, universal Debug analysis and universal Release build pass; complete logs are in `build/FolderSettings/logs/`. No Swift compiler/analyzer diagnostics remain; the only metadata-step warning is the existing AppIntents diagnostic assessed in [code-review.md](code-review.md#sidebar-review-2026-10-24). Native Intel/minimum-macOS execution and VoiceOver were not tested.

Component reference inspected for this row: the existing `SettingsView` grouped Form and NeatWebApp's `SettingsPanes.swift` `LabeledContent` action row; reuse its native label/control ownership, not its unrelated settings or state model. Apple's [LabeledContent](https://developer.apple.com/documentation/swiftui/labeledcontent) and [Form](https://developer.apple.com/documentation/swiftui/form) document the native settings layout; `LabeledContent` is present in the installed Xcode 27.2 SwiftUI interface. Acceptance: open Settings through the application menu/Command-comma, choose a temporary folder, inspect the sidebar update and setting readback, cancel a second selection, restart and verify persistence, then restore the original folder. Inspect the sidebar header to confirm no folder-setting entry remains.

Owner correction (2026-10-25, sidebar header follow-up): delete the ellipsis actions icon and its menu from the sidebar section header. The header shows only the current documents-folder name; choosing the folder stays a Settings preference. Keep Show in Finder (folder and files) and Refresh reachable from the sidebar's native context menus, and leave file actions unchanged. Retain the one-line middle truncation and the full path in hover/accessibility text, with no added control chrome or replacement icon. Verify the installed header in English and Chinese: the icon and its menu are absent, the folder name remains readable, and right-click still offers Show in Finder and Refresh.

Installed sidebar-header acceptance (`0786e01`, 2026-10-25): the Developer ID-signed universal Release at `/Applications/NeatEditor.app` matches the built executable. The section header renders only the documents-folder name in both English and Chinese launches; the ellipsis icon and its menu are absent. Right-clicking the header area exposes New Document, Show in Finder and Refresh, and a file row still exposes Open, Show in Finder, Rename…, Duplicate, Copy Path and Move to Trash. Inspected at 1031 × 685 pt and 640 × 530 pt (200 pt sidebar); the original 1031 × 685 pt frame, system language and `/Applications` launch were restored. Evidence is under `build/sidebar-header-icon/`. The 96-test arm64 suite, universal Debug analysis and universal Release build pass with no Swift compiler/analyzer diagnostics; the only metadata-step warning is the existing AppIntents diagnostic assessed in [code-review.md](code-review.md#sidebar-review-2026-10-24). Logs are in `build/sidebar-header-icon/logs/`. Native Intel/minimum-macOS execution and VoiceOver were not tested; the automated regression test asserts the header hosts no `NSButton`, so it guards against reintroducing an actions control.

References inspected: NeatWebApp's grouped Form/about row and NeatEditor's existing SettingsView and workspace scene. Reuse the existing public Form, Picker and Toggle controls and approved workspace host. Acceptance must inspect the installed Settings tab in dark/light and English/Chinese, check the minimum window size and complete remaining content, and verify Text Softness is absent. Existing model tests verify preference persistence; they do not establish the visual result. Research exemption: this owner-directed removal reuses the inspected existing native Settings and workspace containers and introduces no API semantics.

Current 1.0.9 diagnostics: a fresh Debug clean/build/analyze/test run passed all 51 tests in six suites. Debug reports the App Intents metadata notice assessed below; the universal Release archive additionally reports the pre-existing absent application category. The previous 1.0.8 source has no `LSApplicationCategoryType` either. Apple defines that key as the [App Store category](https://developer.apple.com/documentation/bundleresources/information-property-list/lsapplicationcategorytype); this Developer ID release retains the existing distribution metadata. Residual limitation: no declared store category; select and validate it when introducing a Mac App Store route. Xcode listed arm64 and x86_64 for the broad local Debug destination and selected native arm64; this is destination selection, not a compiler warning. The formal archive uses the generic macOS destination and explicitly builds both supported architectures. No diagnostics were suppressed.

Installed 1.0.9 (9) acceptance: the primary inspected the final stapled app's English and Chinese Settings at 500 × 502 points. Text Softness and all three sliders are absent; Editor, Updates and the complete about/update/quit row remain visible without clipping or scrollbars. This is static evidence under lock. The lock shield prevented direct resize and body-control actions; a launch-only native frame override exercised the smaller window. Dark appearance, the language-restart notice and physical interaction were not revalidated on this artifact. The launch-only dark request still rendered light and is not dark evidence. The three persisted softness values remain unchanged; opening a document can update its remembered-font recency bookkeeping. Original saved window frames were restored and the app relaunched without inspection arguments.

The public [1.0.9 release](https://github.com/NeatMacApps/NeatEditor/releases/tag/v1.0.9) contains the notarized DMG, signed ZIP and SHA256SUMS. All three complete anonymous downloads match the local artifacts; the live Sparkle feed serves build 9. The final installed app passes strict signature and stapled-ticket validation and has the same executable as the exported release. Its source snapshot is `ed157d43264d0cb6c1081e188924902d894db289`; installation did not reset rendering preferences or alter the save/quit guard.

Historical acceptance for 1.0.8 (8), before the owner removed Text Softness: English dark and Chinese light were inspected at a 500 × 632-point window, including the language-restart notice. All groups and the about row fit without clipping or settings scrolling. Command-comma reopens the Settings tab. The native slider accessibility increment changed the persisted light-appearance preference from 0.16 to 0.26; decrement restored 0.16, while the other two values remained unchanged. Pointer-drag and arrow-key automation did not move the slider, so those methods are not counted as passed evidence. The original language preference and softness values were restored after acceptance.

Historical 1.0.8 diagnostics: 51 tests in six suites passed; the scheduler suite passed again after its weak-reference warning was repaired. Release build and analyze passed. The ineffective Sparkle delegate `@preconcurrency` annotation was removed. The remaining Xcode App Intents metadata-extraction warning comes from the build tool finding no AppIntents dependency in this target: this settings change adds no intents, metadata is not required for these controls, and existing editor behavior is unaffected. Reassess the warning when an App Intents capability is introduced; no diagnostic was suppressed. The Developer ID-signed, stapled universal 1.0.8 app was installed and its Settings tab inspected again. The public [1.0.8 release](https://github.com/NeatMacApps/NeatEditor/releases/tag/v1.0.8) contains the notarized DMG, signed ZIP and SHA256SUMS; all three downloaded bytes matched, and its release-time Sparkle feed served build 8. A transient SSH transport failure was recovered from the existing verified artifacts without rebuilding or resubmitting notarization. Distribution requirements remain in `RELEASING.md`.
- Zoom commands belong to the existing native View menu, using `CommandGroup`; the app must not create a second View menu. Existing zoom shortcuts remain available.

### Startup sidebar and Settings values (owner correction, 2026-11-14)

The sidebar must publish file names/order before reading optional body previews. A slow preview must not leave an otherwise available folder behind the initial spinner. Keep enumeration and preview I/O off the main actor, preserve disk/live-buffer separation and coalescing, and reject results from a previously selected folder. Listing must not materialize iCloud/File Provider placeholders just to produce previews or sniff extensionless files; keep supported-extension rows visible without a preview, and retain the existing text-only validation for extensionless files once local. Refresh retries uncached empty previews after a file becomes local.

Inspected references: `WorkspaceStore+Sidebar.swift` refresh/cache flow, `DocumentPersistenceService+Sidebar.swift` bounded prefix readers, and `WorkspaceSidebarView`'s existing native List/empty-state overlay. Reuse these components, sort order and error/retry UI; do not add controls or hide the spinner on a timer. Apple's [download status key](https://developer.apple.com/documentation/foundation/urlresourcekey/ubiquitousitemdownloadingstatuskey) and installed Foundation headers distinguish `.notDownloaded` from local `.downloaded`/`.current`; Darwin's installed `sys/stat.h` exposes `SF_DATALESS`. A bounded read size does not bound the latency of opening a nonlocal file. The iOS consumer's existing `LibraryListing` in `LibraryFile.swift` already separates metadata listing from local-byte-only previews; retain that behavior while compiling the shared prefix guards on both platforms. The reported long launch finished before sampling, so the specific provider wait is a hypothesis, not a captured stack.

Settings: the right-hand Choose Folder button and Theme, Tab Behavior and Language choices use text only, including the selected value and popup entries. Retain the left-hand row-label icons and all other Settings actions. Reuse the inspected `SettingsView` native `Button`/`Picker` and `.labelStyle(.titleOnly)` on their localized value labels, not the row labels; no replacement controls or preference changes. Reference: [SwiftUI title-only label style](https://developer.apple.com/documentation/swiftui/labelstyle/titleonly), present in the installed SDK. The delivery tree contains only this task's label-style hunks; pre-existing uncommitted Text/model-symbol cleanup stays untouched in the working checkout.

Acceptance: hold a preview reader while requiring file rows to appear, release it and verify the preview/live-buffer result, switch folders during the hold and reject old-folder rows/errors, check nonlocal-content policy, then cold-launch the installed same-identity Release and inspect fresh sidebar and Settings pixels. Record actual launch timing and any untested provider/minimum-OS/Intel paths separately.

### Optional theme (owner request, 2026-11-05)

Add a native Theme Picker to the existing Editor settings group with Warm and White / Black choices. Warm remains the default for new and upgraded workspaces and preserves the exact existing light/dark palette. White / Black uses a white editor in light appearance and a black editor in dark appearance, with neutral gray chrome. System appearance still determines light versus dark; this is not a separate appearance override. Apply the choice immediately to the editor, line-number gutter, selected tab, tab band, sidebar, search band, empty state and character-count capsule, and persist it in the existing workspace preferences. Missing or unrecognized theme values fall back to Warm without losing other saved preferences. Do not add cloud synchronization or an extra settings surface.

Reference inspected: this product's `SettingsView` Tab Behavior / Language Pickers and `EditorChrome.adaptiveColor` appearance provider. Reuse the native SwiftUI `Picker` (segmented for these two choices), existing preference-save path and AppKit `NSColor(name:dynamicProvider:)` resolution; do not copy unrelated settings or introduce a custom control. Public references: [Picker](https://developer.apple.com/documentation/swiftui/picker), [AppKit dynamic colors](https://developer.apple.com/videos/play/wwdc2019/210/). The installed Xcode 27.2 SDK exposes these APIs. Keep all English and Simplified Chinese labels localized.

Acceptance: verify legacy decoding, both theme round trips, unknown-value fallback, both appearance palettes and live native editor/gutter/tab repaint without text, selection or undo changes. On the installed signed Release, use Settings to switch both ways, inspect fresh light/dark captures, restart to verify persistence, and check the complete Settings form at minimum size including the restart notice. Record any unavailable interaction/VoiceOver/minimum-OS coverage rather than treating model tests as visual evidence.

Installed acceptance (2026-11-05): the Developer ID-signed universal Release 1.0.28 (28) is installed at `/Applications/NeatEditor.app`. The unchanged pre-theme workspace (no `editorTheme` key, 1482 × 931 pt) reopened in Warm. The native application menu opened the Settings tab; its Theme row showed Warm selected and the complete form fit at the restored native minimum frame (captured window bounds 686 × 512 pt) without scrolling. A persisted White / Black selection rendered a pure white editor with neutral gray chrome in light appearance, survived quit and relaunch, and switched live to black editor surfaces with dark chrome when the system appearance changed to dark, without relaunching or changing document text. The original light appearance and the pre-change domain (Warm, original tabs and 1482 × 931 pt frame) were restored afterward. Evidence: `build/theme/evidence/`, command logs under `build/theme/logs/`.

Limits of that installed run: the locked session exposed no window-level accessibility tree (element lookup returned `kAXErrorAPIDisabled`), and direct pointer or keyboard events to window controls did not reach the app, so the White / Black selection was seeded into the saved workspace state before launch rather than clicked in the picker. The picker's click and keyboard path, VoiceOver, minimum-macOS and Intel execution remain unverified and need an unlocked session. The 164-test arm64 suite, universal Debug build/analyze and universal Release build/analyze pass; the only diagnostic is the existing AppIntents metadata notice.

## Floating character count

Owner correction (2026-10-29, reported on macOS 26) supersedes the former
background-free count and 24 pt shortened viewport: the count floats only in
its own bottom-right region, not in a full-width footer or clipped bottom band.
Give the count a small, opaque, editor-colored capsule so document glyphs do
not mix with the statistics. Do not add a divider, icon, hover target or popover.
The text viewport and line-number gutter both retain their full height. Font
commands stay in the native View menu and Command +/-, and Settings or an empty
workspace shows no count.

Retain 11 pt secondary text with monospaced digits, 16 pt trailing and 6 pt
bottom outer inset; local padding belongs inside the capsule. The count stays
non-interactive and passes clicks through. Add scrollable space to the native
text document, not a shorter scroll-view frame or scroll-view content inset,
so the final text line and caret can scroll fully above the count. Other text at the bottom edge remains visible
outside the count's local bounds; a background alone is not proof that the final
line is accessible. Counts are extended grapheme clusters, including spaces and
line breaks, with locale grouping separators.

Reference inspected: the existing `EditorCharacterCountView`, its workspace
bottom-trailing overlay and `EditorTextContainerView`'s scroll-view constraints.
Reuse that count/overlay and `EditorChrome.editorSurface` rather than introducing
a status bar or glass control over a flat editor. Public APIs: SwiftUI
`background(_:in:)` with `Capsule`, AppKit
[`NSTextView.textContainerInset`](https://developer.apple.com/documentation/appkit/nstextview/textcontainerinset)
and its overridable `textContainerOrigin`. Inspect and adapt only the bottom
padding/origin calculation in Christian Tietze's
[one-sided overscrolling reference](https://christiantietze.de/posts/2017/07/typewriter-mode-overscrolling/):
half the extra padding is added to the symmetric vertical inset, then subtracted
from the text origin to preserve the existing 8 pt top margin. No typewriter
mode, scroll locking or resize observer is adopted. Verify this older reference
against the current TextKit 2 engine, gutter coordinates and final-line geometry.
No input-method or count-computation change is intended.

Rejected implementation: `NSScrollView.contentInsets` retained a full-sized clip
view frame and passed geometry tests, but the installed TextKit 2 surface still
stopped drawing text above the inset while gutter labels continued to the bottom.
A full-height frame alone is insufficient evidence; check the rendered bottom
rows outside the count and the actual text viewport, not only Auto Layout.
The reusable inset/viewport lesson is maintained in the shared
[AppKit guide](~/Codes/_standards/workspace-docs/swift-docs/macos-appkit-gotchas.md#floating-content-and-bottom-text-padding-2026-10-29).

The count is computed away from the main actor and coalesced. It uses the
committed buffer, never marked IME text; superseded work must not publish after
edits or tab switches. Reporting must not change text, selection, undo, saves,
line numbers or TextKit layout.

Acceptance: type, switch tabs, compose with IME, search and resize wide/narrow;
inspect light/dark and English/Chinese. Verify the count updates live, remains
readable over the editor, leaves the final line fully visible at maximum scroll,
and disappears for Settings. Keep diagnostics and actual-path evidence under
`build/floating-count/` for the current correction (`build/character-count/` for
historical evidence); a hosted view test does not substitute for the installed UI.

Correction acceptance (2026-10-29, source `c24774e`): the complete arm64 suite
passes 119 tests in 17 suites with zero failures/skips. Debug and Release app
build/analyze pass for arm64 and x86_64; complete initial and final diagnostics
are in `build/floating-count/logs/`. The unused DEBUG profiler return-value
warning was fixed; only the individually assessed AppIntents metadata notice
remains. Frame tests cover 360/900 pt editors, full-height gutters and unchanged
8 pt top origin. Native TextKit 2 tests scroll a long wrapped CJK/emoji document's
final caret fully above the count at both 13 and 36 pt.

The same Developer ID-signed universal Release was installed at
`/Applications/NeatEditor.app` (version/build remain 1.0.25/25; no public release
requested). Inspected fresh installed captures show bottom-row text continuing
outside the local count capsule, including dense wrapped text. Verified English
at 1335 × 740 pt and Chinese at 600 × 520 pt; actual system dark-mode switching
produced the inspected dark capture, whereas the launch-only dark argument did
not. Settings has no count; the native Find command leaves the count above its
search bar. Evidence, executable hashes and restoration receipts are under
`build/floating-count/`. The original four tabs, selected file, window frame,
normal launch arguments and light appearance were restored; no document content
was edited. No virtual display was connected.

Limits: the execution host is macOS 27.2 / Xcode 27.2, not macOS 26. The locked
session permits fresh rendering and menu commands but not reliable body input;
installed pointer scrolling, typing/IME and final-line-at-maximum-scroll are not
claimed. The final-line result above is native production-view test evidence,
not installed interaction evidence. Native Intel execution is also unverified.

Historical acceptance of the superseded shortened viewport (2026-10-27):
107 tests in 16 suites, analyze and the universal
Release build passed; the only diagnostics were the existing AppIntents metadata
warnings. The Developer ID Release from `139bdce` was installed at
`/Applications`. In the installed app the count updated across tab switches,
stayed above the search bar, disappeared in Settings and remained inside the
editor at 470 × 510 points. With a 1,157-character document at maximum scroll,
the final wrapped line ended above the count; no full-width row covered the
line-number gutter. Diagnostics, install hashes and screenshots are under
`build/character-count/`.

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
| TC-15 | Enable `.*`, enter a nested-quantifier pattern such as `(a+)+$`, keep typing in the document | The app stays responsive; highlights clear and a one-line “Search timed out” status appears; no beep on timeout; a valid pattern afterwards restores highlights and clears the status | 2026-11-05 repair: nine search tests / 13 executions pass, including native interrupted computation, one-active/one-pending coalescing, stale/dismissed results and literal/regex navigation beyond match 2000. Fresh full `WorkspaceView` component captures show the timeout status, subsequent valid-query recovery and selection at match 2001. Component/receipt evidence: `~/.config/neateditor/development/release-fixes-20261105/acceptance/`; not installed-app or physical-keyboard acceptance |
| TC-16 | In a CR-only document, create a CR+LF pair at a line start (paste LF text, or another LF insertion) and check the gutter | Line numbers stay consecutive (incremental index equals a full rebuild) | 2026-11-05: unit regression passes. Installed check on 1.0.28 (28): CR-only Return and Shift+Enter LF insertion both kept consecutive numbering (1–4); the exact CR+LF merge via paste could not be delivered in the locked session, so that path remains installed-unverified |
| TC-17 | Edit tab A, switch to a not-yet-loaded tab B, let an external writer update A's file during the load, then switch back to A before B finishes loading and save | A shows the externally merged text; the old buffer is never recorded as the accepted revision, so saving does not overwrite the merge | 2026-11-05: unit regression on the deferred revision; installed check pending |

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
