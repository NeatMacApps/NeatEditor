import AppKit

/// Gates AppKit's native background dragging to the top row on each press.
/// Every event keeps its normal delivery; this never moves the window itself.
@MainActor
final class TopBandDragController {
    static let resizeMargin: CGFloat = 6

    weak var tabBand: NSView?
    private weak var window: NSWindow?
    private var monitor: Any?
    private var originalBackgroundDrag = false

    var isInstalled: Bool { monitor != nil }

    func install(in window: NSWindow) {
        guard self.window !== window else { return }
        remove()
        self.window = window
        originalBackgroundDrag = window.isMovableByWindowBackground
        monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) {
            [weak self, weak window] event in
            guard let self, let window, event.window === window else { return event }
            return self.handle(event, in: window)
        }
    }

    func remove() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        window?.isMovableByWindowBackground = originalBackgroundDrag
        window = nil
    }

    /// Change native eligibility before normal window dispatch, including for
    /// multiple clicks. Never consume a press, drag or release.
    func handle(_ event: NSEvent, in window: NSWindow) -> NSEvent? {
        guard event.type == .leftMouseDown else { return event }
        window.isMovableByWindowBackground = !window.styleMask.contains(.fullScreen)
            && canStartDrag(at: event.locationInWindow, in: window)
        if !window.isKeyWindow, topBandRect(in: window).contains(event.locationInWindow) {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
        }
        return event
    }

    func canStartDrag(at point: NSPoint, in window: NSWindow) -> Bool {
        topBandRect(in: window).contains(point)
            && !isInResizeMargin(point, in: window)
            && !isInteractive(at: point, in: window)
    }

    func isInResizeMargin(_ point: NSPoint, in window: NSWindow) -> Bool {
        guard window.styleMask.contains(.resizable) else { return false }
        let margin = Self.resizeMargin
        return point.x < margin || point.x > window.frame.width - margin
            || point.y < margin || point.y > window.frame.height - margin
    }

    func topBandRect(in window: NSWindow) -> CGRect {
        let contentTop = window.contentLayoutRect.maxY
        var rect = CGRect(x: 0, y: contentTop, width: window.frame.width,
                          height: max(0, window.frame.height - contentTop))
        if let tabBand, tabBand.window === window, !tabBand.isHiddenOrHasHiddenAncestor {
            rect = rect.union(tabBand.convert(tabBand.bounds, to: nil))
        }
        return rect
    }

    func isInteractive(at point: NSPoint, in window: NSWindow) -> Bool {
        guard let root = window.contentView?.superview,
              let hit = root.hitTest(root.convert(point, from: nil)) else { return false }
        var view: NSView? = hit
        while let current = view {
            // A tab distinguishes click/rename from drag before forwarding the
            // original press. Its close button and rename field remain controls.
            if current is EditorTabItemView { return false }
            if current is NSControl || current is NSText { return true }
            view = current.superview
        }
        return false
    }
}
