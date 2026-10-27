# Code review

Scope: persistence, autosave scheduling, workspace state and lifecycle,
AppKit text synchronization, preferences, accessibility, and local/public
release tooling. Behavior requirements are recorded before implementation in
[editing-text-sync-test-cases.md](editing-text-sync-test-cases.md).

## Persistence cleanup (2026-10-27)

Preserve the existing service facade and all editor/UI contracts. Core save,
rename, path resolution and naming remain in `DocumentPersistenceService.swift`;
`DocumentPersistenceService+Sidebar.swift` owns file discovery, bounded previews,
legacy migration and sidebar file actions. This reuses the existing no-clobber
staging/link implementation rather than introducing a dependency or a parallel
filesystem service. First-save publication and disk/live-buffer duplication now
share `publishFile(named:in:using:)`: at most 1000 candidates, extension retained,
only file-exists errors retried. Exhaustion identifies the last attempted target.
Apple documents the no-overwrite behavior of
[`copyItem(at:to:)`](https://developer.apple.com/documentation/foundation/filemanager/copyitem(at:to:));
[`linkItem(at:to:)`](https://developer.apple.com/documentation/foundation/filemanager/linkitem(at:to:))
remains the existing complete-inode publication mechanism.

A regression reproduced legacy-copy failure returning a non-nil count, which
`WorkspaceStore.refreshSidebarFiles()` treated as migration completion. Migration
now attempts remaining files but returns nil after any non-collision copy error,
so the existing completion-marker gate stays false. A concurrently claimed target
is left untouched. The failing regression passes after the fix and verifies the
original bytes, a later successful copy and an idempotent retry. Graph inspection
found one migration implementation and one completion-marker consumer in this
repository; no duplicate implementation required repair.

Full clean Debug and Release build/analyze passed for arm64 and x86_64. The
native arm64 suite passed **112 tests / 142 parameter-expanded executions**, with
zero failures, skips or runtime warnings in the structured result. Complete logs,
source-input SHA256, environment identity and XCTest results are retained under
`build/refactor-1.0.17/`. Environment: Xcode 27.2 (27B5028f), macOS 27.2 (26B118),
Swift 6 mode, pinned Sparkle 2.9.5 and deployment target 26.0. The sole retained
diagnostic is the AppIntents metadata-step notice individually assessed under
[Sidebar review](#sidebar-review-2026-10-24); no Swift compiler or analyzer warning
was found. Native Intel and minimum-macOS execution remain unverified. Release
and installed-path evidence are maintained in [RELEASING.md](../RELEASING.md).

## macOS 26 baseline (2026-10-25)

Owner requirement: minimum supported runtime is macOS 26.0. App/test deployment
settings, bundle metadata, CI and all supported-language install/build documents
must agree. The minimum toolchain is Xcode 26.0; Swift 6 language mode remains.
Universal Apple silicon/Intel distribution remains supported.

The existing native toolbar and split controller already adopt Tahoe appearance.
Reuse `WorkspaceSplitViewController.updatePinItem()` and Apple's inspected
[WWDC25 toolbar example](https://developer.apple.com/videos/play/wwdc2025/310/):
`NSToolbarItem.style = .prominent` indicates enabled pinning, `.plain` indicates
disabled pinning. The property is available from macOS 26.0 in the installed
Xcode 27.2 AppKit header. Preserve the native action, focus policy, 52 pt toolbar
and owner-retained document tabs; no new glass wrapper or custom control.

Review found that Shift+Enter manually removed one newline code unit, splitting
CRLF and overlooking NEL/paragraph separators. Use Foundation's
[`NSString.getLineStart(_:end:contentsEnd:for:)`](https://developer.apple.com/documentation/foundation/nsstring/getlinestart(_:end:contentsend:for:))
to find the content end before inserting the existing LF. Existing terminators
must remain intact; the shortcut must remain one undoable edit. The same review
found LF-only gutter indexing despite native line-range drawing; its numbering
and trailing-empty-line detection must use the same Foundation boundaries.

The initial review retained TextKit 1 because the gutter and search both used
`NSLayoutManager`. That decision was superseded by the coordinated rendering
repair in `94423bc`: the editor now constructs
`ZoomableTextView(usingTextLayoutManager: true)`, the gutter uses modern visible
layout fragments, and plain-text search decoration uses removable text-storage
attributes. Apple's [TextKit compatibility guidance](https://developer.apple.com/videos/play/wwdc2022/10090/)
explains why reading `NSTextView.layoutManager` would switch the engine back;
current product code has no such read. The installed SDK declares these TextKit
2 APIs from macOS 12, within the macOS 26 baseline. No macOS 27-only viewport API
or obsolete runtime-availability fallback is needed. The coordinated repair,
regressions and remaining actual-app/IME acceptance are owned by
[the editing contract](editing-text-sync-test-cases.md#display-only-editing-acceptance).

A clean compile also identified macOS 26's deprecated `Text + Text` operator
in the existing close-tab shortcut hint. Preserve its behavior and bold shortcut
using Apple's [Text interpolation](https://developer.apple.com/documentation/swiftui/text),
with a complete localizable sentence so translators can place the shortcut.

Retained toolchain diagnostic: universal Debug test linking reports
`_Testing_CoreTransferable ... fat file missing arch 'x86_64', file has
'arm64,arm64e'` in `NeatEditorTests`. `lipo -archs` on the installed Xcode
27.2 beta 2 testing framework confirms those two slices; the application does
not link that testing framework. The arm64 suite executes; Intel test execution
is not established. No linker suppression, dependency substitution or weakened
check was added. Recheck with a stable universal Xcode testing framework before
claiming native Intel test coverage. The separate AppIntents metadata diagnostic
retains the individual assessment below.

Baseline clean Debug build/test/analyze passed with arm64 and x86_64 compilation:
**77 tests in 13 suites executed on arm64**. Logs:
`build/macos26-review/final-checks.log`; structured result:
`build/macos26-review/FinalChecks.xcresult`. Swift compiler and analyzer emitted
no source warning/error. The two toolchain diagnostics above remain assessed.
Before the fixes, newline regressions failed on CRLF/NEL/paragraph separator;
the gutter regression failed on CR/NEL/line/paragraph separators. Final cases
cover all six native terminators, UTF-16 emoji/CJK positions, last/empty lines,
native undo and the 999-to-1000 line-number width transition.

During native-tab integration, a title-measurement helper constructed an
`NSTextField` from a nonisolated static method, producing nine AppKit isolation
diagnostics. Isolating that helper to `@MainActor` removed them. The final
implementation then removed the duplicate measurement field altogether and
measures the actual native item on its existing main actor. Pure geometry helpers
retain their current isolation.
The independent native-cell probe then isolated the title-width failures:
centred `NSTextField` cells measure four points wider than otherwise identical
left-aligned cells on this SDK. The strip was measuring a separately configured
copy and compensating with a guessed two-point inset on each side. The final fix
measures the displayed field's own cell (`cell?.cellSize.width`) and gives the
title field the full padded width, so alignment and editing style stay with the
control that renders them. AppKit keeps ownership of the exact metrics; no
magic padding remains. The API is unchanged, and regression fields must fit CJK
and long mixed-language filenames. Probe:
`build/macos26-review/measure-title.swift`.

This follows the [Swift migration guidance](https://www.swift.org/migration/documentation/swift-6-concurrency-migration-guide/commonproblems/)
and the installed SDK's NSView/AppKit isolation contract. No suppression or unsafe
actor assertion is needed. Final diagnostics must confirm removal.

After the native-tab integration and the title-cell fix, repeated clean universal
Debug build/analyze on source `2e26959`. Both architectures compiled, the full log
has only the assessed AppIntents metadata diagnostic, and structured build results
report zero compiler/analyzer issues. The final arm64 suite passed **84 tests in
13 suites**, including the CJK and long mixed-language title-fit regression and the
CRLF/Unicode newline cases. Source files were unchanged during the checks; only
documentation stayed dirty. Complete diagnostics:
`build/macos26-review/final-universal.log` and `FinalUniversal.xcresult`;
`build/macos26-review/post-alignment-test-2.log` and `PostAlignment2.xcresult`.
Release 1.0.15 was published from `98784c7`. The notarized, stapled DMG and the
Sparkle ZIP download anonymously byte-identical to the local artifacts
(`SHA256SUMS.txt` verified); the live appcast carries build 15 with an EdDSA
signature and `minimumSystemVersion` 26.0. The public DMG was mounted and installed
at `/Applications/NeatEditor.app`: the universal binary contains both slices,
`LSMinimumSystemVersion` reads 26.0, Gatekeeper reports `Notarized Developer ID`,
and the installed app launched with the mixed-language fixture documents passed to
it without a launch failure. At publication time, pixel
inspection of the new tab widths could not run because Screen
Recording and Accessibility access were unavailable to that execution host; the production control's
geometry is covered by the passing native title-fit test, and the earlier pin and
newline screenshots predate this title-sizing change.

Installed native pin acceptance: the exact installed application PID was
resolved by bundle path, activated, and its actual `Always on Top` toolbar
button received accessibility press. The window level changed 0 → 3 → 0;
inspected `/tmp/neateditor-macos26-pin-active.png` and
`/tmp/neateditor-macos26-unpinned.png` show prominent filled-pin and ordinary
pin states without a focus ring. Restored unpinned state. Both installed binary
slices and `LSMinimumSystemVersion` read back `26.0`. The final committed-gutter Debug was then installed. Inspected
`/tmp/neateditor-macos26-lines.png`: all six terminators render as logical lines
1–7. The actual editor received Shift+Enter at a UTF-16 selection before CRLF;
AX text and autosaved fixture bytes exactly matched the expected preserved CRLF.
A later unguarded Command-Z after autosave did not change the fixture; subsequent
inspection found the app inactive. Native undo passes the unit window test, but
this installed shortcut attempt is not accepted. Recheck with fresh input ownership
before claiming that path. These captures establish the earlier compatibility
fixes; they do not establish acceptance of later tab or TextKit 2 changes.

### Follow-up after concurrent updates

The [published 1.0.15](https://github.com/NeatMacApps/NeatEditor/releases/tag/v1.0.15)
snapshot is `98784c7`; its release-validation workflow
[passed on Xcode 26.0.1](https://github.com/NeatMacApps/NeatEditor/actions/runs/40172972989).
The [runner's official tool inventory](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-Readme.md)
still includes that compiler and macOS 26.0 SDK. The later TextKit 2, live-resize
and trailing-toolbar fixes are newer than that public snapshot; do not attribute
them to the published assets. They retain the 26.0 deployment target and need
their own local acceptance and the next release-train publication.

On 2026-10-25, the installed bundle's `LSMinimumSystemVersion` and both binary
slices' `LC_BUILD_VERSION.minos` independently read back 26.0. The host remains
macOS 27.2 on Apple silicon: this establishes the declared runtime requirement,
not native Intel execution or a macOS 26 runtime test.

Independent follow-up checks cover the integrated source now committed as
`a4322bc`, including the TextKit 2 repair, toolbar alignment and taller native
tabs. A clean universal Debug build, arm64 execution of **94 tests in 13 suites**,
static analysis and a universal Release build all passed. The source/config/test
input digest stayed unchanged through both configurations:
`d1e23e72e2685d131102a7fdbc8b3690154cbb4d36694553ead6f9533e849492`.
Full diagnostics and structured results are retained at
`build/macos26-review/followup-final-{debug,release}.log`,
`FollowupFinalDebug.xcresult`, `FollowupFinalRelease.xcresult` and
`followup-final-checks.json`. No source/compiler or analyzer issue was reported;
only the individually assessed AppIntents metadata diagnostic and test-only
Intel framework warning above remain.

The installed Release's current editor surface was passively captured and
inspected at `build/macos26-review/followup-installed.png`: wrapped CJK text has
one gutter label per logical line. This static capture predates the taller-tab
installation and does not replace that change's interaction acceptance. Existing
user tabs and the active UI agent's application session were left intact.

## Findings and disposition

| Priority | Finding | Disposition |
|---|---|---|
| P0 | A failed lazy read became editable error text and could overwrite the original on lifecycle save. | Fixed: keep failed reads unsaveable, show a native alert, and allow retry. |
| P1 | First saves could overwrite a different file with the same name. | Fixed: write one complete private staging file and claim a free final name without overwriting. Name collisions do not repeat content writes. |
| P1 | Close and Close Other Tabs removed a buffer after a failed save; quit had no save-failure veto. | Fixed: propagate save success, keep tabs open, and use `applicationShouldTerminate` to veto failed saves. |
| P1 | A delayed editor report used an array index that could refer to another tab after removal. | Fixed: bindings resolve tab IDs at access time. |
| P1 | An old same-tab snapshot could overwrite rapid edits; the regression passed the new text instead of the old one. | Fixed: AppKit edits own the live buffer until a tab switch; regression now supplies old text. |
| P1 | Composition was committed during a later view update, after the old tab had already been saved or closed. | Fixed: weak native-editor commit hook runs before the save snapshot. |
| P1 | Cancelled or reentrant autosave tasks could discard a replacement's cancellation handle. | Fixed: unique pending-operation identity, weak lifetime, and bounded bookkeeping. |
| P1 | Tag CI published unsigned install packages and could race the local signed release. | Fixed: tag CI is validation-only with read-only contents permission; public DMG/ZIP come from the local signed/notarized release. |
| P2 | New-tab construction synchronously scanned a user directory. | Fixed: in-memory naming; collision safety belongs to first save. |
| P2 | Document default location changed during the review. | Superseded by the owner's 2026-10-24 decision: use Documents by default with a remembered folder picker; legacy app-library files are copied without overwrite or deletion. See the persistence KB. |
| P2 | Restoring a selected Settings tab foregrounded a secondary surface. | Fixed: restore documents and leave Settings to an explicit user action. |
| P2 | Search/Settings drew custom control-outline frames and Settings pickers lacked useful accessibility labels. | Fixed: remove those frames and label the native controls. |
| P2 | A standalone View command menu duplicated the system View menu. | Fixed: add zoom commands to the existing menu through `CommandGroup(after: .toolbar)`. Installed-menu verification is pending. |
| P2 | Release artifacts preceded the source commit; detached execution, notes and checksum documentation were inconsistent. | Fixed and exercised for 1.0.14: commit-first universal archive/export, app/DMG notarization, draft-only uploads, downloaded-byte verification and signed appcast. |
| P2 | Hosting document tabs in an `NSToolbarItem` removed the old title-bar drag: dragging a tab no longer moved the window. | Fixed: the tab-strip monitor tracks the press, moves the window after 4 points, clamps it on screen, and leaves clicks to SwiftUI. Installed drag verified from a tab (window origin 100,100 → 280,200). |
| P2 | The tab toolbar item's maximum width refreshed only on split-view resize, so widening the window kept a 398 pt strip and hid tabs despite free toolbar space. | Fixed: derive the width from the current content layout width on `NSWindow.didResizeNotification`, update the tab host synchronously, and revalidate toolbar items. Installed Release verified at 700/1150/1330 pt and with 191 live-drag frames across both sidebar states. |

## Sidebar review (2026-10-24)

The layout requirement and inspected native reference are recorded in
[TabStripGestures.md](../TabStripGestures.md#product-requirements).
The sidebar uses `NSSplitViewController`, `List(selection:)` and a real
`NSToolbar` with a tracking separator. Tabs are custom content of that same
native toolbar row above the detail column, not a second content row; search
stays inside the detail column. Native window controls are no longer manually
repositioned. An installed two-row NavigationSplitView attempt was rejected
by the owner and its assetless release draft was stopped before publication. Detail minimum widths protect
the editor and existing Settings form when the sidebar is visible.

Fixed refresh-time snapshots overwriting newer edits, live-preview cache
contamination, silent folder enumeration failures, disk-only duplication of
open buffers, duplicated rename rules and missing closed-file font migration.
Preview reads are unconditionally bounded, CRLF is one line break, duplicate
normalized URLs cannot crash cache reconstruction, and rename handoff is
MainActor-isolated rather than using `nonisolated(unsafe)`. Failed trash
operations on open files now present the same native error as closed files.

Debug build, the full 65-test suite and static analysis passed on Xcode 27.2 /
macOS, arm64. Added regressions cover refresh ordering, cache isolation,
unsaved duplication, folder failure retention and CRLF. Complete diagnostics
are retained under `build/sidebar-review/`. One test-only unused binding
warning was fixed and the full suite rerun.

Retained diagnostic: `appintentsmetadataprocessor: Metadata extraction skipped,
no AppIntents.framework dependency found`, app/test-host build steps. The app
does not import AppIntents or declare intents, so there is no metadata to
extract; this is an Xcode metadata-step diagnostic, not a sidebar or Swift
compiler defect. No suppression or artificial framework dependency was added.
Residual limit: no Shortcuts metadata is produced. Reassess if App Intents
are adopted. Universal archive also exposed a missing application category;
set the existing editor's category to Productivity instead of suppressing
that diagnostic. Installed visual and universal Release acceptance are recorded
below after verification.

## Verification

Final integration acceptance (2026-10-25): source `275a50a`, release 1.0.14,
installed at `/Applications/NeatEditor.app`. All intervening 1.0.12/1.0.13
folder, window-drag and stepped-tab join changes were preserved; the only
production-code change for 1.0.14 configures native toolbar item focus rings.

- Clean Debug build/test/analyze: **72 tests in 11 suites passed**, arm64,
  Xcode 27.2. Full diagnostics: `build/sidebar-review/integration-1.0.14-clean-checks.log`.
  Three native-toolbar regressions cover the built-in Sidebar action, shared
  item-view policy and incomplete notifications. Existing persistence, IME
  commit, identity, first-save, folder and autosave regressions remain green.
- Universal Release archive/export compiled arm64 and x86_64. Both configurations
  retain only the AppIntents metadata diagnostic assessed above; no Swift
  compiler or static-analysis warning/error was found.
- Native Sidebar accessibility press reproduced a blue focus ring in 1.0.13.
  The same path in installed Debug and signed Release 1.0.14 has no ring.
  Native `.toggleSidebar` and its original action remain in use; only its
  public `item.view.focusRingType` changes, with no private hierarchy traversal.
- Inspected expanded/collapsed screenshots and selected different tabs in both
  states. Repeated four native toggles, resized to 470 × 570 and back, and
  confirmed the selected stepped tab stays visible and joins the continuous
  editor top rule once layout settles. Sidebar filenames did not reorder.
- Actual tab drag moved the window from (1008,255) to (1061,291); sequential
  captures retained the same selected document and no rename field. A temporary
  empty tab exercised new-document, selected-tab double-click, Escape rename
  cancellation and Command-W closure (four → five → four tabs). Pin/unpin changed
  the actual window layer 0 → 3 → 0. No real document content was edited.
- Inspected signed Release light/dark captures; restored the initial light
  appearance, unpinned state, normal size and original selection. Captures are
  `/tmp/neateditor-1.0.14-release-*.png`; diagnostics are under `build/sidebar-review/`.
- Application and DMG passed notarization and staple validation. All three public
  assets were anonymously downloaded and compared byte-for-byte with the local
  artifacts; DMG and ZIP SHA256 checks passed. The live appcast contains build 14
  and its EdDSA-signed update URL. Installed and exported binary SHA256 match.

Limits: execution was on macOS 27.2/Apple silicon, not native Intel or a minimum-OS
machine. Full-screen/Split View, Settings and physical IME interaction were not
rerun in this bounded pass. This host reports Gatekeeper security disabled;
its `accepted` output is not a clean-machine enforcement test. Apple's accepted
submissions and stapled tickets independently establish notarization.

## Architecture decisions still requiring product direction

- The owner explicitly retained the existing rounded stepped document tabs;
  this scoped exception is recorded in `TabStripGestures.md` and must not be
  silently replaced by a segmented picker. The search surface is also custom.
  Apple's native search integration is `NSTextView.usesFindBar`, backed by
  `NSTextFinder` and `NSScrollView`. A container migration must first reconcile
  the existing regular-expression and rename interactions with native
  behavior. No replacement search control was added in this review.
- Closed-tab snapshots retain document strings without a bound. A retention
  limit would change how far Reopen Closed Tab can go; no arbitrary limit was
  introduced without that decision.
- Large-file saves are synchronous on the main actor. Moving them off-thread
  requires ordered saves plus close/quit completion semantics; no unverified
  asynchronous rewrite was added.

## Distribution status

The earlier account-agreement HTTP 403 is historical, not a current blocker;
see [the account-agreement record](troubleshooting/2026-10-01-notary-agreement.md).
Both 1.0.14 notarization submissions were accepted. A subsequent GitHub SSH
transport failure was recovered over authenticated HTTPS using the existing
credential helper and hooks, without rebuilding or resubmitting accepted bytes.

Published [1.0.14](https://github.com/NeatMacApps/NeatEditor/releases/tag/v1.0.14)
contains the signed/stapled DMG, signed update ZIP and their checksum file.
The install is Developer ID-signed, universal and stapled. Release logs:
`build/release-logs/publish-20261025-100230.log` and `resume-1.0.14.log`.
Publication-only recovery and the remaining tooling improvement are documented
in [RELEASING.md](../RELEASING.md#publication-only-recovery).

## Primary references

- [Apple text view](https://developer.apple.com/documentation/appkit/nstextview)
- [Apple termination delegate](https://developer.apple.com/documentation/appkit/nsapplicationdelegate/applicationshouldterminate(_:))
- [Apple native alert](https://developer.apple.com/documentation/swiftui/view/alert(_:ispresented:presenting:actions:message:))
- [Apple native find bar](https://developer.apple.com/documentation/appkit/nstextview/usesfindbar)
- [Apple native command group](https://developer.apple.com/documentation/swiftui/commandgroup)
- [Swift cooperative cancellation](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/)
- [Apple exclusive data write](https://developer.apple.com/documentation/foundation/nsdata/writingoptions)
- [Apple hard-link publication](https://developer.apple.com/documentation/foundation/filemanager/linkitem(at:to:))
- [Sparkle publishing](https://sparkle-project.org/documentation/publishing/)
