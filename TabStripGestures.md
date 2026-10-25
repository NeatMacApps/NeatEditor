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

`TitleBarEventNSView` owns the tab-strip drag because a custom view hosted in an
`NSToolbarItem` does not get the window drag automatically, and
`NSWindow.performDrag(with:)` is ignored in that context. The monitor records
the initial window origin and pointer location, then moves the window directly
once the pointer crosses the threshold, clamping the frame so part of the
window remains on screen. Clicks are left untouched for SwiftUI; no event is
replayed or delayed. This replaces the old native title-bar drag path only for
the tab strip.

`EditorTabStripView` preserves the product's existing `EditorTabItemView`,
connected fill and inline rename inside the single native toolbar item. The
inspected restoration reference is this repository's `b213e21` implementation
of those components and the installed single-row screenshot. The rejected
segmented-control replacement is not a reference for the document tabs.
Use one continuous outline for the baseline and raised selected tab, rather
than separate strokes with clearance gaps or mismatched fill/border curves.
Native AppKit continues to own the surrounding toolbar and window behavior.
Restoring an owner-decided design is exempt from new appearance research;
public API changes still require official documentation and SDK checks.

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
  4-point threshold. SwiftUI still receives the press, so a click without
  movement selects or renames normally; only a completed drag suppresses the
  tab action. The inline rename field remains a text field and is not turned
  into a window-drag surface.
- Double-click a tab that was already selected on the first click to rename
  inline. Double-clicking an inactive tab selects it without starting rename.
- Enter, clicking outside or switching apps commits rename. Escape cancels it.
- Context menus preserve Show in Finder, Rename, Close, Close Other Tabs and
  Move to Trash where applicable. Middle-click closes the hit tab.
- Scroll-wheel/trackpad tab stepping keeps the existing sensitivity and ignores
  momentum. Selection is revealed when clipped, including after a resize.
- Native AppKit owns empty-titlebar double-click and window dragging. Never
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
