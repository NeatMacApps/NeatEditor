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
- Sidebar files use descending content modification date (latest first), then
  descending natural filename and path for equal dates. Missing dates sort last.
  Owner revision 2026-11-03 supersedes the previous filename-first order.
  Reference: the existing native `WorkspaceSidebarView` List and metadata-only
  `DocumentPersistenceService.sidebarTextFiles`; retain their UI and filtering.
  Save/autosave and external edits may move a file when its disk modification
  date changes. Tab switching and preview-only updates do not invent dates.
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
- The tab strip and pin live in a trailing native titlebar accessory aligned
  with the editor column (40 pt row), not in the content hosts underneath it.
  With the sidebar collapsed the accessory starts after the sidebar button;
  with it expanded it starts at the editor column. Empty accessory regions stay
  in native titlebar hit-testing. Full screen reuses the same controls in the
  reserved content band; see the 2026-10-27 routing repair below.
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

### Top-row alignment and narrow windows (owner correction 2026-10-26)

- Keep the native 40 pt compact row and system-placed traffic lights. Sidebar,
  New Document, Always on Top and tab filenames use the same 20 pt vertical
  content axis; do not align actions to the bottom of a shorter tab.
- Use 13 pt regular SF Symbols and 32 pt action slots throughout. Leave 8 pt
  after the trailing slot. The existing stepped tabs remain equal 168 pt slots
  with 13 pt titles, now 36 pt tall with a 4 pt top gutter; title placement follows
  the row axis rather than the shape's editor-join extension.
- Replace the thin pin silhouette with `square.3.layers.3d.top.filled`, a compact
  top-layer symbol. Keep the existing Always on Top action, accessible name and
  tooltips; gray when off, accent when on, without a capsule or focus ring.
- The 470 pt minimum window must fit the native split: 200 pt sidebar plus a
  240 pt editor minimum and the divider. The former 300 pt editor minimum
  exceeded the available width with the sidebar visible and pushed trailing
  controls outside the window. Settings retain their 500 pt detail minimum;
  the window minimum includes the visible sidebar and divider in that state.
- Inspected reference: this repository's `WorkspaceSplitView` titlebar accessory,
  `EditorTabStripView.layout`, and `EditorTabItemView.layout`, compared with both
  owner captures (empty row and 470 pt expanded sidebar). Reuse the native
  `NSButton`, `NSTitlebarAccessoryViewController`, empty `.unifiedCompact`
  `NSToolbar`, native split constraints and existing stepped-tab exception;
  no replacement toolbar or manual traffic-light placement.
