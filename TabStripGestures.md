# Workspace Sidebar and Tabs

## Product requirements

Owner corrections (2026-10-24):

- The native sidebar occupies the entire leading window area, including the
  background behind the native traffic lights, and reaches the bottom.
- Dragging anywhere in the tab strip, including on a tab or its empty
  background, moves the window, matching the old title-bar behavior. A press
  below the drag threshold remains a normal click; a drag must not select or
  rename the tab where it started.
- Window controls, sidebar toggle, document tabs, New Document and pin share
  **one top row**. No separate toolbar row above the tabs.
- Tabs begin in the editor column, not above the sidebar. Search and document
  notices remain in the editor column.
- Closing the sidebar leaves no rail and never removes the tab control.
  Repeated collapse/expand and minimum-window resizing must keep tabs clickable.
- Sidebar files use descending natural filename order with a path tie-breaker.
  Save/autosave and tab switching do not change their positions. Creating or
  renaming files may change their positions.
- Owner correction: preserve the existing rounded, stepped document tabs joined
  to the editor surface. The owner explicitly rejected replacing this component
  with `NSSegmentedControl` and instructed continuation of its restoration.
  This is a scoped exception for the existing document-tab component, not
  permission to replace native sidebar, toolbar, window controls or other UI.
  Fix continuous outlines without changing that design. Manual traffic-light
  placement remains prohibited.
- Owner request (2026-10-26): the sidebar follows the active document. Switching
  to a document whose sidebar row is scrolled out of view — for example from the
  top tab band — scrolls the sidebar until that row is visible. A row chosen
  directly in the sidebar never moves the list, and ordinary refreshes, preview
  updates or typing never move it either. The restored document is located once
  at launch and after the sidebar is expanded.

## Compact 40 pt top row (owner decision 2026-10-25, authoritative)

The owner rejected the system-standard 52 pt toolbar for this minimal editor:
the design philosophy includes using as much screen space as possible for text.
The owner chose a compact single row and explicitly approved removing the
toolbar's items and glass controls for this window. Owner follow-up: 32 pt felt
over-compressed; use the native 40 pt compact row. This is an owner exception for the workspace window's top row
only; sidebar, split view, window controls and editor remain native.

- The window carries an **empty** `NSToolbar` with `.unifiedCompact` style only
  to obtain the native 40 pt row (measured on macOS 27.2; traffic lights and
  leading accessories centred 20 pt from the top). A bare titlebar is 32 pt and
  accessories cannot make it taller; no public API gives a height in between
  without de-centring the traffic lights. The toolbar has no items, no
  customization and no display-mode menu. Traffic lights stay system-placed.
- The programmatically created toolbar's delegate implements all three required
  item methods, including an item factory returning `nil` for every identifier.
  Empty identifier lists alone let Swift compile but AppKit rejects the delegate
  at runtime (`invalid delegate ... does not implement all required methods`).
  The release gate reproduced this in the native titlebar tests. Reuse the
  existing `WorkspaceSplitViewController` toolbar and lists; supply only the
  missing [native item factory](https://developer.apple.com/documentation/appkit/nstoolbardelegate/toolbar(_:itemforitemidentifier:willbeinsertedintotoolbar:)).
  Apple's documentation and the installed Xcode 27.2 `NSToolbar.h` require it
  even though the Objective-C protocol declares the method optional.
- Sidebar toggle: a native borderless `NSButton` (`sidebar.left`) in a
  `.leading` `NSTitlebarAccessoryViewController`, so AppKit places it beside
  the traffic lights. It calls `NSSplitViewController.toggleSidebar(_:)`.
- Pin: a native borderless `NSButton` at the trailing end of the editor
  column's band, a peer of New Document: the same 13 pt symbol size, secondary
  colour and centre line as `+` and the tab titles, 6 pt clear of the window's
  rounded corner. `pin`/`pin.fill`, accent tint while pinned, the existing
  Enable/Disable Always on Top tooltips. (Owner: the earlier 15 pt corner
  accessory, 3 pt higher than `+`, looked ugly.)
- New Document: a borderless `plus` button immediately after the last tab, owned
  by the tab strip; when tabs overflow it stays at the strip's trailing edge.
- No glass capsules: a 36 pt glass item cannot fit a 32 pt row, and the capsules
  were the main source of top-row weight. Buttons never draw focus rings.
- The tab strip is a native sibling in the editor column's top band (titlebar
  height, at least 40 pt), excluding the sidebar accessory and the pin slot. With the sidebar
  collapsed it starts after the sidebar button; with it expanded it starts at
  the editor column. Blank strip space still hit-tests through to native
  titlebar drag/double-click.
