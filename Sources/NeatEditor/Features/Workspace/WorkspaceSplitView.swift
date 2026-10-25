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
        sidebar.minimumThickness = 200
        sidebar.maximumThickness = 360
        sidebar.allowsFullHeightLayout = true
        sidebar.isCollapsed = !configuration.isSidebarVisible
        addSplitViewItem(sidebar)

        let detail = NSSplitViewItem(viewController: detailController)
        detail.minimumThickness = configuration.isSettingsSelected ? 500 : 300
        addSplitViewItem(detail)

        let sidebarLabel = String(localized: "Toggle Sidebar")
        sidebarButton.toolTip = sidebarLabel
        sidebarButton.setAccessibilityLabel(sidebarLabel)
        sidebarButton.target = self
        sidebarButton.action = #selector(toggleSidebar(_:))
        sidebarAccessory.view = sidebarButton
        sidebarAccessory.layoutAttribute = .leading
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
        splitViewItems.last?.minimumThickness = configuration.isSettingsSelected ? 500 : 300
        isApplyingConfiguration = false
        updatePinButton()
    }

    func detachFromWindow() {
        detailController.strip.finishRename(commit: true)
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
        window.titlebarAppearsTransparent = true
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
        detailController.view.needsLayout = true
    }

    private func updatePinButton() {
        let pinned = configuration.isWindowPinned
        pinButton.image = NSImage(
            systemSymbolName: pinned ? "pin.fill" : "pin",
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

    fileprivate static func titlebarButton(symbol: String, pointSize: CGFloat = 15) -> NSButton {
        let button = NSButton()
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.contentTintColor = .secondaryLabelColor
        button.focusRingType = .none
        // Keeps the image's symbol configuration across later image swaps.
        button.symbolConfiguration = .init(pointSize: pointSize, weight: .regular)
        // Frame-sized: titlebar accessories are placed by AppKit, and an
        // Auto Layout width here displaced them onto the traffic lights.
        button.frame.size = CGSize(width: 40, height: EditorTabLayout.stripHeight)
        return button
    }
}

/// The tab band and top rule are native siblings above the hosting view, not
/// subviews whose ordering or layout is owned by SwiftUI's hosting implementation.
private final class WorkspaceEditorViewController: NSViewController {
    private let host: NSHostingController<AnyView>
    let topRule = EditorTabTopRuleView()
    let strip = EditorTabStripView()
    /// Peer of the strip's New Document button: same size, colour and centre line.
    let pinButton = WorkspaceSplitViewController.titlebarButton(
        symbol: "pin", pointSize: EditorTabLayout.titleFontSize
    )
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
        view.addSubview(strip, positioned: .above, relativeTo: topRule)
        view.addSubview(pinButton, positioned: .above, relativeTo: strip)
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
        strip.frame = CGRect(x: 0, y: view.bounds.height - band, width: view.bounds.width, height: band)
        let slot = EditorTabLayout.newDocumentSlotWidth
        let trailingSlot = slot + EditorTabLayout.trailingMargin
        // Bottom-aligned like the tabs, so its centre matches the titles and +.
        pinButton.frame = CGRect(x: view.bounds.width - trailingSlot, y: strip.frame.minY,
                                 width: slot, height: EditorTabLayout.tabHeight)
        var insets = accessoryInsets()
        insets.right = max(insets.right, trailingSlot)
        strip.contentInsets = insets
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

private extension WorkspaceSplitView {
    func isSidebarVisibleChanged(_ visible: Bool) {
        // Native split notifications can arrive during SwiftUI layout.
        Task { @MainActor in
            onSidebarVisibilityChange(visible)
        }
    }
}
