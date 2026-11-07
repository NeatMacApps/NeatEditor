import AppKit

/// Owner requirement (2026-11-07): the whole visible top region drags the
/// window — the sidebar column above its list, the tab gutter, blank space and
/// the tabs themselves. Native titlebar routing in this app's opaque
/// `unifiedCompact` shell either claims some of those points itself or hands
/// them to content, so a window-level monitor owns the decision instead of
/// relying on hit-test results alone.
///
/// Controls keep their own clicks: tab bodies, `+`, pin, the sidebar button,
/// traffic lights and any other native control or text editor are passed
/// through untouched. A double-click on blank band space is forwarded to the
/// native frame view so the user's Desktop & Dock preference still decides
/// between zoom and minimize.
@MainActor
final class TopBandDragController {
    /// The same threshold the tabs use, so a press without movement stays a click.
    static let dragThreshold: CGFloat = 4

    /// The band hosting tabs, `+` and pin; used for the full-screen layout where
    /// no native titlebar exists.
    weak var tabBand: NSView?

    private weak var window: NSWindow?
    private var monitor: Any?

    var isInstalled: Bool { monitor != nil }

    func install(in window: NSWindow) {
        guard self.window !== window else { return }
        remove()
        self.window = window
        monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self, weak window] event in
            guard let self, let window, event.window === window else { return event }
            return self.handleMouseDown(event, in: window) ? nil : event
        }
    }

    func remove() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        window = nil
    }

    /// Returns `true` when the event was consumed for a window drag or a native
    /// blank double-click.
    @discardableResult
    func handleMouseDown(_ event: NSEvent, in window: NSWindow) -> Bool {
        let point = event.locationInWindow
        guard isInsideTopBand(point, in: window) else { return false }
        guard !isInteractive(at: point, in: window) else { return false }
        if event.clickCount >= 2 {
            // The frame view owns the system double-click action (zoom or
            // minimize, per Desktop & Dock). Never emulate the preference.
            window.contentView?.superview?.mouseDown(with: event)
            return true
        }
        trackDrag(of: window)
        return true
    }

    /// Window-coordinate band: the native titlebar row, or the reserved band
    /// when full screen keeps the same controls in the content view.
    func topBandRect(in window: NSWindow) -> CGRect {
        let contentTop = window.contentLayoutRect.maxY
        var rect = CGRect(x: 0, y: contentTop,
                          width: window.frame.width,
                          height: max(0, window.frame.height - contentTop))
        if let tabBand, tabBand.window === window, !tabBand.isHiddenOrHasHiddenAncestor {
            rect = rect.union(tabBand.convert(tabBand.bounds, to: nil))
        }
        return rect
    }

    func isInsideTopBand(_ point: NSPoint, in window: NSWindow) -> Bool {
        topBandRect(in: window).contains(point)
    }

    /// A hit belongs to a control, text field or text editor, which keep their
    /// own behaviour. Blank band regions and non-interactive content drag.
    func isInteractive(at point: NSPoint, in window: NSWindow) -> Bool {
        guard let root = window.contentView?.superview,
              let hit = root.hitTest(root.convert(point, from: nil)) else {
            return false
        }
        return Self.isInteractiveHit(hit)
    }

    static func isInteractiveHit(_ hit: NSView) -> Bool {
        var view: NSView? = hit
        while let current = view {
            if current is NSControl || current is NSText || current is NSTextView {
                return true
            }
            view = current.superview
        }
        return false
    }

    private func trackDrag(of window: NSWindow) {
        let startMouse = NSEvent.mouseLocation
        let startOrigin = window.frame.origin
        var isDragging = false
        while let event = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp],
                                           until: .distantFuture, inMode: .eventTracking,
                                           dequeue: true) {
            if event.type == .leftMouseUp { return }
            let mouse = NSEvent.mouseLocation
            let delta = CGPoint(x: mouse.x - startMouse.x, y: mouse.y - startMouse.y)
            if max(abs(delta.x), abs(delta.y)) >= Self.dragThreshold {
                isDragging = true
            }
            guard isDragging else { continue }
            window.setFrameOrigin(WindowDragGeometry.clampedOrigin(
                CGPoint(x: startOrigin.x + delta.x, y: startOrigin.y + delta.y),
                for: window
            ))
        }
    }
}

/// Shared drag geometry so tab dragging and blank-band dragging clamp alike.
@MainActor
enum WindowDragGeometry {
    static func clampedOrigin(_ origin: CGPoint, for window: NSWindow) -> CGPoint {
        guard let screen = (window.screen ?? NSScreen.main)?.visibleFrame else { return origin }
        return CGPoint(
            x: min(max(origin.x, screen.minX - window.frame.width + 80), screen.maxX - 80),
            y: min(max(origin.y, screen.minY - window.frame.height + 40), screen.maxY - 40)
        )
    }
}
