import AppKit
import SwiftUI

/// AppKit owns the split and the native compact top row. Document tabs live in
/// the editor column's titlebar band; the toolbar exists only for its height.
struct WorkspaceSplitView: NSViewControllerRepresentable {
    let sidebar: AnyView
    let detail: AnyView
    let tabs: [EditorTabDescriptor]
    let selectedTabID: UUID?
    let tabActions: EditorTabActions
    let isSidebarVisible: Bool
    let isSettingsSelected: Bool
    let isWindowPinned: Bool
    let onSidebarVisibilityChange: (Bool) -> Void
    let onTogglePin: () -> Void

    static let sidebarMinimumWidth: CGFloat = 200
    static let editorMinimumWidth: CGFloat = 240
    static let settingsMinimumWidth: CGFloat = 500

    static func minimumWindowWidth(sidebarVisible: Bool, settingsSelected: Bool) -> CGFloat {
        let detail = settingsSelected ? settingsMinimumWidth : editorMinimumWidth
        let sidebar = sidebarVisible ? sidebarMinimumWidth + 1 : 0
        return max(EditorTabLayout.minimumWindowEdge, detail + sidebar)
    }

    func makeNSViewController(context: Context) -> WorkspaceSplitViewController {
        WorkspaceSplitViewController(configuration: self)
    }

    func updateNSViewController(_ controller: WorkspaceSplitViewController, context: Context) {
        controller.update(configuration: self)
    }

    static func dismantleNSViewController(_ controller: WorkspaceSplitViewController, coordinator: ()) {
        controller.detachFromWindow()
    }
}

final class WorkspaceSplitViewController: NSSplitViewController, NSToolbarDelegate {
    private var configuration: WorkspaceSplitView
    private let sidebarController: NSHostingController<AnyView>
    private let detailController: WorkspaceEditorViewController
    /// Empty `.unifiedCompact` toolbar: the native 40 pt row with centred
    /// traffic lights. A bare titlebar is 32 pt and cannot be made taller.
    private let heightToolbar = NSToolbar(identifier: "WorkspaceCompactRow")
    private let sidebarAccessory = NSTitlebarAccessoryViewController()
    private let tabAccessory = NSTitlebarAccessoryViewController()
    private let sidebarButton = WorkspaceSplitViewController.titlebarButton(symbol: "sidebar.left")
    private var pinButton: NSButton { detailController.pinButton }
    private weak var attachedWindow: NSWindow?
    private var isApplyingConfiguration = false

    init(configuration: WorkspaceSplitView) {
        self.configuration = configuration
        sidebarController = NSHostingController(rootView: configuration.sidebar)
        detailController = WorkspaceEditorViewController(rootView: configuration.detail)
        super.init(nibName: nil, bundle: nil)
        detailController.strip.update(tabs: configuration.tabs, selectedTabID: configuration.selectedTabID,
                                      actions: configuration.tabActions)
        detailController.accessoryViews = [sidebarButton]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        splitView.isVertical = true
        splitView.dividerStyle = .thin

        let sidebar = NSSplitViewItem(sidebarWithViewController: sidebarController)
        sidebar.minimumThickness = WorkspaceSplitView.sidebarMinimumWidth
        sidebar.maximumThickness = 360
        sidebar.allowsFullHeightLayout = true
        sidebar.isCollapsed = !configuration.isSidebarVisible
        addSplitViewItem(sidebar)

        let detail = NSSplitViewItem(viewController: detailController)
        detail.minimumThickness = configuration.isSettingsSelected
            ? WorkspaceSplitView.settingsMinimumWidth : WorkspaceSplitView.editorMinimumWidth
        addSplitViewItem(detail)

        let sidebarLabel = String(localized: "Toggle Sidebar")
        sidebarButton.toolTip = sidebarLabel
        sidebarButton.setAccessibilityLabel(sidebarLabel)
        sidebarButton.target = self
        sidebarButton.action = #selector(toggleSidebar(_:))
        sidebarAccessory.view = sidebarButton
        sidebarAccessory.layoutAttribute = .leading
        tabAccessory.layoutAttribute = .trailing
        pinButton.target = self
        pinButton.action = #selector(togglePin(_:))
        heightToolbar.delegate = self
        heightToolbar.allowsUserCustomization = false
        heightToolbar.allowsDisplayModeCustomization = false
        updatePinButton()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        attachToWindow()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        attachToWindow()
    }

    override func splitViewDidResizeSubviews(_ notification: Notification) {
        super.splitViewDidResizeSubviews(notification)
        detailController.view.needsLayout = true
        guard !isApplyingConfiguration, let sidebar = splitViewItems.first else { return }
        let visible = !sidebar.isCollapsed
        guard visible != configuration.isSidebarVisible else { return }
        configuration.isSidebarVisibleChanged(visible)
    }