- Public APIs checked in the installed Xcode 27.2 SDK and Apple's documentation:
  [button symbol configuration](https://developer.apple.com/documentation/appkit/nsbutton/symbolconfiguration),
  [compact toolbar](https://developer.apple.com/documentation/appkit/nswindow/toolbarstyle-swift.enum/unifiedcompact),
  and [split minimum thickness](https://developer.apple.com/documentation/appkit/nssplitviewitem/minimumthickness).
  These product dimensions are not Apple-prescribed constants. This correction
  supersedes the 30 pt tabs, 15 pt sidebar icon and bottom-aligned action policy
  above; the 40 pt row and native ownership remain unchanged.
- Acceptance includes empty and mixed-title tabs, sidebar open/closed, 470 pt
  and normal widths, overflow selection, pin toggling and Settings minimum size.
  Check actual installed-window screenshots and native frame containment.
- Installed overflow acceptance exposed a separate redraw issue: after resizing
  or toggling the sidebar, New Document still accepted a click at its correct
  frame but its symbol was absent until selection changed. Complete the strip's
  layout synchronously with the editor column and invalidate the native button's
  display after moving it; do not add delayed geometry callbacks. Include the
  button in the tab group's explicit accessibility children so the actual native
  action and frame can be verified without guessing a pixel target.

### Installed alignment acceptance (2026-10-26)

Implementation `62e8b0b` was installed as a same-identity Developer ID-signed
universal Release at `/Applications/NeatEditor.app`. Installed/build executable
SHA256: `55429d3b4caee89e7e1cbd66623b9a93cd9aacb4ee6b7051044251e5dabdfa1b`.

- Full arm64 suite: 101 tests in 14 suites. Universal Release build and Debug
  analysis passed, including recompilation of the changed views for both slices.
  Complete diagnostics: `build/titlebar-polish/logs/final-{tests,release,analyze}.log`.
  No Swift compiler or analyzer warnings. The retained AppIntents metadata-step
  diagnostic remains assessed in `docs/code-review.md`; no framework was added
  merely to suppress it. Final commands specify the arm64 destination while
  explicitly building both application architectures, avoiding destination ambiguity.
- Installed 470 pt window: inspected the expanded sidebar, collapsed sidebar and
  overflow selection with short, long CJK and empty-file fixtures. New Document
  and Always on Top remained visible and separate. Actual accessibility frames
  expose both buttons. A pre-redraw-fix pointer check created a new tab at the
  invisible symbol's correct location, distinguishing redraw from hit testing;
  the final installed captures verify its visible symbol in both sidebar states.
  The final native Always on Top accessibility press returned 1 then 0.
- Inspected the same mixed-title group at 1000 pt, with equal slot widths and
  native tail truncation. Fixture tabs were closed without changing their contents.
  Screenshot evidence: `/tmp/neateditor-titlebar-final-{overflow,collapsed,wide}.png`;
  these are actual desktop-context captures, not a composed mockup.
- Limits: installed visual checks covered dark appearance on macOS 27.2. Light
  appearance, native Intel execution and a macOS 26 runtime were not exercised.
  Settings minimum width was checked in native-window tests, not through its
  installed settings surface. This does not clear earlier unrelated motion,
  blank-chrome drag or Settings-color acceptance limits below.

### Two-tone workspace surfaces (owner decision 2026-10-26)

- Owner direction: the two tones must be coordinated, not contrasting. A
  cool blue-gray band read as cement and a deep-navy band read as a clash
  (it also tinted the translucent sidebar). Use one warm hue family at two
  depths: a warm charcoal tab band (`#2D2925`) above the warm-black editor
  (`#211F1D`) in dark appearance, and oat (`#EEE8E0`) above warm off-white
  (`#FAF8F5`) in light appearance. Separate the layers by depth, not by a
  second hue. The selected stepped tab uses the exact editor surface,
  making the color boundary follow its raised outline rather than cutting
  straight through it. Inactive tabs remain on the uninterrupted band.
  Follow the system appearance; do not add a theme picker. Preserve system
  label colors, focus policy and pin state tint.
- Editor text background, gutter, empty editor and Settings content all share
  `EditorChrome.editorSurfaceColor`. A footer using that existing token inherits
  the surface automatically. Keep the boundary at 1 pt with a quieter outline;
  use solid surfaces, not decorative gradients. Existing overflow edge fades
  remain functional and must resolve against the new tab-band color.
- Reuse the inspected `EditorChrome`, `EditorTabStripView.draw/geometryDidChange`,
  `EditorTabItemView.draw`, `EditorTextContainerView.updateTextViewColors` and
  `LineNumberGutterView.draw/updateColors`. Native sidebar material and native
  traffic lights are not replaced or manually positioned. The expanded native
  sidebar retains its full-height material rather than gaining a painted cap.
- Public API applicability checked against Apple and the installed Xcode 27.2
  headers: [dynamic NSColor](https://developer.apple.com/documentation/appkit/nscolor/init(name:dynamicprovider:)),
  [drawing appearance](https://developer.apple.com/documentation/appkit/nsappearance/performascurrentdrawingappearance(_:)),
  [window background](https://developer.apple.com/documentation/appkit/nswindow/backgroundcolor)
  and [transparent titlebar](https://developer.apple.com/documentation/appkit/nswindow/titlebarappearstransparent).
  Use the supplied appearance when resolving dynamic colors; layer CGColors
  must be refreshed for the owning view's appearance. Preserve the existing
  native compact titlebar and scoped stepped-tab exception.
- Research scope: palette preference is the owner's subjective choice; keep the
  previously verified native color APIs and inspected local components rather
  than treating third-party palette recommendations as evidence of visual fit.
- Acceptance checks the actual installed editor, selected/inactive tabs, gutter
  and overflow edge in light/dark appearances, sidebar open/closed and at 470 pt.
  A screenshot must show the joined selected tab and editor in one surface.
- Evidence (2026-10-26, c94a572): installed universal Release, dark and light
  (`-NSRequiresAquaSystemAppearance YES`) windows captured with the warm band,
  warm-tinted sidebar and joined selected tab. Narrow-window and overflow
  captures were not repeated for this color-only change.

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

`EditorTabStripView` is a native AppKit `NSView` in the titlebar accessory, owning one `NSScrollView`,
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
- Blank space within the tab accessory's bounds (above the tabs or after
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

## Blank titlebar event routing (2026-10-27 repair)

The owner reports that double-clicking the visible empty top row does not resize
the window. Preserve the compact single row, tab rename, +, pin and sidebar
controls. Every blank titlebar region (including the sidebar side, tab top gutter
and trailing space) must reach AppKit's native titlebar interaction and honor
Desktop & Dock settings. A strip-only `hitTest == nil` assertion is insufficient:
content containers behind the strip can still claim that event. Verify routing
through the complete window, then double-click to resize and restore, and drag.
Do not emulate the system preference or invoke a second zoom action.

Reference and API choice: reuse the existing sidebar's
`NSTitlebarAccessoryViewController` mechanism for the tab band as a trailing
accessory. AppKit owns the containing titlebar. The accessory's container still
claims blank hits before the titlebar sees them, so blank `hitTest` results are
handed to the window's frame view (`contentView.superview`). The frame view is
the native owner of titlebar drag and the system double-click action, so no
preference emulation or manual zoom call is needed. Only tab controls, + and pin
consume events inside the band. The SwiftUI scene uses `.titleBar` with an
opaque titlebar (a 2026-10-27 transparent detour is recorded in "Top band color,
light surface and native titlebar gestures"). `.titleBar` resets
`titlebarAppearsTransparent` to false after AppKit attachment, so a transparent
setting in `attachToWindow` alone has no effect in the real scene (measured in
the live window; an `NSHostingController` fixture misses this Scene-level
reset). Installed visual acceptance must retain the tabs, + and pin and the
open join.

Official
[NSTitlebarAccessoryViewController](https://developer.apple.com/documentation/appkit/nstitlebaraccessoryviewcontroller)
and [titlebar transparency](https://developer.apple.com/documentation/appkit/nswindow/titlebarappearstransparent)
were checked against the installed Xcode 27.2 SDK headers. Inspecting the
installed AppKit hierarchy showed the titlebar's double-click recognizers on the
theme frame and titlebar container; a hit test that stopped at the accessory
container never reached them. No private titlebar subviews, private selectors or
preference emulation are used.

Keep the band width aligned with the editor column and retain the content-band
fallback when full screen hides the titlebar. The frame-view redirect is disabled
in that fallback because full screen has no native titlebar. Move the same
controls to the content band only after full-screen entry succeeds, and restore
the accessory after full-screen exit succeeds; failed transitions must not strand
hidden controls.

Verification: 114 tests in 17 suites pass on arm64, including complete-window
hit-testing with and without a SwiftUI host/sidebar, button/tab targets,
minimum widths, full-screen reparenting and the frame-view redirect for blank
band hits. Debug static analysis and the universal arm64/x86_64 Release build
pass; logs are in `build/titlebar-repair/test-final-routing.log`,
`analyze-routing.log` and `release-final.log`. A real SwiftUI `Window` scene
probe with the production band and accessory reported the blank point between
`+` and pin as the window frame view; a synthesized double-click there resized
the window to the screen's visible frame instead of doing nothing. The installed
Release window was captured after relaunch and retains the tabs, `+`, pin and
open join. The only retained diagnostic is the
[assessed AppIntents metadata notice](./code-review.md#verification).
An earlier Debug signing attempt failed because the timestamp service was
unavailable; that test/analyze invocation alone used `--timestamp=none`. The
local Release uses the existing Developer ID identity and a valid timestamp.

Acceptance limit: the screen is locked, so physical pointer double-click and
restore, drag and full-screen animation remain unaccepted. In-process event replay
in a real SwiftUI Window scene does resize the window from the blank band,
establishing that the event now reaches the native frame view; it is not a
substitute for physical pointer acceptance. Do not clear the owner's report on
build or hit-testing results alone.

## Full-width tab rule (owner clarification 2026-10-27, authoritative)

- Owner clarification of the original "line breaks near the sidebar" report: the
  tab bar's bottom line must continue naturally to the left, across the sidebar
  column to the window's leading edge. The selected tab rises from one
  continuous full-width line. Earlier fixes (first-tab clearance, corner-row
  painting, titlebar transparency) addressed real defects but not this request.
- Design: the rule is owned by the split view, not the editor column. One
  `EditorTabTopRuleView` spans the whole split view width at the editor column's
  safe-area top (the band's bottom edge in windowed and full-screen layouts),
  above both split panes, including the floating sidebar glass. It keeps the
  open gap and the selected tab's foot row exactly as before; the first tab's
  foot now meets the rule's run over the sidebar.
- Native alternative rejected: `NSSplitViewItem.titlebarSeparatorStyle` needs an
  opaque titlebar section, which caps the sidebar (see below).
- Acceptance: with the sidebar expanded and collapsed, the line runs unbroken
  from the window's leading edge into the selected tab's foot and continues after
  the tab to the trailing edge; key-window evidence is required for the sidebar
  glass portion.

## Top band color, light surface and native titlebar gestures (owner reports 2026-10-27, authoritative)

- Owner requirements: the whole top row (behind the traffic lights, above the
  sidebar, behind the tabs) is the band color; everything below the full-width
  line is the light surface, including the margins around the floating sidebar
  panel; double-click and drag on every blank part of the top row keep the
  native titlebar actions.
- History: 1.0.20 showed a white cap above the sidebar in the key window. It is
  AppKit's `NSTitlebarBackgroundView` per split section, inserted into the split
  view under an opaque titlebar (live view tree). 1.0.21 removed it with a
  transparent titlebar (`.hiddenTitleBar`) and routed blank titlebar hits to the
  window frame view from content roots. The owner then found double-click no
  longer zoomed above the sidebar / behind the traffic lights: a frame-view
  redirect from content is not equivalent to the toolbar view the opaque titlebar
  gives those points. That regression shipped in 1.0.21 and 1.0.22. In-process
  replays of double-clicks did not resize the window even at the known-good tab
  band, so they are not evidence for or against titlebar double-click.
- Decision: keep the opaque `.titleBar` scene, where blank points above the
  sidebar and behind the traffic lights hit the native `NSToolbarView` (the
  1.0.20 behavior the owner used). The split view owns a full-width
  `TabBandBackgroundView` (band color, z above AppKit's section backgrounds) and
  the full-width rule; neither takes hits. The window background is
  `EditorChrome.editorSurfaceColor`, so the light surface shows around the
  floating sidebar. Do not reintroduce a transparent titlebar or content-side
  titlebar hit routing for this.
- Owner correction after 1.0.23 (2026-10-27): the light sidebar looked wrong.
  The sidebar column (its list background and the margins around the floating
  panel) uses the band color, the same as the top row; only the editor column is
  the light surface. Superseded: "everything below the line is the light
  surface". Implementation: `WorkspaceSidebarView` hides the list's scroll
  background and paints `EditorChrome.tabBarBackground`; the window background
  returns to `EditorChrome.tabBarBackgroundColor`. The full-width line still runs
  across the sidebar. This is an owner exception to keeping the native sidebar
  material visible.
- Pending owner decision: the owner asked for a top margin between the line and
  the floating sidebar panel equal to its bottom margin. The native sidebar
  panel's placement has no public API (checked `NSSplitViewItem` /
  `NSSplitViewController` in the Xcode 27.2 SDK); achieving it would mean
  replacing the native sidebar glass with a custom panel, which the native-UI
  standard prohibits without an explicit owner exception.
- Owner correction (2026-11-06): the traffic-light/sidebar-button region must
  match the uninterrupted inactive-tab band, including when the sidebar is
  collapsed and the window is key. An inactive-window screenshot that hides
  the native white cap does not accept this requirement. The selected stepped
  tab still matches the editor surface; no geometry or gesture change is requested.
- Historical 2026-11-06 implementation (superseded by the native-drag repair
  and the 2026-11-13 cold-launch correction below): inspected `WorkspaceView`,
  `WorkspaceSplitViewController` and `TabBandBackgroundView`, retaining their
  compact native toolbar, accessories and theme palette. It used SwiftUI's public
  [`toolbarBackground(_:for:)`](https://developer.apple.com/documentation/swiftui/view/toolbarbackground(_:for:))
  on `.windowToolbar`, with `.visible` background visibility and the same
  `EditorChrome` band token. The API is present in Xcode 27.2 (macOS 13+).
  A real SwiftUI `Window` scene is required: a standalone `NSHostingController`
  does not apply this window-toolbar preference. The existing split-view
  background alone cannot cover opaque active native chrome.
- SwiftUI applies the custom background but also sets
  `titlebarAppearsTransparent = true`. Reassert `false` on native split-view
  layout and `NSWindow.didUpdateNotification` after the preference applies.
  The preference can arrive after layout without invalidating the split view.
  A scene probe with active-application drawing reproduced the old white cap, then showed the same rendered color
  behind the traffic lights and inactive tabs with the custom style and opaque
  titlebar together. Native toolbar blank hits remain outside content. Do not
  modify private chrome views or manually position traffic lights. The earlier
  prohibition on hiding toolbar paint is superseded by the cold-launch correction
  below; `.hiddenTitleBar` and transparent native hit routing remain rejected.
- Acceptance: inspect the top-left and inactive-tab-band pixels in the same
  key-window capture, light/dark and both themes, sidebar open/closed; retain
  native blank-titlebar hit routing. Locked-session inactive pixels alone leave
  key-window visual acceptance open.
- Verification (2026-11-06): 200 tests / 23 suites pass on arm64. Fresh universal
  Debug and Release build/analysis pass; only the previously assessed AppIntents
  metadata notice remains (`docs/code-review.md`). The scene fixture passes all
  16 combinations of two themes, light/dark, sidebar open/closed and 470/900 pt,
  including rendered peer-color equality, opaque compact chrome and native
  blank-region hits. Its application-active state is simulated; actual installed
  key-window pointer/double-click acceptance remains open under screen lock.
  A universal Release from source `0b34f29` was installed at
  `/Applications/NeatEditor.app` with the existing Developer ID team. Installed
  and product executable SHA256 match
  `626c8f742f0548331e855a1152e4a0df48e60702385242cf8eef3a1825b0fa2c`;
  strict nested signature verification passes. Fresh installed-window captures
  show a continuous top band with the sidebar expanded and collapsed. The real
  sidebar menu command established collapse; repeated locked-session restore
  commands did not establish expansion. The original expanded preference was
  restored after normal quit, then a fresh installed launch/capture confirmed
  expansion. These are live inactive-window pixels, not key-window pointer
  acceptance.
  This remains a local unnotarized 1.0.29 source build; no public release or
  appcast change was made. Full logs and private/component images are retained
  under `~/.config/neateditor/verification/2026-11-06-top-band/`.
- Reproduce the scene fixture after the Debug build, from the repository root:

  ```bash
  product="$PWD/build/TopBand/Build/Products/Debug"
  swiftc -parse-as-library -swift-version 6 -I "$product" -F "$product" \
    Tests/Fixtures/WorkspaceChromeProbe.swift \
    "$product/NeatEditor.app/Contents/MacOS/NeatEditor.debug.dylib" \
    -o /tmp/neateditor-workspace-chrome-probe
  DYLD_FRAMEWORK_PATH="$product" \
  DYLD_LIBRARY_PATH="$product/NeatEditor.app/Contents/MacOS" \
    /tmp/neateditor-workspace-chrome-probe --matrix
  ```

  Optional `NEATEDITOR_CHROME_OUTPUT=/tmp/chrome.png` retains component images;
  keep output paths out of launch arguments. The fixture uses an isolated
  temporary documents folder/defaults suite and removes them on success/failure.
  Scene-owned preference scope, active/inactive evidence and native routing
  caveats are maintained in the [shared macOS guide](~/.config/agentsync/docs/MACOS_APP_DEVELOPMENT_GUIDE.md#scene-owned-toolbar-backgrounds-verified-2026-11-06).

### Cold-launch white-cap regression (owner report 2026-11-13)

- Acceptance is reopened: launching with the sidebar collapsed can leave a white
  rectangle behind the traffic lights and sidebar button; expanding the sidebar
  clears it. The initial frame must already use the uninterrupted band color.
  Toggling the sidebar, resizing, delayed synthetic redraws, or accepting only
  inactive-window pixels is not a fix.
- Reuse the existing native compact toolbar, titlebar accessories and
  `TabBandBackgroundView`; preserve native dragging, double-click and controls.
  Verify a fresh collapsed launch before any resize or sidebar transition, then
  both sidebar states, themes and appearances. The existing scene fixture forces
  resize/layout/cache drawing before comparison, so its passing matrix alone
  does not cover this startup path.
- Inspected implementation: the existing `WorkspaceView` toolbar preference,
  `WorkspaceSplitViewController` opacity guard and `TabBandBackgroundView`.
  Use the public
  [`toolbarBackgroundVisibility(.hidden, for: .windowToolbar)`](https://developer.apple.com/documentation/swiftui/view/toolbarbackgroundvisibility(_:for:))
  to remove only the competing native background paint. Keep `.titleBar`, the
  visible empty `.unifiedCompact` toolbar, native accessories and
  `titlebarAppearsTransparent == false`. The split view remains the single band
  painter. This is not `.hiddenTitleBar`, toolbar removal, transparent titlebar
  hit routing, or the custom toolbar-color modifier that blocked dragging.
- Reference applicability: Apple's
  [window customization sample](https://developer.apple.com/documentation/swiftui/customizing-window-styles-and-state-restoration-behavior-in-macos)
  documents the background-visibility API; the installed SDK supports it. Reuse
  this API only, not the sample's titlebar removal, new gestures or layout.
  The scene matrix checks native blank hits outside content, native
  `mouseDownCanMoveWindow`, visible toolbar/controls and the 40 pt geometry.
- First-frame evidence must come from `winshot` while the fixture is running
  with `--cold-launch`, before any cache drawing. Its `--verify-capture` mode
  reads that image from `NEATEDITOR_CHROME_CAPTURE` and compares leading-band
  pixels with the inactive-tab band. Run each theme/appearance/sidebar/width
  combination in a fresh process. The cached matrix remains a separate
  transition/routing check; it can pass while an initial compositor cap exists.
- The Debug-only `prepareWindowForTesting` hook exercises key-before-toolbar
  ordering. Active-application/key drawing is simulated in the scene fixture;
  screen-lock captures of the installed application do not establish genuine
  foreground activation or physical dragging/double-click. Do not turn those
  limitations into an active-window acceptance claim.

## First-tab join clearance (owner report 2026-10-27)

- Owner report: with the sidebar expanded, the selected tab's outline stops
  mid-curve where the editor column meets the sidebar, so the tab band reads as
  a broken line instead of joining the editor's top rule.
- Cause: the selected fill and open outline extend
  `ConnectedTabGeometry.baselineOutset` (3 pt) past the 168 pt slot on each side
  so the bottom arcs can reach the 1 pt rule. The first slot began exactly at the
  scroll viewport's leading edge, which is the editor-column boundary; the clip
  view removed those 3 pt, cutting the descending arc before its horizontal
  tangent.
- Owner correction after 1.0.19 (2026-10-27): the shipped 8 pt clearance looked
  wrong in the active window. The floating sidebar's glass titlebar region sits
  directly left of the band, so the clearance read as a stray band-colored column
  between the glass and the tab. Superseded: `tabsLeadingInset` now equals
  `baselineOutset` (3 pt), the foot's own width, so the arc finishes its
  horizontal tangent exactly at the column edge with no extra band-colored run.
  Do not add a rail, gutter or separate connector, and do not change the slot
  width.
- Regression coverage: a native test asserts the first tab's outline stays inside
  the scroll viewport and that its foot ends exactly at the viewport edge.

### Bottom-corner joins inside the opaque titlebar (owner report 2026-10-27)

- Owner report on installed 1.0.19: the curves at every selected tab's lower
  left and lower right corners break before they reach the editor's top rule.
- Cause: the 1.0.19 routing repair moved the band into a native titlebar
  accessory with opaque chrome. The outline's last row (centre `maxY + 0.5`)
  lies 1 pt below the band, which the titlebar clips, while the rule is drawn
  in the content column below the titlebar. The arcs therefore stopped 1 pt
  short of the rule. The inactive window hid this because the separator color
  composited close to the band; the active window showed the gap.
- Rule ownership stays as above: the editor column owns the rule below the opaque
  titlebar (moving it up would hide it under the titlebar beside the traffic
  lights when the sidebar is collapsed). `EditorTabTopRuleView` additionally
  strokes the selected tab's `ConnectedTabGeometry.outline`, converted from the
  live tab view and clipped to the visible viewport span, inside its own 1 pt row.
  `EditorTabItemView` clips its own drawing to the band, because whether the
  titlebar clips the 1 pt overhang varies with window state: installed inactive
  pixels showed the overhang still drawn, so drawing it in both views darkened
  each foot. The strip and the rule therefore draw one path split exactly at the
  titlebar edge, each row painted once. Do not move the band out of the accessory; that would regress blank
  titlebar routing.
- Acceptance: magnify both lower corners of a selected first, middle and overflow
  tab with the sidebar expanded and collapsed; the arc must continue into the rule
  without a gap. Window captures under a locked session are inactive-window
  pixels; the owner's active-window report must be rechecked when an unlocked
  active capture is available.

## Hover close button (owner, 2026-11-05)

- Entering a tab reveals a native trailing `NSButton` with the × symbol; leaving
  hides it. Selected and inactive tabs use the same fixed geometry. Hide it
  during inline rename. Closing uses the existing save-before-close action,
  without first selecting an inactive tab. Context menu, middle click and
  Command-W remain unchanged.
- Keep the title's frame stable. A small transparent-to-opaque background
  gradient beneath the button fades the filename into that tab's actual
  selected/unselected surface. Do not add a rounded hover tab background or
  cover the stepped outline. Repaint it on theme/appearance/selection changes.
- Inspected reference: existing `EditorTabStripView.configureNewDocumentButton`
  (`NSButton`) and its overflow `CAGradientLayer` fades, adapted inside
  `EditorTabItemView`. Reuse the product-owned stepped tab and native button;
  do not replace them with a new tab design. Public
  [NSTrackingArea](https://developer.apple.com/documentation/appkit/nstrackingarea)
  supplies enter/exit tracking and
  [CAGradientLayer](https://developer.apple.com/documentation/quartzcore/cagradientlayer)
  supplies the fade; checked against installed Xcode 27.2 headers.
- Acceptance: short/long/CJK titles together, selected/inactive and light/dark,
  both themes, overflow and minimum width; entering the button must not hide
  it or select/drag the tab, and closing must preserve existing save failures.

### Hover-close re-verification (2026-11-06)

Current source `87bf3a9`: 200 arm64 tests pass, including the native button hit
route, no accidental selection, rename suppression and all four palette states.
Debug static analysis and universal arm64/x86_64 Release build/analysis pass.
The first Debug build hit an unavailable Apple timestamp service; the unchanged
signed retry passed. The only retained build notice is the already assessed
AppIntents metadata extraction notice; no Swift/compiler/analyzer warning was
introduced.

A freshly compiled component window reuses the current production tab sources.
Its inspected capture shows the trailing × and filename fade on short, long and
CJK peers in both themes/light-dark appearances. Enter events were delivered
programmatically, so this is component rendering and hit-routing evidence, not
real pointer acceptance in the installed workspace.

The installed 1.0.29 (29), signed with the same Developer ID, is displaying
Save Failed for an open document whose source disappeared. Do not choose Don't
Save, force-quit or overwrite it to make a hover test pass: preserve that buffer.
The session became locked before native pointer verification; the installed
hover path remains unaccepted. No product source change or public release was
needed for the already implemented close/fade. The current universal Release
artifact remains available in `build/ParityDerivedData/Build/Products/Release/`
and the same-Developer-ID, non-notarized local handoff ZIP
`build/local-delivery/NeatEditor-873dbe7-local.zip`. The component process exited
and no task-owned virtual display remains connected (none was needed).
Full logs and the fresh component capture are under
`~/.config/neateditor/verification/2026-11-06-mobile-parity/8308b07e/`.

### Hover-close verification and installation limit (2026-11-05)

Source `0b5df2b`: 176 native arm64 tests pass in 23 suites, including close-button
hit routing, no accidental selection, stable peer/title geometry, rename
suppression and both themes in light/dark appearances. Debug analysis and a
universal arm64/x86_64 Release build/analysis pass on Xcode 27.2 beta 2. The only
retained build notice is the already assessed AppIntents metadata extraction
notice in [code-review.md](code-review.md#verification); no compiler/analyzer or
structured test-runtime warning remains. Intel runtime is not established.

A fresh four-variant native component window compiled from these committed
production tab sources was captured and inspected: × remains legible over the
fade on short, long and CJK titles without changing the stepped geometry.
Programmatically delivering enter events establishes rendering, not real pointer
hover in the installed editor. The temporary component process was stopped.

The installed 1.0.28 process refused a normal quit because an open document's
source disappeared and Save Failed was presented. Preserve that unsaved buffer:
no force quit, Don't Save, overwrite install or user-data change was performed.
The installed executable therefore remains the prior build, and the actual
installed hover path is still unverified. The new same-Developer-ID universal
Release is handed off as
`build/local-delivery/NeatEditor-hover-close-0b5df2b.zip` (SHA256
`038ffdebfcdd813feb44130fbad94b9a281057210496e58f0c8538840612eeac`).
Full logs, fingerprints and private captures (the save-failure capture contains
user content and must not be published) remain in
`~/.config/neateditor/verification/2026-11-05-editor-gestures/`.

## Icon + Label menus and whole-top dragging (owner corrections, 2026-11-07)

### Native drag repair

Owner acceptance reopened: blank-band dragging jitters and does not follow the
pointer; earlier final-position checks did not establish motion quality. The
whole top row must remain draggable without sacrificing native titlebar
double-click, activation, corner resizing, or tab/button/rename interactions.
A rollback that removes blank-band dragging is not an acceptable fix.

Use AppKit's native background drag, gated to each top-row mouse-down via
`NSWindow.isMovableByWindowBackground`. The SwiftUI `Window` scene must also
opt in via `.windowBackgroundDragBehavior(.enabled)`: a plain NSWindow harness
passed while SwiftUI's default scene policy still rejected installed dragging.
The independent fixture was then changed to a real SwiftUI `Window` scene;
with this opt-in, top-row drags moved +71/+35 pt and a content-background drag
moved 0/0 pt. The per-press gate still limits dragging to the requested band.

The installed app also required removing
`.toolbarBackground(color, for: .windowToolbar)`: that modifier gives the
native toolbar an opaque background whose view claims blank band presses and
rejects the native drag (harness matrix: colour 0/0 pt, colour + visibility
0/0 pt, visibility alone +71/+35 pt). The 2026-11-13 cold-launch correction
supersedes the earlier `Visibility(.visible)` choice: hide native background
paint only, preserve opaque native hit routing, and let the split view's band
view own the colour. The custom toolbar-colour modifier remains absent.

Installed acceptance (2026-11-07, universal Release from `d5934fe` + this
change): top-band drags measured +71/+35 pt over sidebar blank, tab gutter and
trailing blank; dragging the editor background moved 0/0 pt; blank double-click
zoomed 988×563 → 2228×1266 and restored; the upper-left corner resized
988×563 → 952×590 while the upper-right corner kept its press.

Click-to-focus on an inactive window remains unverified by automation: posted
`CGEvent` clicks did not change application activation on this host, including a
click on Finder's own titlebar, so the probe cannot distinguish a product defect
from a synthetic-input limit. Because the band gate no longer consumes presses,
native first-click activation applies; confirm with a real pointer. The shared
reusable rules (scene opt-in, opaque-toolbar blocker, `performDrag` failure,
this verification limit) live in
[macos-appkit-gotchas.md](~/Codes/_standards/workspace-docs/swift-docs/macos-appkit-gotchas.md#whole-content-background-dragging-in-a-swiftui-window-scene).
Publication and Cask evidence: [RELEASING.md](../RELEASING.md#1031-publication-evidence-2026-11-07).
Apple's [scene contract](https://developer.apple.com/documentation/swiftui/scene/windowbackgrounddragbehavior(_:))
and the installed SwiftUI SDK expose this public API. Leave every event in normal delivery;
the monitor only enables/disables native eligibility before window dispatch.
Disable it on every press outside the band, on buttons/fields and resize edges,
and in full screen. Restore the original property on detach. This is not the
previous rejected, unconditional whole-window background-drag setting.
Remove all `setFrameOrigin` loops. Retain the 4 pt tab threshold, then forward
the original press through the strip's inherited `NSView.mouseDown(with:)`.
AppKit owns subsequent motion. Blank double-click must reach AppKit unchanged;
do not read `AppleActionOnDoubleClick` or emulate zoom/miniaturize.

Inspected reference: Ghostty's
[`WindowDragView.mouseDown`](https://github.com/ghostty-org/ghostty/blob/main/macos/Sources/Features/Terminal/Window%20Styles/TitlebarTabsVenturaTerminalWindow.swift)
uses `performDrag(with:)` for single presses and forwards multiple clicks.Do not copy its private hierarchy manipulation, traffic-light layout or
appearance. Direct `performDrag` was also evaluated but failed on this Mac:
a separate native control app reproduced zero movement with WindowServer's
`no client initiated window drag trait gesture to activate for mouse`; native
background dragging in the same control app moved +71/+35 pt. This establishes
a local failure, not a claim about every physical input or OS installation.
Related report: [Warp #16508](https://github.com/warpdotdev/warp/issues/16508).
The inspected local control (`DragView.mouseDown`, threshold + inherited
`mouseDown`) demonstrates the selected public-API path. Apple's
[background-drag property](https://developer.apple.com/documentation/appkit/nswindow/ismovablebywindowbackground)
and [view propagation contract](https://developer.apple.com/documentation/appkit/nsview/mousedowncanmovewindow)
were checked against the installed SDK. No manual fallback is introduced.

Component verification: the independent window compiled the actual workspace,
tab and chrome source with disposable descriptors, not user documents. Native
drags from sidebar blank, trailing blank, tab gutter and tab body moved the
window +71/+35 pt for a commanded +72/+36 pt path. The owner physically tested
this window and reported that it appeared to work normally. Native blank
zoom/restore was also observed, but its automated double-click supplied a
synthetic click count; that alone does not verify physical click recognition.
A later trajectory run overlapped live interaction and had changed start frames
and control hits; its output is not valid motion-acceptance evidence.

Full arm64 suite: 207 tests / 24 suites; Debug analysis and universal Release
build passed (`build/native-top-drag/`). No Swift compiler/analyzer warnings;
the existing AppIntents metadata notice remains assessed in `docs/code-review.md`.
Installed acceptance is recorded separately after replacement. Historical motion
claims below are superseded by the owner's reported regressions.

- The native File/Edit/View application commands, sidebar and tab context menus
  and Settings choices use the global Icon + Label rule wherever a familiar
  symbol gives a recognition cue. Native controls, actions, destructive roles,
  keyboard shortcuts and localization are unchanged; no custom menu rows were
  added. macOS 27 hides menu symbol images by default, so every SwiftUI menu
  Label carries `.labelStyle(.titleAndIcon)` and every AppKit item sets
  `preferredImageVisibility = .visible` behind an availability check. A non-nil
  symbol alone does not establish rendered visibility. Compact titlebar actions
  stay icon-only exceptions. The Theme, Tab Behavior and Language pickers now
  share one menu-picker presentation with per-option symbols; the earlier
  text-only segmented Theme control was the odd one out in that peer group.
- Owner regression report: dragging from the sidebar's top region or the blank
  gutter above tabs did nothing. Cause: with the opaque `.unifiedCompact`
  titlebar, those points are answered by AppKit chrome or by the full-height
  sidebar host rather than by the tab accessory, so the previous
  "blank hit reaches the window frame" assumption did not move the window.
  The original `TopBandDragController` consumed presses and tracked window
  positions manually. That implementation was rejected after jitter and
  native-interaction regressions; the native drag repair above supersedes it.
  Tab bodies keep immediate selection, rename and their four-point threshold;
  `+`, pin, sidebar button, hover-close and the native rename field keep events.
- Rejected alternatives: unconditional `isMovableByWindowBackground` (enables
  unrelated backgrounds; distinct from the per-press native gate above), widening the
  leading titlebar accessory to the sidebar column, and a content-side drag
  surface — each either failed the physical pointer test or changed unrelated
  regions. `WorkspaceWindowDragSurface` was removed with them. Native
  double-click is never emulated; the frame view receives the event so Desktop
  & Dock still decides zoom versus minimize.
- Inspected references: this repository's `WorkspaceSplitView`,
  `EditorTabStripView`, `EditorTabStripView+Interaction`, `EditorTabItemView`,
  `WorkspaceCommands`, `WorkspaceSidebarView` and `SettingsView`; the shared
  macOS 27 menu-image recipe in `macos-appkit-gotchas.md`. Public APIs checked
  against Apple's documentation and the installed Xcode 27.2 SDK:
  [NSWindow drag](https://developer.apple.com/documentation/appkit/nswindow/performdrag(with:)),
  [local event monitors](https://developer.apple.com/documentation/appkit/nsevent/addlocalmonitorforevents(matching:handler:))
  and the [macOS 27 menu-image behavior](https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes).
- Acceptance evidence (2026-11-07, installed 1.0.29 source build
  `ecee515…`): with the Debug build, physical pointer drags of exactly
  (+72, +36) pt were measured from the sidebar top, the tab top gutter, the
  trailing blank band and a tab body; a click on the sidebar button moved
  nothing. Blank double-clicks on the sidebar top zoomed the window to
  2228 × 1266 and the tab gutter double-click restored 1069 × 665. Inspected
  installed captures show icons in the expanded File menu, in the sidebar row
  context menu, in every Settings row, and in the open Theme options menu,
  including the highlighted row. These final-position checks did not prove
  continuous motion quality; the later owner reports reopened drag acceptance.

### Installed build for this correction (2026-11-07)

Universal Release `1.0.29 (29)`, Developer ID `Zhichao Cao (SHZQ3MWP3B)`,
installed at `/Applications/NeatEditor.app`; installed and build-product
executable SHA256 both
`ecee5150924cc267b206e54fd4ca8246ca34e0c349c09339b65e3e08908d8ed4`, with
`codesign --verify --deep --strict` passing. Full arm64 suite: 202 tests in 23
suites; Debug static analysis and the universal Release build pass with no
Swift compiler or analyzer warning (only the previously assessed AppIntents
metadata notice). Logs: `build/icon-label-drag/`.

Remaining limits: light appearance, a second display and macOS 26 runtime were
not exercised for this correction; the app's automatic-update toggles render
from Sparkle state after warm-up, so a capture taken during launch can show the
pre-sync value. macOS 27 hides menu images by default — older runtimes still
follow their own defaults, which the availability-checked code does not alter.

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
  blank space within the tab accessory. Never
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
active document changes. An unanchored `scrollTo` may still shift a partially
visible clicked row to make it whole, which would move the list under the
pointer; the exemption prevents exactly that. The marker is transient
view/session state and is not persisted with the workspace snapshot.

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

### Modification-date ordering verification (2026-11-03)

Source `38dea03`: 149 macOS tests pass on arm64; Debug universal analysis and
universal Release build pass on Xcode 27.2. The signed Release was installed to
`/Applications/NeatEditor.app`; installed/product executable SHA256 matches
`53fa2a5a37a6d51426bb3a7171da0a3720c3c51d559d39314b9c2c89c21647ac`.
A fresh installed-window capture showed the first three files in the same order
as their descending on-disk content modification dates. Regression tests cover
changed-date reordering and equal-date natural filename ordering.

Complete logs, result bundle and private capture are retained under
`~/.config/neateditor/verification/2026-11-03-file-order/`; captures may contain
private document content and must not be published. The only build diagnostic
is the existing AppIntents metadata-step warning assessed in
`docs/code-review.md` (Sidebar review, 2026-10-24); no compiler,
analyzer or structured runtime warnings were found. Native Intel tests, dark
appearance and pointer interaction were not established by this check. iOS
uses the same ordering and has a cross-client metadata-order regression; its
device-delivery limits are recorded in the iOS knowledge base.

## Acceptance

Use the installed `/Applications/NeatEditor.app`, not just a build/test result.

1. Inspect a screenshot against the owner's rejected two-row capture.
2. Click the actual sidebar toolbar control repeatedly; inspect expanded and
   collapsed screenshots and select a tab in both states.
3. Repeat at normal/minimum width; resize the native divider.
4. Save, switch documents and refresh; the most recently modified file must
   appear first. Equal-date files retain deterministic filename/path order;
   preview-only refreshes must not alter dates.
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

Feature commit `0f7ac6e`. The installed Release was built from `b01d946`, the
last code-affecting commit; the later commits on this branch are tests and
documentation only. Release hash:
`2bec9be3389767506a03d728ce02b2d4080e28fb544a574db8b37702900e711d`.
It is signed with the same Developer ID identity; the installed executable hash
and signature match the build product. A Release from the intermediate
`9f82c38` was also installed and used for the live close-fallback inspection
below.

The clean final source archive passed 99 tests in 14 suites, including
`WorkspaceSidebarRevealTests`, which hosts the real `WorkspaceSidebarView` with
80 files and asserts: the restored bottom selection reveals at launch, an
external selection of the top row scrolls up, a fully visible row does not move
the list, an external selection of a middle or bottom row scrolls down, preview
changes do not move the list, `openSidebarFile` (the sidebar binding path) does
not move it, and a file selected before the asynchronous refresh lists it is
revealed once the row appears. Debug analyze passed without compiler or
static-analysis warnings; only the previously assessed AppIntents
metadata-step note remains in test/build logs.

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
