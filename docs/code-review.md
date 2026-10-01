# Code review

Scope: persistence, autosave scheduling, workspace state and lifecycle,
AppKit text synchronization, preferences, accessibility, and local/public
release tooling. Behavior requirements are recorded before implementation in
[editing-text-sync-test-cases.md](editing-text-sync-test-cases.md).

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
| P1 | Tag CI published unsigned install packages and could race the local signed release. | Release correction in progress: CI must not publish unsigned public assets. |
| P2 | New-tab construction synchronously scanned a user directory. | Fixed: in-memory naming; collision safety belongs to first save. |
| P2 | App-created documents used Documents without user selection. | Fixed for new documents: app-owned config root; existing URLs are preserved. |
| P2 | Restoring a selected Settings tab foregrounded a secondary surface. | Fixed: restore documents and leave Settings to an explicit user action. |
| P2 | Search/Settings drew custom control-outline frames and Settings pickers lacked useful accessibility labels. | Fixed: remove those frames and label the native controls. |
| P2 | A standalone View command menu duplicated the system View menu. | Fixed: add zoom commands to the existing menu through `CommandGroup(after: .toolbar)`. Installed-menu verification is pending. |
| P2 | Release artifacts preceded the source commit; detached execution, notes and checksum documentation were inconsistent. | Tooling fixed; final acceptance pending worker corrections and account preflight. |

## Verification

The primary's final full test run passed 39 tests in five suites, including
a real `NSTextView.setMarkedText`/`unmarkText` composition followed by
close/save, a captured binding after tab removal, multiple first-save name
collisions, private file modes, and cancelled-predecessor cleanup. Tests use
disposable files and isolated preference suites.

Shell syntax and Python compilation pass for release tooling. Whole-tree
release acceptance, installed-app screenshots and final delivery are pending; these
statements do not claim installed or publicly notarized acceptance.

## Architecture decisions still requiring product direction

- The existing tab strip and search surface are custom implementations.
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

## Distribution limitation

The Apple notarization preflight returns HTTP 403 for a missing or expired
account agreement. See
[the account-agreement record](troubleshooting/2026-10-01-notary-agreement.md).
This blocks public notarized packaging, not committed local builds or source
publication. The account holder must resolve the agreement; changing keys or
repeatedly submitting packages does not address it.

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
