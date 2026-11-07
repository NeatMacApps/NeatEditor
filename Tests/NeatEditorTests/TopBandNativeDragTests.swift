import AppKit
import Testing

@testable import NeatEditor

@MainActor
struct TopBandNativeDragTests {
    private func makeWindow() -> NativeDragRecordingWindow {
        let window = NativeDragRecordingWindow(
            contentRect: CGRect(x: 200, y: 200, width: 900, height: 500),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSView(frame: CGRect(x: 0, y: 0, width: 900, height: 500))
        window.layoutIfNeeded()
        return window
    }

    private func event(_ type: NSEvent.EventType = .leftMouseDown,
                       at point: NSPoint, in window: NSWindow, clicks: Int = 1) throws -> NSEvent {
        try #require(NSEvent.mouseEvent(
            with: type, location: point, modifierFlags: [], timestamp: 1,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0,
            clickCount: clicks, pressure: 1
        ))
    }

    @Test("top press enables native dragging without consuming or moving anything")
    func nativeEligibility() throws {
        let window = makeWindow()
        defer { window.close() }
        let controller = TopBandDragController()
        let point = NSPoint(x: 500, y: window.frame.height - 14)
        let down = try event(at: point, in: window)
        let origin = window.frame.origin
        #expect(controller.handle(down, in: window) === down)
        #expect(window.isMovableByWindowBackground)
        for type in [NSEvent.EventType.leftMouseDragged, .leftMouseUp] {
            let subsequent = try event(type, at: NSPoint(x: point.x + 30, y: point.y + 20), in: window)
            #expect(controller.handle(subsequent, in: window) === subsequent)
        }
        #expect(window.forwardedPresses.isEmpty)
        #expect(window.frame.origin == origin)
        let contentPress = try event(at: NSPoint(x: 500, y: 100), in: window)
        #expect(controller.handle(contentPress, in: window) === contentPress)
        #expect(!window.isMovableByWindowBackground)
    }

    @Test("multiple clicks retain native delivery and eligibility", arguments: [2, 3])
    func doubleClickPassThrough(clicks: Int) throws {
        let window = makeWindow()
        defer { window.close() }
        let controller = TopBandDragController()
        let down = try event(at: NSPoint(x: 500, y: window.frame.height - 14), in: window, clicks: clicks)
        #expect(controller.handle(down, in: window) === down)
        #expect(window.isMovableByWindowBackground)
        #expect(window.forwardedPresses.isEmpty)
    }

    @Test("both upper corners and the native top edge retain resize ownership")
    func resizePassThrough() throws {
        let window = makeWindow()
        defer { window.close() }
        let controller = TopBandDragController()
        for x in [CGFloat(2), window.frame.width / 2, window.frame.width - 2] {
            window.isMovableByWindowBackground = true
            let down = try event(at: NSPoint(x: x, y: window.frame.height - 2), in: window)
            #expect(controller.handle(down, in: window) === down)
            #expect(!window.isMovableByWindowBackground)
        }
        #expect(window.forwardedPresses.isEmpty)
    }

    @Test("install and remove are idempotent and restore the original window flag")
    func monitorLifecycle() {
        let window = makeWindow()
        defer { window.close() }
        window.isMovableByWindowBackground = false
        let controller = TopBandDragController()
        controller.install(in: window)
        controller.install(in: window)
        #expect(controller.isInstalled)
        window.isMovableByWindowBackground = true
        controller.remove()
        controller.remove()
        #expect(!controller.isInstalled)
        #expect(!window.isMovableByWindowBackground)
    }

    @Test("a tab forwards the original press after four points without awaiting a release")
    func tabNativeHandoff() throws {
        let window = makeWindow()
        defer { window.close() }
        let strip = EditorTabStripView(frame: CGRect(x: 0, y: 0, width: 600, height: 40))
        window.contentView?.addSubview(strip)
        strip.nextResponder = window
        let point = NSPoint(x: 100, y: 20)
        let down = try event(at: point, in: window)
        window.queuedEvents = [
            try event(.leftMouseDragged, at: NSPoint(x: 102, y: 21), in: window),
            try event(.leftMouseDragged, at: NSPoint(x: 106, y: 23), in: window)
        ]
        strip.trackPointer(down, tabID: UUID())
        #expect(window.forwardedPresses.count == 1)
        #expect(window.forwardedPresses.first === down)
        #expect(window.queuedEvents.isEmpty)
    }
}

@MainActor
private final class NativeDragRecordingWindow: NSWindow {
    var forwardedPresses: [NSEvent] = []
    var queuedEvents: [NSEvent] = []

    override func mouseDown(with event: NSEvent) {
        forwardedPresses.append(event)
    }

    override func nextEvent(matching mask: NSEvent.EventTypeMask, until expiration: Date?,
                            inMode mode: RunLoop.Mode, dequeue deqFlag: Bool) -> NSEvent? {
        guard !queuedEvents.isEmpty else { return nil }
        return queuedEvents.removeFirst()
    }
}
