import AppKit

/// One native owner for tab identity, layout, scrolling and interaction.
/// SwiftUI supplies descriptors/actions, never pixel geometry.
final class EditorTabStripView: NSView {
    static let titleBarHeight = EditorTabLayout.stripHeight
    static let minimumWindowEdge = EditorTabLayout.minimumWindowEdge

    private(set) var tabs: [EditorTabDescriptor] = []
    private(set) var selectedTabID: UUID?
    private(set) var tabViews: [UUID: EditorTabItemView] = [:]
    var actions = EditorTabActions()
    weak var topRule: EditorTabTopRuleView?
    var editingTabID: UUID?
    var renameEligibleID: UUID?
    var renameClickMonitor: Any?
    private var scrollStepper = EditorTabScrollStepper()
    private let scrollView = EditorTabScrollView()
    private let canvas = EditorTabCanvas()
    private let leadingFade = CAGradientLayer()
    private let trailingFade = CAGradientLayer()

    override var isFlipped: Bool { true }
    override var wantsDefaultClipping: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        focusRingType = .none
        wantsLayer = true
        layer?.masksToBounds = false
        scrollView.strip = self
        canvas.strip = self
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.horizontalScrollElasticity = .none
        scrollView.verticalScrollElasticity = .none
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.documentView = canvas
        addSubview(scrollView)
        for fade in [leadingFade, trailingFade] {
            fade.zPosition = 100
            fade.startPoint = CGPoint(x: 0, y: 0.5)
            fade.endPoint = CGPoint(x: 1, y: 0.5)
            layer?.addSublayer(fade)
        }
        setAccessibilityRole(.tabGroup)
        setAccessibilityLabel(String(localized: "Documents"))
        NotificationCenter.default.addObserver(
            self, selector: #selector(didScroll), name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(applicationDeactivated),
            name: NSApplication.didResignActiveNotification, object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(tabs: [EditorTabDescriptor], selectedTabID: UUID?, actions: EditorTabActions) {
        self.actions = actions
        guard self.tabs != tabs || self.selectedTabID != selectedTabID else { return }
        if let editingTabID,
           selectedTabID != editingTabID || !tabs.contains(where: { $0.id == editingTabID }) {
            finishRename(commit: true)
        }
        let ids = Set(tabs.map(\.id))
        for id in Array(tabViews.keys) where !ids.contains(id) {
            tabViews.removeValue(forKey: id)?.removeFromSuperview()
        }
        self.tabs = tabs
        self.selectedTabID = selectedTabID
        for tab in tabs {
            let item: EditorTabItemView
            if let existing = tabViews[tab.id] {
                item = existing
            } else {
                item = EditorTabItemView(descriptor: tab)
                item.strip = self
                tabViews[tab.id] = item
                canvas.addSubview(item)
            }
            item.update(descriptor: tab, selected: tab.id == selectedTabID)
        }
        if let selectedTabID, let selected = tabViews[selectedTabID] {
            canvas.addSubview(selected, positioned: .above, relativeTo: nil)
        }
        needsLayout = true
        topRule?.needsDisplay = true
    }

    override func layout() {
        super.layout()
        let viewportWidth = max(0, bounds.width - EditorTabLayout.trailingPadding)
        // One extra point carries the tab's join into the editor's top rule.
        scrollView.frame = CGRect(x: 0, y: 0, width: viewportWidth, height: bounds.height + 1)
        scrollView.tile()
        var x: CGFloat = 0
        for tab in tabs {
            let width = EditorTabLayout.width(for: tab.title)
            tabViews[tab.id]?.frame = CGRect(
                x: x - ConnectedTabGeometry.baselineOutset,
                y: bounds.height - EditorTabLayout.tabHeight,
                width: width + 2 * ConnectedTabGeometry.baselineOutset,
                height: EditorTabLayout.tabHeight + 1
            )
            x += width
        }
        canvas.frame.size = CGSize(width: max(viewportWidth, x + EditorTabLayout.trailingPadding),
                                   height: bounds.height + 1)
        let selectedFrame = selectedTabID.flatMap { tabViews[$0] }.map {
            canvas.convert($0.tabBounds, from: $0)
                .insetBy(dx: -ConnectedTabGeometry.baselineOutset, dy: 0)
        }
        let offset = EditorTabLayout.revealedOffset(
            selectedFrame: selectedFrame, viewportWidth: viewportWidth,
            contentWidth: canvas.bounds.width, currentOffset: scrollView.contentView.bounds.minX
        )
        scrollView.contentView.scroll(to: CGPoint(x: offset, y: 0))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        geometryDidChange()
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
        tabViews.values.forEach { $0.needsDisplay = true }
        geometryDidChange()
    }

    /// Evaluated at drawing time, after native layout. Never a copied frame.
    func selectedTabGap(in rule: NSView) -> ClosedRange<CGFloat>? {
        guard let window, rule.window === window, !isHiddenOrHasHiddenAncestor,
              let selectedTabID, let tab = tabViews[selectedTabID] else { return nil }
        let tabFrame = rule.convert(tab.tabBounds, from: tab)
        let viewport = rule.convert(scrollView.contentView.bounds, from: scrollView.contentView)
        let lower = max(tabFrame.minX - ConnectedTabGeometry.baselineOutset, viewport.minX)
        let upper = min(tabFrame.maxX + ConnectedTabGeometry.baselineOutset, viewport.maxX)
        return lower < upper ? lower...upper : nil
    }

    private func geometryDidChange() {
        let offset = scrollView.contentView.bounds.minX
        let width = scrollView.contentView.bounds.width
        let color = NSColor.windowBackgroundColor.cgColor
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        leadingFade.frame = CGRect(x: 0, y: 0, width: EditorTabLayout.fadeWidth, height: bounds.height)
        trailingFade.frame = CGRect(x: max(0, width - EditorTabLayout.fadeWidth), y: 0,
                                    width: EditorTabLayout.fadeWidth, height: bounds.height)
        leadingFade.colors = [color, NSColor.windowBackgroundColor.withAlphaComponent(0).cgColor]
        trailingFade.colors = [NSColor.windowBackgroundColor.withAlphaComponent(0).cgColor, color]
        leadingFade.isHidden = offset < 1
        trailingFade.isHidden = offset + width >= canvas.bounds.width - 1
        CATransaction.commit()
        topRule?.needsDisplay = true
    }

    @objc private func didScroll(_ notification: Notification) { geometryDidChange() }

    func handleScroll(_ event: NSEvent) {
        guard editingTabID == nil else { return }
        guard event.momentumPhase.isEmpty,
              !event.phase.contains(.ended), !event.phase.contains(.cancelled) else {
            scrollStepper.reset()
            return
        }
        let x = event.hasPreciseScrollingDeltas ? event.scrollingDeltaX : event.deltaX
        let y = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY
        for step in scrollStepper.steps(
            delta: abs(y) >= abs(x) ? y : x, timestamp: event.timestamp,
            precise: !event.phase.isEmpty || !event.momentumPhase.isEmpty
        ) {
            actions.onSelectRelative(step)
        }
    }

    func handleSwipe(_ event: NSEvent) {
        guard editingTabID == nil else { return }
        scrollStepper.reset()
        let delta = abs(event.deltaY) >= abs(event.deltaX) ? event.deltaY : event.deltaX
        if delta != 0 { actions.onSelectRelative(delta > 0 ? -1 : 1) }
    }

    override func mouseDown(with event: NSEvent) { trackPointer(event, tabID: nil) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { finishRename(commit: true) }
        super.viewWillMove(toWindow: newWindow)
    }

    @objc private func applicationDeactivated(_ notification: Notification) {
        finishRename(commit: true)
    }
}

private final class EditorTabCanvas: NSView {
    weak var strip: EditorTabStripView?
    override var isFlipped: Bool { true }
    override func mouseDown(with event: NSEvent) { strip?.trackPointer(event, tabID: nil) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private final class EditorTabScrollView: NSScrollView {
    weak var strip: EditorTabStripView?
    override func scrollWheel(with event: NSEvent) { strip?.handleScroll(event) }
    override func swipe(with event: NSEvent) { strip?.handleSwipe(event) }
}