- Tabs: 30 pt tall, bottom-aligned with the editor, 13 pt regular titles,
  168 pt equal slots, 12 pt title padding, 7 pt corners; the stepped
  editor-joined shape and separator-colour outline are retained.
- Supersedes: the 52 pt `.unified` toolbar, toolbar item focus/`.prominent`
  pin policy, tracking separator and flexible-space notes below, and the
  38 pt / 14 pt tab sizes. Those sections remain as history.
- Reference: local probe windows (`NSTitlebarAccessoryViewController`
  `.leading/.trailing` stayed 32 pt even when taller; an empty `.unifiedCompact`
  toolbar gave 40 pt; content views in the titlebar band receive hits). Apple [NSTitlebarAccessoryViewController](https://developer.apple.com/documentation/appkit/nstitlebaraccessoryviewcontroller)
  `layoutAttribute` supports bottom, leading and trailing.

## Native implementation and reference

`WorkspaceSplitViewController` uses `NSSplitViewController`, a full-height
`NSSplitViewItem(sidebarWithViewController:)`, and one `NSToolbar`.
`NSTrackingSeparatorToolbarItem` aligns toolbar and sidebar. Native items own
sidebar toggling, new-document and pin actions. The tab toolbar item is
unbordered; its minimum and maximum widths use constraints rather than deprecated
`NSToolbarItem.minSize/maxSize`. The width is **not** a required detail-column
width: the hidden-sidebar layout also needs space for native window controls.
Tabs have user visibility priority so actions overflow before document selection.

Toolbar controls must not draw focus rings after mouse, accessibility or keyboard
activation. Installed 1.0.13 exposed a blue ring on the native Sidebar button
through its actual accessibility press. Preserve AppKit's built-in items and
set `item.view?.focusRingType = .none` in `toolbarWillAddItem(_:)`, using public
`NSToolbarUserInfoKey.itemKey`; do not search private titlebar descendants or replace
the native button. Apply the same policy to all items so New Document and pin
cannot repeat the defect. Reference: the installed built-in `.toggleSidebar`
item's public `view` is an `NSButton`; public callback/key/property verified
against Xcode 27.2 headers and [Apple's focus ring API](https://developer.apple.com/documentation/appkit/nsview/focusringtype).

### Tab implementation rewrite (owner direction 2026-10-25)

The owner approved replacing the scattered tab implementation, not another
geometry-delay patch. Scope is the document-tab component and its editor join;
retain the stepped appearance, one toolbar row, native surrounding controls and
all existing document actions. Editor buffers, save/restore and sidebar behavior
are not redesigned.

`EditorTabStripView` is a native toolbar `NSView`, owning one `NSScrollView`,
stable-ID tab views and immediate selection reveal. Each `EditorTabItemView`
keeps its native `NSTextField`, fill and open outline in the same local bounds.
All tabs use one fixed slot width (184 pt; see Toolbar height below), independent of title or selection.
The native title field truncates at the tail; full filenames remain available
through the existing tooltip and accessibility label. Overflow still reveals
the selected tab synchronously; do not make a long filename widen one slot.
`WorkspaceSplitViewController` attaches the editor's native top-rule view as a
sibling above hosted content, anchored to the native top safe area below the
toolbar rather than the full-size content view's top edge. That
view converts the current selected tab and viewport into its coordinates when
it draws; it never consumes a cached frame or asynchronously published gap.
SwiftUI passes immutable tab descriptors and action callbacks only. Remove the
old frame preferences, cross-host observable geometry, global pending rename and
separate SwiftUI/AppKit event-monitor machinery.

The strip owns pointer tracking and applies the existing four-point window-drag
threshold; it records initial pointer/window origins and clamps the moved window
to remain partly visible. A completed drag never selects or renames. Keep this
scoped manual move because the previous toolbar-hosted implementation verified
that `NSWindow.performDrag(with:)` did not move this custom toolbar item. Native
AppKit still owns empty chrome outside the tab component. Rename state belongs
to the strip and uses the standard field editor, not a global draft. An outside
click or app deactivation commits; Escape cancels.

Inspected implementation references: this repository's existing stepped curve
and installed 1.0.14 appearance; MacVim's `src/MacVim/MMTabline/MMTabline.m`
(`layout`, native scroll/document container) and `MMTab.m` (local tab drawing
with a native title field), inspected from the current upstream source. Reuse
that ownership pattern, not its appearance, extra buttons, tab-reordering,
animations, legacy availability branches or Vim-specific behavior. No external
source/dependency is copied. The owner's existing scoped custom-tab exception
continues; this is not a replacement for surrounding native toolbar controls.

Public APIs checked against Apple's documentation and installed Xcode 27.2 SDK:
[NSToolbarItem.view](https://developer.apple.com/documentation/appkit/nstoolbaritem),
[NSView](https://developer.apple.com/documentation/appkit/nsview),
[NSScrollView](https://developer.apple.com/documentation/appkit/nsscrollview),
[NSTextField](https://developer.apple.com/documentation/appkit/nstextfield),
`NSView.convert(_:from:)`, `NSClipView.scroll(to:)` and native field-editor
commands. No private chrome traversal or manual traffic-light positioning.

On macOS 26+, the native pin item uses `NSToolbarItem.style`: `.prominent`
while pinned and `.plain` otherwise. This reuses the existing pin item/action
and Apple's WWDC25 toolbar state example, not a separate glass view. The item
continues to follow the shared focus-ring policy.

### Trailing toolbar actions (owner report 2026-10-25)

- New Document and pin remain at the native trailing window margin with the
  sidebar both expanded and collapsed. Opening the sidebar must not leave an
  extra empty region to the right of these actions. Preserve their native size,
  grouping, actions and the existing single-row tab design.
- Reuse this controller's existing `NSToolbar` items and add AppKit's standard
  `.flexibleSpace` between the document tabs and the trailing actions. A tab
  item's maximum width only caps its size; it does not consume the remaining
  toolbar space. Do not compensate with sidebar-dependent button offsets.
- Reference inspected: `WorkspaceSplitView.swift`'s default item order and
  tab-width constraint, compared with the owner's expanded/collapsed captures.
  Apple's [flexibleSpace](https://developer.apple.com/documentation/appkit/nstoolbaritem/identifier/flexiblespace)
  supplies the missing flexible width; the identifier is declared in the
  installed Xcode 27.2 `NSToolbarItem.h`. No replacement controls are needed.
- Verify the installed app by pressing the actual Sidebar toolbar button at
  normal and narrow window widths, including a resized sidebar. Compare both
  action frames and screenshots against the native trailing margin.

Installed alignment verification (`b5d5065`, 2026-10-25): the signed universal
Release was installed at `/Applications/NeatEditor.app`; its executable hash
matches `build/ToolbarAlignment`'s product. At 470 × 641 pt with the sidebar
expanded, the native pin item's trailing edge is 4 pt from the window edge.
The inspected `build/toolbar-alignment-logs/470-expanded-installed.png` removes
the extra right-hand gap visible in the owner's capture. The arm64 suite passes
92 tests, including the native spacer/order regression for both sidebar states;
universal Debug analysis and Release compilation pass. Complete diagnostics are
in `build/toolbar-alignment-logs/`; only the previously assessed AppIntents
metadata-step warning remains (see `docs/code-review.md`). The analyzer command's
ambiguous destination warning selected this Mac; explicit `ARCHS` compiled both
slices. Native Intel execution is not established. The session locked after the
first installed accessibility readback, so repeated button toggling, divider
resizing and the collapsed-state screenshot were not accepted; static captures
after lock are not transition evidence. No document text or window size changed.

### Live resize synchronization (owner report 2026-10-25)

- During continuous window resize, the selected tab's filename, fill and raised
  outline must move as one object, including when overflow reveals the selection.
  Alignment only after releasing the resize gesture is not sufficient.
- The filename, fill and raised outline share one native tab view and one scroll
  transform. The editor rule reads live native geometry during drawing. No
  geometry travels through SwiftUI preferences, tasks or next-run-loop callbacks.
- Reuse the existing `ConnectedTabGeometry` curve; preserve horizontal viewport
  clipping and the bottom half-point join. Partial-patch motion capture showed
  that a local outline alone did not fix the asynchronously positioned rule gap;
  both parts must pass the same continuous-resize acceptance.
- Reveal selection during the same native layout pass after selection, tab-size
  or viewport-size changes. Do not animate or queue resize reveals.
- The tab toolbar item's maximum width must follow every window resize, not only
  split-view or sidebar changes. Derive it from the window's current content
  layout width minus the visible sidebar and divider, and update it synchronously
  from the native resize callback. Otherwise widening leaves a stale narrow strip
  that hides tabs while both buttons and window space remain free.
- Acceptance requires sequential frames during repeated fast shrink/expand and
  direction reversals, with sidebar both visible and hidden and a trailing tab
  selected. A settled screenshot or a passing build is not motion evidence.
  Verified on the installed 1.0.15 release: 85 visible-sidebar and 106
  hidden-sidebar frames across roughly 700–1330 pt widths, plus settled 700/1150/
  1330 checks. The selected filename, fill and outline stayed in one frame, and
  the strip width tracked the window instead of retaining a 398 pt cap.

### Toolbar height and editor top rule (owner direction 2026-10-25)

- Owner principle (2026-10-25): NeatEditor is a minimal text editor whose design
  philosophy includes using as much screen space as possible for text. The
  system-standard 52 pt toolbar height does not fit that philosophy. Decided:
  see "Compact 40 pt top row" above.
- Measured on macOS 27.2 (probe windows, `frame.height - contentLayoutRect.height`):
  titlebar only 32 pt (traffic-light centre 16 pt from top); `.unifiedCompact`
  40 pt (centre 20 pt, sidebar item 24 pt tall); `.unified` 52 pt in this app.
  No public API sets an intermediate toolbar height.

- Use the native `unified` toolbar (52 pt), not `unifiedCompact` (40 pt), so
  the native glass items keep their standard control size. The owner compared
  the top-right New Document and pin actions with Corral's top bar; compact
  glass (24 pt tall) clamped the glyphs and read as cramped. The installed
  unified toolbar draws 36 pt glass, the same as the reference.
- Owner correction (2026-10-25, later; supersedes the same day's 44 pt / 15 pt
  enlargement): the tabs read as too large and dominant. Keep the native 52 pt
  row, its standard glass controls and the stepped, editor-joined shape, but
  lower the tabs' visual weight. Owner follow-up: the 32 pt / 13 pt version
  felt empty; settle midway at 38 pt tall, bottom-aligned with the editor,
  8 pt corners, one fixed 184 pt slot width, 16 pt horizontal title padding.
  The remaining top gutter is window chrome, not tab content; do not enlarge
  the toolbar or introduce another row.
- Filenames use a 14 pt system font, between the 13 pt macOS default (HIG
  body) and the rejected 15 pt, so navigation stays quieter than document text
  and does not follow editor zoom. Selection is expressed by color, not
  weight: the selected title uses the primary label color, others the
  secondary label color, both regular weight. Reuse the
  existing native `NSTextField` and center it by its `intrinsicContentSize`;
  no fixed title box or clipping of CJK glyphs/Latin descenders.
- The selected tab's raised outline and the editor's top rule share one
  1 pt native `separatorColor` stroke (`EditorChrome.tabOutlineColor`), so the
  open join still meets on a single line and the outline recedes behind text. Reference: [Apple HIG typography](https://developer.apple.com/design/human-interface-guidelines/typography)
  (macOS default 13 pt; tab titles do not grow with content text size).
- Unselected tabs have no rounded-rectangle hover fill. The owner identified the
  previous capsule as a leftover background; only the selected stepped tab owns
  a fill and raised outline. Switching, scrolling and resizing must leave no
  extra background behind an inactive filename.
- Blank space within the custom toolbar item's bounds (above the tabs or after
  the last tab) must hit-test through to native window chrome. AppKit owns its
  double-click action and drag, including the user's Desktop & Dock preference.
  Do not manually invoke zoom/miniaturize or emulate the preference.
- Component reference inspected: `EditorTabStripView.layout/hitTest`,
  `EditorTabItemView.draw/layout` and the owner's two captures. Reuse the local
  `ConnectedTabGeometry` stepped curve and native toolbar; change height, field
  centering and event ownership only. Apple's public
  [NSView.hitTest](https://developer.apple.com/documentation/appkit/nsview/hittest(_:))
  allows blank regions to return nil; its
  [mouseDownCanMoveWindow](https://developer.apple.com/documentation/appkit/nsview/mousedowncanmovewindow)
  keeps native window event propagation. Check these declarations in the
  installed SDK. [Apple's window guide](https://support.apple.com/guide/mac-help/work-with-app-windows-mchlp2469/mac)
  confirms titlebar double-click follows Desktop & Dock settings. Installed
  acceptance must verify the actual blank regions, not a direct zoom call.
- Owner color correction: the selected tab and the content surface it joins
  must resolve the same background color in light and dark appearances,
  including Settings and other non-text content. Use one `EditorChrome` AppKit
  color shared with SwiftUI, and paint the entire detail body; the Settings
  host's default window background previously exposed a subtle darker-tab seam.
  Native toolbar glass remains native; do not flatten it to hide the mismatch.
  Verify colors on both sides of the open join, not only text-editor tabs.
- The editor column owns the full-width 1 pt top rule. It is not drawn when
  there are no tabs, and it leaves an open span under the selected tab's join.
  The tab strip draws only the raised tab outline; both strokes are measured
  in AppKit window coordinates so they meet on one line instead of stepping at
  the tab's bottom corners.

Inspected component references:

- [Apple MacLandmarks LandmarkList](https://developer.apple.com/tutorials/swiftui/creating-a-macos-app):
  native sidebar `List(selection:)`; adapted to NeatEditor's file list.
- [CotEditor](https://github.com/coteditor/CotEditor):
  `CotEditor/Sources/Document Window/WindowContentViewController.swift` and
  `DocumentWindowController.swift` for native split items and toolbar tracking;
  its split and toolbar mechanisms remain applicable. Its inspector segmented
  tabs do not match the owner's required document-tab appearance and must not
  replace the existing stepped component. No domain logic, dependencies or
  private workarounds are copied.

Official applicability and installed Xcode 27.2 SDK checked:

- [NSSplitViewController](https://developer.apple.com/documentation/appkit/nssplitviewcontroller)
- [NSToolbarItem](https://developer.apple.com/documentation/appkit/nstoolbaritem)
- [Constraint-based toolbar sizing](https://developer.apple.com/documentation/macos-release-notes/appkit-release-notes-for-macos-10_14)
- [NSSegmentedControl](https://developer.apple.com/documentation/appkit/nssegmentedcontrol)

## Interaction contract

- Single click selects immediately; no multi-click recognition delay.
- A left drag beginning on a tab moves the window after a 4-point threshold.
  Pointer tracking distinguishes a click from a drag; only a completed drag
  suppresses the tab action. Blank strip space passes through to native chrome
  for window dragging and double-click. The inline rename field remains a
  native text field and is not a window-drag surface.
- Double-click a tab that was already selected on the first click to rename
  inline. Double-clicking an inactive tab selects it without starting rename.
- Enter, clicking outside or switching apps commits rename. Escape cancels it.
- Context menus preserve Show in Finder, Rename, Close, Close Other Tabs and
  Move to Trash where applicable. Middle-click closes the hit tab.
- Scroll-wheel/trackpad tab stepping keeps the existing sensitivity and ignores
  momentum. Selection is revealed when clipped, including after a resize.
- Native AppKit owns all blank-titlebar double-click and dragging, including
  blank space within the tab toolbar item. Never
  separately call zoom/miniaturize for the same event: that caused the earlier
  enlarge-then-immediately-restore regression.
- Pin changes the native window level. Existing topmost hover-focus protection
  and debounce remain in `WindowPinningView`.

## Sidebar row consistency

Owner follow-up (2026-10-25): every file entry has the same height, including
empty files and files with short or multiline previews. Keep one filename line
and two reserved preview lines, aligned to the same leading edge. The native
sidebar list retains selection, scrolling, context menus and accessibility.
Long filenames/previews truncate at the tail; content does not enlarge the row.

### Active-document reveal

The native `List(selection:)` remains the owner of selection styling and
scrolling; `WorkspaceSidebarView` wraps it in `ScrollViewReader` and gives every
row its normalized file URL as its scroll id. Reveal calls `scrollTo(url)` with
no anchor. SwiftUI List scrolls the minimum needed to make the row wholly
visible: a partially visible row shifts slightly, while a far row settles at the
leading edge. Do not animate or center the reveal, so locating a file stays
predictable and matches the tab band's instant reveal.

Reveal is requested when the active document changes (tab band, menu command,
external open, reopen, close fallback), when the sidebar expands, and once for
the restored selection when the file list first becomes available. Because an
open/new file may appear only after the asynchronous sidebar refresh, a pending
reveal retries when the list's file URLs change. Preview-only updates must not
trigger reveal, and a plain refresh must not pull a deliberately scrolled-away
list back to the selection.

A selection made directly in the sidebar is exempt: `WorkspaceStore.openSidebarFile`
records `sidebarOriginatedSelectionURL`, and the sidebar consumes it when the
active document changes. `List.scrollTo` would otherwise move an
already-clicked row to the top under the pointer, which is exactly the
disruption this exemption prevents. The marker is transient view/session state
and is not persisted with the workspace snapshot.

Inspected reference: the existing `WorkspaceSidebarView` native `List(selection:)`
and its filename/preview `VStack`. Reuse that row, not a replacement list or a
custom selection background. Always include the preview `Text`, with common
18 pt title and 28 pt preview slots using public `frame(height:alignment:)` and
`@ScaledMetric` for text-size adaptation. The measured empty-preview reservation
failure and the scalable-slot remedy are recorded in the shared
[peer-consistency guide](~/.config/agentsync/docs/UI_DESIGN_GUIDE.md#peer-consistency).
Keep this product's slot dimensions here; do not use filler text or relax the
height-equality assertion.
[Native tail truncation](https://developer.apple.com/documentation/swiftui/view/truncationmode(_:))
preserves equal peer geometry. Verify empty, one-line, multiline and long CJK
content together at narrow and wide sidebar widths.

## File correctness

`WorkspaceStore+Sidebar` coalesces background refresh requests, applies current
loaded buffers only after disk work finishes, and keeps disk cache separate from
unsaved previews. It retains the usable list and reports enumeration failures.
Previews have bounded reads and recognize CRLF as one line break.

Duplicate includes the current committed editor buffer, including unsaved changes,
without committing marked IME text. Closed-file rename shares document validation
and migrates remembered font preferences. Blank autosave and collision protection
remain unchanged.

## Acceptance

Use the installed `/Applications/NeatEditor.app`, not just a build/test result.

1. Inspect a screenshot against the owner's rejected two-row capture.
2. Click the actual sidebar toolbar control repeatedly; inspect expanded and
   collapsed screenshots and select a tab in both states.
3. Repeat at normal/minimum width; resize the native divider.
4. Save, switch documents and refresh; sidebar filename order must remain stable.
5. Drag from a tab and from empty tab-strip space; the window must follow the
   pointer, and releasing must not select or rename the starting tab. Double-click
   the top gutter and trailing blank area: each must perform the native configured
   action once, without an immediate restore. Then click the same tab and
   double-click it to confirm click and rename still work. Inspect inactive tabs
   after hover, selection changes and resize for any leftover rounded background.
6. Exercise active/inactive double-click, rename commit/cancel, close/reopen,
   pin/unpin and search; verify no content changes cross document identities.
7. Check light/dark appearances, Settings minimum size and keyboard selection.
8. Scroll a long sidebar away from the active file, then select an offscreen
   file from the tab band: its row must become visible, without animation. Click
   a visible sidebar row near an edge: the list must not jump. Type in the
   editor: preview updates must not move the list. Expand the sidebar after
   switching tabs while collapsed: the active row must be revealed.

### Active-document reveal evidence (2026-10-26)

Feature commit `0f7ac6e`; final HEAD `b01d946`. The final installed Release was
built from a clean `git archive` of HEAD:
`2bec9be3389767506a03d728ce02b2d4080e28fb544a574db8b37702900e711d`.
It is signed with the same Developer ID identity; the installed executable hash
and signature match the build product. A Release from the intermediate
`9f82c38` was also installed and used for the live close-fallback inspection
below; `b01d946` differs only in comments, tests and documentation.

The clean HEAD archive passed 99 tests in 14 suites, including
`WorkspaceSidebarRevealTests`, which hosts the real `WorkspaceSidebarView` with
80 files and asserts: the restored bottom selection reveals at launch, an
external selection of the top row scrolls up, a fully visible row does not move
the list, an external selection of a middle or bottom row scrolls down, preview
changes do not move the list, and `openSidebarFile` (the sidebar binding path)
does not move it. Debug analyze
passed without compiler or static-analysis warnings; only the previously
assessed AppIntents metadata-step note remains in test/build logs.

An isolated copy of the Release binary, re-signed only to use a separate
defaults domain, was inspected with a 60-file folder: the restored
`note-01.txt` sat at the bottom of the list at launch, and Command-W selected
`note-20.txt` and scrolled the sidebar to it. The Debug isolated run additionally
used Command-Shift-T to reopen `note-01.txt` and return the sidebar to the
bottom.

The installed Release was then exercised directly: Command-W closed the active
`scroller-long.txt` tab and selected `Untitled 18.txt`; the sidebar shifted just
enough to make that partially visible row wholly visible. The workspace was
restored to its pre-test snapshot afterwards, and the final `b01d946` Release
launched with the active sidebar row selected. Evidence images are in the local
`build/sidebar-reveal/evidence/` (Debug, isolated Release and installed Release
runs).

Remaining limits: the session was locked, so pointer clicks on the top tab band
or sidebar rows could not be synthesized. The hosted test covers the direct
`selectedTabID` path and sidebar-origin suppression; the installed-app run
covered a real close-fallback selection through the same
`selectedSidebarFileURL` observer. The exact scroll amount for a far row is
SwiftUI List's own minimum-scroll behavior; the test asserts visibility, not a
specific anchor offset.

### Consistency repair evidence and remaining limits

The consistency repair (`b7112f6`) passed 95 tests in 13 suites on arm64,
including equal tab widths, 15 pt title layout at that revision, native tail
truncation, no inactive fill, blank-region hit-testing and equal sidebar-row
heights for empty/short/multiline/long content at 160/240/340 pt widths.
Universal Debug analysis and Release compilation passed on Xcode 27.2; native
Intel test execution was not established. Complete diagnostics are retained in
`build/TallerTabs/logs/consistency-{final-test,analyze,release}.log`. Only the
previously assessed AppIntents metadata-step warning remained (see
`docs/code-review.md`); no Swift compiler/static-analysis warning was found.

That signed Release was committed, pushed and installed; installed/product
executable SHA256 matched. The inspected
`/tmp/neateditor-consistency-installed.png` shows the installed expanded sidebar,
equal tab slots and row rhythm at 1284 × 777 pt. It is a static document-tab
capture, not Settings light/dark color or double-click/drag acceptance.
The later owner-approved compact top-row sizes above supersede that revision's
44 pt / 15 pt / 200 pt geometry and were not rolled back during closure.

Still unaccepted: actual blank-region double-click/drag, latest Settings color
matching in both appearances, and post-correction motion. Locked-session AX
window routing/input prevented those interactions; subsequent capture retries
also failed despite capture permission and bounded display preparation. Native
window replay without a visibly attached toolbar did not establish a zoom pass.
Do not treat unit hit-testing or the earlier static capture as resolving these
items. The task-connected Agent Display was disconnected and its native
vendor/model/serial identity removed; the task-started BetterDisplay host quit.

The rejected two-row 1.0.10 draft has no assets and remains unpublished.
The corrected release uses a new immutable version, never a moved tag.
