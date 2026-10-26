import AppKit

/// One native owner for tab identity, layout, scrolling and interaction.
/// SwiftUI supplies descriptors/actions, never pixel geometry.
final class EditorTabStripView: NSView {
    static let minimumWindowEdge = EditorTabLayout.minimumWindowEdge

    private(set) var tabs: [EditorTabDescriptor] = []
    private(set) var selectedTabID: UUID?
    private(set) var tabViews: [UUID: EditorTabItemView] = [:]
    var actions = EditorTabActions()
    /// Titlebar regions owned by native accessories (sidebar button, pin).
    var contentInsets = NSEdgeInsets() {
        didSet { needsLayout = true }
    }
    weak var topRule: EditorTabTopRuleView?
    var editingTabID: UUID?
    var renameEligibleID: UUID?
    var renameClickMonitor: Any?
    private var scrollStepper = EditorTabScrollStepper()
    private let scrollView = EditorTabScrollView()
    private let canvas = EditorTabCanvas()
    private let newDocumentButton = NSButton()
    private let leadingFade = CAGradientLayer()
    private let trailingFade = CAGradientLayer()

    override var isFlipped: Bool { true }
    override var wantsDefaultClipping: Bool { false }
    override var mouseDownCanMoveWindow: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        focusRingType = .none
        wantsLayer = true
        layer?.masksToBounds = false
        scrollView.strip = self
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
        configureNewDocumentButton()
        setAccessibilityChildren([newDocumentButton])
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
        setAccessibilityChildren(tabs.compactMap { tabViews[$0.id] } + [newDocumentButton])
        if let selectedTabID, let selected = tabViews[selectedTabID] {
            canvas.addSubview(selected, positioned: .above, relativeTo: nil)
        }
        needsLayout = true
        topRule?.needsDisplay = true
    }

    private func configureNewDocumentButton() {
        let label = String(localized: "New Document")
        newDocumentButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: label)
        newDocumentButton.symbolConfiguration = .init(pointSize: EditorTabLayout.actionSymbolSize, weight: .regular)
        newDocumentButton.isBordered = false
        newDocumentButton.imagePosition = .imageOnly
        newDocumentButton.contentTintColor = .secondaryLabelColor
        newDocumentButton.focusRingType = .none
        newDocumentButton.toolTip = label
        newDocumentButton.setAccessibilityLabel(label)
        newDocumentButton.target = self
        newDocumentButton.action = #selector(newDocument(_:))
        addSubview(newDocumentButton)
    }

    @objc private func newDocument(_ sender: Any?) { actions.onNewDocument() }

    override func layout() {
        super.layout()
        let viewportX = contentInsets.left
        let viewportWidth = max(0, bounds.width - contentInsets.left - contentInsets.right
            - EditorTabLayout.newDocumentSlotWidth)
        // One extra point carries the tab's join into the editor's top rule.
        scrollView.frame = CGRect(x: viewportX, y: 0, width: viewportWidth, height: bounds.height + 1)
        scrollView.tile()
        var x: CGFloat = 0
        for tab in tabs {
            let width = EditorTabLayout.tabWidth
            tabViews[tab.id]?.frame = CGRect(
                x: x - ConnectedTabGeometry.baselineOutset,
                y: bounds.height - EditorTabLayout.tabHeight,
                width: width + 2 * ConnectedTabGeometry.baselineOutset,
                height: EditorTabLayout.tabHeight + 1
            )
            x += width
        }
        // Room for the last tab's join foot so overflow never clips it.
        canvas.frame.size = CGSize(width: max(viewportWidth, x + ConnectedTabGeometry.baselineOutset),
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
        // Directly after the last tab; pinned to the viewport end on overflow.
        let tabsEnd = viewportX + min(viewportWidth, x - offset)
        newDocumentButton.frame = CGRect(
            x: tabsEnd, y: EditorTabLayout.contentCenterY - EditorTabLayout.actionHeight / 2,
            width: EditorTabLayout.newDocumentSlotWidth, height: EditorTabLayout.actionHeight
        )
        newDocumentButton.needsDisplay = true
        geometryDidChange()
    }

    override func draw(_ dirtyRect: NSRect) {
        EditorChrome.tabBarBackgroundColor.setFill()
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
        let originX = scrollView.frame.minX
        let background = EditorChrome.resolvedColor(EditorChrome.tabBarBackgroundColor, for: effectiveAppearance)
        let color = background.cgColor
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        leadingFade.frame = CGRect(x: originX, y: 0, width: EditorTabLayout.fadeWidth, height: bounds.height)
        trailingFade.frame = CGRect(x: originX + max(0, width - EditorTabLayout.fadeWidth), y: 0,
                                    width: EditorTabLayout.fadeWidth, height: bounds.height)
        leadingFade.colors = [color, background.withAlphaComponent(0).cgColor]
        trailingFade.colors = [background.withAlphaComponent(0).cgColor, color]
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

    override func hitTest(_ point: NSPoint) -> NSView? {
        // The toolbar's native chrome must own blank-space double-click/drag.
        // Only tab controls (including their rename field) consume events here.
        guard let hit = super.hitTest(point) else { return nil }
        if hit === newDocumentButton { return hit }
        guard tabViews.values.contains(where: { hit === $0 || hit.isDescendant(of: $0) }) else {
            return nil
        }
        return hit
    }

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
    override var isFlipped: Bool { true }
}

private final class EditorTabScrollView: NSScrollView {
    weak var strip: EditorTabStripView?
    override func scrollWheel(with event: NSEvent) { strip?.handleScroll(event) }
    override func swipe(with event: NSEvent) { strip?.handleSwipe(event) }
}
