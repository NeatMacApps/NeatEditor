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
Measure each configured title field's native cell, not just its glyphs or a
separately configured probe; centered cells include additional insets. Cache
those widths on descriptor/selection updates, not on every resize frame.
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
- Acceptance requires sequential frames during repeated fast shrink/expand and
  direction reversals, with sidebar both visible and hidden and a trailing tab
  selected. A settled screenshot or a passing build is not motion evidence.

### Toolbar height and editor top rule (owner direction 2026-10-25)

- Use the native `unified` toolbar (52 pt), not `unifiedCompact` (40 pt), so
  the native glass items keep their standard control size. The owner compared
  the top-right New Document and pin actions with Corral's top bar; compact
  glass (24 pt tall) clamped the glyphs and read as cramped. The installed
  unified toolbar draws 36 pt glass, the same as the reference.
- The document-tab strip fills that row and keeps the existing 32 pt tab shape
  bottom-aligned, so the tab still meets the editor surface. Tabs sit about
  10 pt lower than the traffic-light centres; shrinking the row again would
  restore the cramped glass, so do not change the height without the owner.
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
- A left drag beginning anywhere in the tab strip moves the window after a
  4-point threshold. Native pointer tracking distinguishes a click from a drag;
  only a completed drag suppresses the tab action. The inline rename field
  remains a native text field and is not a window-drag surface.
- Double-click a tab that was already selected on the first click to rename
  inline. Double-clicking an inactive tab selects it without starting rename.
- Enter, clicking outside or switching apps commits rename. Escape cancels it.
- Context menus preserve Show in Finder, Rename, Close, Close Other Tabs and
  Move to Trash where applicable. Middle-click closes the hit tab.
- Scroll-wheel/trackpad tab stepping keeps the existing sensitivity and ignores
  momentum. Selection is revealed when clipped, including after a resize.
- Outside the tab strip's recorded drag scope, native AppKit owns empty-titlebar
  double-click and window dragging. Never
  separately call zoom/miniaturize for the same event: that caused the earlier
  enlarge-then-immediately-restore regression.
- Pin changes the native window level. Existing topmost hover-focus protection
  and debounce remain in `WindowPinningView`.

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
   pointer, and releasing must not select or rename the starting tab. Then click
   the same tab and double-click it to confirm click and rename still work.
6. Exercise active/inactive double-click, rename commit/cancel, close/reopen,
   pin/unpin and search; verify no content changes cross document identities.
7. Check light/dark appearances, Settings minimum size and keyboard selection.

The rejected two-row 1.0.10 draft has no assets and remains unpublished.
The corrected release uses a new immutable version, never a moved tag.
