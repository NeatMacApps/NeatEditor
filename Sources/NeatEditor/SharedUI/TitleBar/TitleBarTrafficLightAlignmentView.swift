import AppKit
import SwiftUI

struct TitleBarTrafficLightAlignmentView: NSViewRepresentable {
    let titleBarHeight: CGFloat
    let isWindowPinned: Bool

    func makeNSView(context: Context) -> TrafficLightAlignmentHostingView {
        TrafficLightAlignmentHostingView(
            titleBarHeight: titleBarHeight,
            isWindowPinned: isWindowPinned
        )
    }

    func updateNSView(_ nsView: TrafficLightAlignmentHostingView, context: Context) {
        nsView.titleBarHeight = titleBarHeight
        nsView.isWindowPinned = isWindowPinned
        nsView.centerTrafficLightsIfNeeded()
    }
}

final class TrafficLightAlignmentHostingView: NSView {
    var titleBarHeight: CGFloat {
        didSet {
            centerTrafficLightsIfNeeded()
        }
    }
    var isWindowPinned: Bool {
        didSet {
            applyWindowPinningIfNeeded()
            updateHoverFocusMonitoring()
        }
    }
    private var hoverGlobalMonitor: Any?
    private var hoverLocalMonitor: Any?

    init(titleBarHeight: CGFloat, isWindowPinned: Bool) {
        self.titleBarHeight = titleBarHeight
        self.isWindowPinned = isWindowPinned
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureWindowObserver()
        centerTrafficLightsIfNeeded()
        applyWindowPinningIfNeeded()
        updateHoverFocusMonitoring()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if let window {
            NotificationCenter.default.removeObserver(
                self,
                name: NSWindow.didResizeNotification,
                object: window
            )
            if window != newWindow {
                window.level = .normal
            }
        }
        if newWindow == nil {
            stopHoverFocusMonitoring()
        }

        super.viewWillMove(toWindow: newWindow)
    }

    override func layout() {
        super.layout()
        centerTrafficLightsIfNeeded()
    }



    func centerTrafficLightsIfNeeded() {
        guard let window,
              let closeButton = window.standardWindowButton(.closeButton),
              let minimizeButton = window.standardWindowButton(.miniaturizeButton),
              let zoomButton = window.standardWindowButton(.zoomButton),
              let buttonContainer = closeButton.superview else {
            return
        }

        let nativeTitleBarHeight = window.frame.height - window.contentLayoutRect.height
        let resolvedTitleBarHeight = max(titleBarHeight, nativeTitleBarHeight)
        let targetOriginY = buttonContainer.frame.height - resolvedTitleBarHeight
            + ((resolvedTitleBarHeight - closeButton.frame.height) / 2)

        for button in [closeButton, minimizeButton, zoomButton] {
            guard abs(button.frame.origin.y - targetOriginY) > 0.5 else {
                continue
            }

            button.setFrameOrigin(
                NSPoint(
                    x: button.frame.origin.x,
                    y: round(targetOriginY)
                )
            )
        }
    }

    private func configureWindowObserver() {
        guard let window else {
            return
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowDidResize),
            name: NSWindow.didResizeNotification,
            object: window
        )
    }

    @objc
    private func handleWindowDidResize() {
        centerTrafficLightsIfNeeded()
    }

    private func applyWindowPinningIfNeeded() {
        guard let window else {
            return
        }

        let targetLevel: NSWindow.Level = isWindowPinned ? .floating : .normal
        guard window.level != targetLevel else {
            updateHoverFocusMonitoring()
            return
        }

        window.level = targetLevel
        updateHoverFocusMonitoring()
    }

    /// 置顶后鼠标进入窗口即抢回 key 焦点，便于并排多应用快速切换输入。
    /// 跟随图钉默认开，无独立开关、无悬停延迟。
    private func updateHoverFocusMonitoring() {
        guard isWindowPinned, window != nil else {
            stopHoverFocusMonitoring()
            return
        }

        startHoverFocusMonitoring()
    }

    private func startHoverFocusMonitoring() {
        guard hoverGlobalMonitor == nil, hoverLocalMonitor == nil else {
            return
        }

        hoverGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            Task { @MainActor in
                self?.handleHoverFocusTick()
            }
        }
        hoverLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            Task { @MainActor in
                self?.handleHoverFocusTick()
            }
            return event
        }
    }

    private func stopHoverFocusMonitoring() {
        if let hoverGlobalMonitor {
            NSEvent.removeMonitor(hoverGlobalMonitor)
        }
        if let hoverLocalMonitor {
            NSEvent.removeMonitor(hoverLocalMonitor)
        }
        hoverGlobalMonitor = nil
        hoverLocalMonitor = nil
    }

    @MainActor
    private func handleHoverFocusTick() {
        guard isWindowPinned,
            let window,
            window.isVisible,
            !window.isMiniaturized,
            !window.isKeyWindow,
            window.attachedSheet == nil,
            NSApp.modalWindow == nil,
            NSEvent.pressedMouseButtons == 0
        else {
            return
        }

        guard window.frame.contains(NSEvent.mouseLocation) else {
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