    override func toggleSidebar(_ sender: Any?) {
        super.toggleSidebar(sender)
        if let sidebar = splitViewItems.first {
            configuration.isSidebarVisibleChanged(!sidebar.isCollapsed)
        }
    }

    func update(configuration: WorkspaceSplitView) {
        self.configuration = configuration
        sidebarController.rootView = configuration.sidebar
        detailController.rootView = configuration.detail
        detailController.strip.update(tabs: configuration.tabs, selectedTabID: configuration.selectedTabID,
                                      actions: configuration.tabActions)
        guard isViewLoaded else { return }
        isApplyingConfiguration = true
        splitViewItems.first?.isCollapsed = !configuration.isSidebarVisible
        splitViewItems.last?.minimumThickness = configuration.isSettingsSelected
            ? WorkspaceSplitView.settingsMinimumWidth : WorkspaceSplitView.editorMinimumWidth
        isApplyingConfiguration = false
        updatePinButton()
    }

    func detachFromWindow() {
        detailController.strip.finishRename(commit: true)
        if let attachedWindow {
            NotificationCenter.default.removeObserver(self, name: NSWindow.didEnterFullScreenNotification,
                                                      object: attachedWindow)
            NotificationCenter.default.removeObserver(self, name: NSWindow.didExitFullScreenNotification,
                                                      object: attachedWindow)
        }
        detailController.moveTabBand(to: nil)
        tabAccessory.removeFromParent()
        sidebarAccessory.removeFromParent()
        if attachedWindow?.toolbar === heightToolbar {
            attachedWindow?.toolbar = nil
        }
        attachedWindow = nil
    }

    private func attachToWindow() {
        guard let window = view.window, attachedWindow !== window else { return }
        attachedWindow = window
        window.titleVisibility = .hidden
        // Native chrome must receive blank clicks, not the full-size content hosts.
        window.titlebarAppearsTransparent = false
        window.backgroundColor = EditorChrome.tabBarBackgroundColor
        // The connected tab outline owns this boundary; a native full-width
        // separator would draw a second line through the selected tab's join.
        window.titlebarSeparatorStyle = .none
        // Titlebar accessories and toolbars exist only on titled windows.
        guard window.styleMask.contains(.titled) else { return }
        window.toolbar = heightToolbar
        window.toolbarStyle = .unifiedCompact
        if !window.titlebarAccessoryViewControllers.contains(sidebarAccessory) {
            window.addTitlebarAccessoryViewController(sidebarAccessory)
        }
        if !window.styleMask.contains(.fullScreen) {
            detailController.moveTabBand(to: tabAccessory)
            window.addTitlebarAccessoryViewController(tabAccessory)
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(didEnterFullScreen(_:)),
            name: NSWindow.didEnterFullScreenNotification, object: window
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(didExitFullScreen(_:)),
            name: NSWindow.didExitFullScreenNotification, object: window
        )
        detailController.view.needsLayout = true
    }

    @objc private func didEnterFullScreen(_ notification: Notification) {
        detailController.moveTabBand(to: nil)
        tabAccessory.removeFromParent()
    }

    @objc private func didExitFullScreen(_ notification: Notification) {
        guard let window = attachedWindow else { return }
        detailController.moveTabBand(to: tabAccessory)
        window.addTitlebarAccessoryViewController(tabAccessory)
    }

    private func updatePinButton() {
        let pinned = configuration.isWindowPinned
        pinButton.image = NSImage(
            systemSymbolName: "square.3.layers.3d.top.filled",
            accessibilityDescription: String(localized: "Always on Top")
        )
        pinButton.contentTintColor = pinned ? .controlAccentColor : .secondaryLabelColor
        pinButton.toolTip = pinned
            ? String(localized: "Disable Always on Top")
            : String(localized: "Enable Always on Top")
        pinButton.setAccessibilityLabel(String(localized: "Always on Top"))
        pinButton.setAccessibilityValue(pinned ? 1 : 0)
    }

    @objc private func togglePin(_ sender: Any?) {
        configuration.onTogglePin()
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [] }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [] }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        // AppKit requires the factory even when the toolbar has no items.
        nil
    }

    fileprivate static func titlebarButton(symbol: String) -> NSButton {
        let button = NSButton()
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.contentTintColor = .secondaryLabelColor
        button.focusRingType = .none
        // Keeps the image's symbol configuration across later image swaps.
        button.symbolConfiguration = .init(pointSize: EditorTabLayout.actionSymbolSize, weight: .regular)
        // Frame-sized: titlebar accessories are placed by AppKit, and an
        // Auto Layout width here displaced them onto the traffic lights.
        button.frame.size = CGSize(width: EditorTabLayout.newDocumentSlotWidth, height: EditorTabLayout.stripHeight)
        return button
    }
}

