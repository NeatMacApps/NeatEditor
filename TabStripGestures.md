# Tab Strip Gestures

This document describes the gesture requirements, pin accessory alignment, and implementation details for `EditorTabStripView.swift` and its child views.

---

## Requirements Overview

1. **Single-click a tab**
   * **Behavior**: Switch to the selected tab immediately.
   * **Performance requirement**: **No delay**. Single-clicks must not feel slower because the system is waiting to see whether the user double-clicks.

2. **Double-click the active tab**
   * **Behavior**: Enter inline rename mode for the current tab title.

3. **Double-click an inactive tab**
   * **Behavior**: Select the tab only. It must not enter rename mode.

4. **Double-click empty title bar space**
   * **Behavior**: Let AppKit perform the system-configured title bar action exactly once. The window must retain its resulting size until the next user action.

5. **Click inside the rename field while editing**
   * **Behavior**: Move the insertion point normally without leaving edit mode.

6. **Click outside the title bar while editing**
   * **Behavior**: Save the edited title and leave edit mode.

7. **Switch to another app while editing**
   * **Behavior**: Save the edited title and leave edit mode.

8. **Top-right pin alignment**
   * **Behavior**: Center the circular pin control equally from the window's top and right edges, following the top-right corner's concentric placement. Derive both insets from the title bar height and button diameter. The space reserved for tab overflow must not shift the pin inward.
   * **Acceptance**: Inspect the installed window at normal and minimum widths, both unpinned and pinned. Clicking the pin must still toggle Always on Top.

   The original accessory frame put the center 28 pt from the right edge but 18 pt from the top. Use the native SwiftUI `Button` with the public [frame and padding APIs](https://developer.apple.com/documentation/swiftui/layout-adjustments), verified in the Xcode 27 SDK. Installed Release verification on 2026-10-01 measured 19 pt on both axes at 901 × 538 and the actual minimum 470 × 502; screenshots confirmed both states, and clicking switched the window between normal layer 0 and floating layer 3. The screenshot skill's default window list filters floating layers; use its raw window enumeration and capture helper for the pinned window rather than treating the missing list entry as a hidden app.

---

## Core Constraint: Why SwiftUI Gestures Are Not Allowed

**Do not add `.onTapGesture` or `.simultaneousGesture(TapGesture(...))` to `EditorTabStripView` or any of its ancestors.**

Reason: SwiftUI multi-click gestures (`TapGesture(count: 2)` and `.onTapGesture(count: 2)`) inject click recognition delay into the entire view tree. Even if the double-click handler lives on a parent, child views with single-click interactions, including `Button` actions, are forced to wait for the double-click window (about 250 ms). That directly violates the no-delay requirement above.

**Conclusion**: All click and double-click handling must bypass the SwiftUI gesture system and use the following mechanisms instead:
- **Tab click and double-click**: SwiftUI `Button` action for immediate response plus manual timestamp-based double-click detection
- **Empty title bar double-click**: Native AppKit dispatch through SwiftUI `.windowStyle(.hiddenTitleBar)`
- **Edit dismissal and middle-click close**: AppKit `NSEvent.addLocalMonitorForEvents`

---

## Architecture

### Participating Components

| Component | Responsibility |
|------|------|
| `EditorTabStripView` | Parent container that owns `editingTabID` state and provides `dismissEditing()` |
| `EditorTabItemView` | Per-tab view with a SwiftUI `Button` that handles click, double-click, and rename |
| `TitleBarEventMonitor` | `NSViewRepresentable` event monitor at the AppKit layer |
| `tabStripPendingRename` | File-scoped flag that stores the pending renamed title for external dismiss paths |

### Data Flow

```text
User input
  |
  |- mouseDown --> TitleBarEventMonitor
  |                 `- Outside title bar + editing in progress -> dismissEditing()
  |
  |- empty title bar double-click --> native AppKit window action
  |
  |- middle mouseUp --> TitleBarEventMonitor -> close the hit tab
  |
  `- tab mouseUp --> SwiftUI Button (EditorTabItemView.handleClick)
                    |- Selected tab + timestamp double-click check -> begin editing
                    `- Otherwise -> onSelectTab
```

---

## Detailed Implementation Notes

### 1. Single-click tab switching with no delay

`EditorTabItemView` uses a SwiftUI `Button` with `.buttonStyle(.plain)`, and the action directly calls `handleClick()`. `Button` fires immediately on `mouseUp` without gesture recognition delay.

### 2. Double-click rename via manual timestamp detection

Inside `handleClick()`, double-clicks are detected manually with `lastSelectedClickTime` and `NSEvent.doubleClickInterval`:

```swift
if isSelected {
    let now = Date()
    if now.timeIntervalSince(lastSelectedClickTime) < NSEvent.doubleClickInterval {
        // Double-clicking the selected tab enters rename mode.
        isEditing = true
        return
    }
    lastSelectedClickTime = now
}
```

Key details:
- Record timestamps and check for double-clicks only when `isSelected == true`.
- A double-click on an inactive tab never renames it: the first click only selects the tab and resets `lastSelectedClickTime` to `.distantPast`, so the second click is treated as the first eligible click for rename timing.

### 3. Native title bar double-click ownership

The main scene uses the public SwiftUI `.windowStyle(.hiddenTitleBar)` API. It hides the title and title bar backing while retaining native window behavior. Empty title bar double-clicks pass through normal AppKit dispatch; the monitor must not call `zoom`, `performZoom` or `performMiniaturize` for the same event. Tab buttons retain immediate selection and inline rename behavior.

Confirmed regression (2026-10-01): the installed app expanded from 901 × 538 to approximately 2228 × 1266, then returned to 901 × 538 within one second. The local monitor forwarded the event and separately queued `window.zoom(nil)`, leaving two handlers for one double-click. Removing the extra window action restores one native action and avoids duplicating the system preference mapping.

Public API verified in the installed Xcode 27 SDK:
- [SwiftUI hiddenTitleBar](https://developer.apple.com/documentation/swiftui/windowstyle/hiddentitlebar)
- [AppKit local event monitoring](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/MonitoringEvents/MonitoringEvents.html)
- [macOS title bar double-click settings](https://support.apple.com/en-gb/guide/mac-help/mchlp1119/mac)

Acceptance: use the installed app, double-click empty title bar space to enlarge, wait beyond the animation, then double-click again to restore. Inspect sequential window bounds and screenshots. Verify active-tab rename, inactive-tab selection, dragging and pinning without unwanted resizing. Build/test success alone does not establish this behavior.

### 4. Leaving edit mode and saving the title

Edit mode has multiple exit paths with slightly different commit behavior:

#### Path A: Press Enter (`onSubmit`)
`commitTitleEditing()` calls `onRename(sanitizedTitle)` directly and then sets `isEditing = false`.

#### Path B: Click outside (`monitor` dismiss)
1. The monitor sees a `mouseDown` outside the title bar region (`!isClickInTitleBarRegion`).
2. It asynchronously calls `EditorTabStripView.dismissEditing()`.
3. `dismissEditing()` reads the pending title from `tabStripPendingRename` and calls `onRenameTab`.
4. It sets `editingTabID = nil`, which makes `isEditing` false and removes the `TextField`.

**Why `tabStripPendingRename` is used instead of `onDisappear`**:
- `onDisappear` fires while the view is being torn down. Writing back to bindings at that point, such as `isEditing = false`, or calling `onRename` can trigger a render cascade and spike CPU usage.
- `tabStripPendingRename` is kept in sync through `onChange(of: draftTitle)`, so `dismissEditing()` can read the current draft title before the field disappears.

#### Path C: Switch to another app
`NSApplication.didResignActiveNotification` follows the same path as Path B.

### 5. Clicking inside the rename field does not dismiss edit mode

The monitor only dismisses editing on `mouseDown` when `!isClickInTitleBarRegion(event)` is true. The rename `TextField` lives inside the title bar region, so clicking it does not dismiss editing and caret movement works as expected.

---

## Pitfalls and Maintenance Notes

### Do Not Do These Things

1. **Do not add `.onTapGesture` or `.simultaneousGesture(TapGesture(...))` to `EditorTabStripView` or its ancestors.** This introduces roughly 250 ms of click delay to child views.

2. **Do not write to bindings or mutate the model from `onDisappear`.** During view teardown, that can trigger render cascades. With rapid double-clicks, repeated `TextField` creation and destruction can spike CPU usage dramatically.

3. **Do not manually trigger a window action from the local monitor.** Native AppKit owns empty title bar double-clicks; an extra deferred zoom toggles the window back.

4. **Do not trigger commits from `onChange(of: isEditing)`.** `commitTitleEditing()` sets `isEditing = false` through the `editingTabID` binding, which can create a write-notify-write loop.

5. **Do not use `view is NSText` to decide whether the click happened inside the rename field.** The editor itself is also an `NSTextView` subclass, so type checks misclassify clicks. The current implementation uses title bar region checks instead.

6. **Do not consume tab mouse events to prevent a duplicate custom zoom.** Remove the duplicate zoom; keep native button dispatch and rename behavior intact.