/// Native chrome owns the tab band; content owns the matching top rule.
/// Full screen rehomes the same band above the host without SwiftUI-owned layout.
private final class WorkspaceEditorViewController: NSViewController {
    private let host: NSHostingController<AnyView>
    let topRule = EditorTabTopRuleView()
    private let tabBand = WorkspaceTabBandView()
    var strip: EditorTabStripView { tabBand.strip }
    var pinButton: NSButton { tabBand.pinButton }
    /// Titlebar accessory views whose frames the tab band must not cover.
    var accessoryViews: [NSView] = [] {
        didSet {
            for view in accessoryViews {
                view.postsFrameChangedNotifications = true
                NotificationCenter.default.addObserver(
                    self, selector: #selector(accessoryFrameChanged(_:)),
                    name: NSView.frameDidChangeNotification, object: view
                )
            }
        }
    }

    var rootView: AnyView {
        get { host.rootView }
        set { host.rootView = newValue }
    }

    init(rootView: AnyView) {
        host = NSHostingController(rootView: rootView)
        super.init(nibName: nil, bundle: nil)
        strip.topRule = topRule
        topRule.strip = strip
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        view = NSView()
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        topRule.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        view.addSubview(topRule, positioned: .above, relativeTo: host.view)
        view.addSubview(tabBand, positioned: .above, relativeTo: topRule)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            topRule.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topRule.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topRule.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            topRule.heightAnchor.constraint(equalToConstant: 1),
        ])
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        // Full screen hides the titlebar and its safe area; reserve the band
        // ourselves so tabs never cover the editor's first line.
        let systemBand = view.safeAreaInsets.top - view.additionalSafeAreaInsets.top
        let reserved = max(0, EditorTabLayout.stripHeight - systemBand)
        if view.additionalSafeAreaInsets.top != reserved {
            view.additionalSafeAreaInsets.top = reserved
        }
        let band = systemBand + reserved
        let insets = accessoryInsets()
        if tabBand.superview === view {
            tabBand.frame = CGRect(x: 0, y: view.bounds.height - band, width: view.bounds.width, height: band)
            tabBand.accessoryInsets = insets
        } else {
            // Do not overlap the leading native accessory when the sidebar is
            // collapsed: its container would consume the sidebar button's hits.
            let width = max(0, view.bounds.width - insets.left)
            if tabBand.frame.width != width {
                tabBand.setFrameSize(CGSize(width: width, height: tabBand.frame.height))
            }
            tabBand.accessoryInsets = NSEdgeInsets()
        }
        tabBand.needsLayout = true
        tabBand.layoutSubtreeIfNeeded()
    }

    func moveTabBand(to accessory: NSTitlebarAccessoryViewController?) {
        tabBand.removeFromSuperview()
        if let accessory {
            tabBand.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: EditorTabLayout.stripHeight)
            accessory.view = tabBand
        } else {
            view.addSubview(tabBand, positioned: .above, relativeTo: topRule)
        }
        view.needsLayout = true
    }

    /// Accessory frames are read at layout time in window coordinates.
    private func accessoryInsets() -> NSEdgeInsets {
        guard view.window != nil else { return NSEdgeInsets() }
        let column = view.convert(view.bounds, to: nil)
        var insets = NSEdgeInsets()
        for accessory in accessoryViews where accessory.window === view.window && !accessory.isHiddenOrHasHiddenAncestor {
            let frame = accessory.convert(accessory.bounds, to: nil)
            guard frame.maxX > column.minX, frame.minX < column.maxX else { continue }
            if frame.midX < column.midX {
                insets.left = max(insets.left, frame.maxX - column.minX)
            } else {
                insets.right = max(insets.right, column.maxX - frame.minX)
            }
        }
        return insets
    }

    @objc private func accessoryFrameChanged(_ notification: Notification) {
        view.needsLayout = true
    }
}

/// Product content inside native chrome. Blank hits stay in AppKit's titlebar.
private final class WorkspaceTabBandView: NSView {
    let strip = EditorTabStripView()
    let pinButton = WorkspaceSplitViewController.titlebarButton(symbol: "square.3.layers.3d.top.filled")
    var accessoryInsets = NSEdgeInsets()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(strip)
        addSubview(pinButton)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        strip.frame = bounds
        let slot = EditorTabLayout.newDocumentSlotWidth
        let trailingSlot = slot + EditorTabLayout.trailingMargin
        pinButton.frame = CGRect(x: bounds.width - trailingSlot,
                                 y: bounds.height - EditorTabLayout.contentCenterY - EditorTabLayout.actionHeight / 2,
                                 width: slot, height: EditorTabLayout.actionHeight)
        var insets = accessoryInsets
        insets.right = max(insets.right, trailingSlot)
        strip.contentInsets = insets
        strip.layoutSubtreeIfNeeded()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }
}

private extension WorkspaceSplitView {
    func isSidebarVisibleChanged(_ visible: Bool) {
        // Native split notifications can arrive during SwiftUI layout.
        Task { @MainActor in
            onSidebarVisibilityChange(visible)
        }
    }
}
