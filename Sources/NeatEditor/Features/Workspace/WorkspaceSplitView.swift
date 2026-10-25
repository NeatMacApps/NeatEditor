import AppKit
import SwiftUI

/// AppKit owns the split, toolbar and tracking separator. Document tabs are
/// content of the native toolbar, never a second row beneath it.
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
    let onNewDocument: () -> Void
    let onTogglePin: () -> Void

    func makeNSViewController(context: Context) -> WorkspaceSplitViewController {
        WorkspaceSplitViewController(configuration: self)
    }

    func updateNSViewController(_ controller: WorkspaceSplitViewController, context: Context) {
        controller.update(configuration: self)
    }

    static func dismantleNSViewController(_ controller: WorkspaceSplitViewController, coordinator: ()) {
        controller.detachToolbar()
    }
}

final class WorkspaceSplitViewController: NSSplitViewController, NSToolbarDelegate {
    private enum Item {
        static let tabs = NSToolbarItem.Identifier("WorkspaceDocumentTabs")
        static let newDocument = NSToolbarItem.Identifier("WorkspaceNewDocument")
        static let pin = NSToolbarItem.Identifier("WorkspacePin")
    }

    private var configuration: WorkspaceSplitView
    private let sidebarController: NSHostingController<AnyView>
    private let detailController: WorkspaceEditorViewController
    private let tabHost = EditorTabStripView()
    private var topRule: EditorTabTopRuleView { detailController.topRule }
    private let workspaceToolbar = NSToolbar(identifier: "WorkspaceToolbar")
    private var tabWidth: NSLayoutConstraint?
    private var pinItem: NSToolbarItem?
    private weak var attachedWindow: NSWindow?
    private var isApplyingConfiguration = false

    init(configuration: WorkspaceSplitView) {
        self.configuration = configuration
        sidebarController = NSHostingController(rootView: configuration.sidebar)
        detailController = WorkspaceEditorViewController(rootView: configuration.detail)
        super.init(nibName: nil, bundle: nil)
        tabHost.update(tabs: configuration.tabs, selectedTabID: configuration.selectedTabID,
                       actions: configuration.tabActions)
        tabHost.topRule = topRule
        topRule.strip = tabHost
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

        tabHost.translatesAutoresizingMaskIntoConstraints = false
        let width = tabHost.widthAnchor.constraint(lessThanOrEqualToConstant: 400)
        NSLayoutConstraint.activate([
            tabHost.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
            width,
            tabHost.heightAnchor.constraint(equalToConstant: EditorTabStripView.titleBarHeight),
        ])
        tabWidth = width

        workspaceToolbar.delegate = self
        workspaceToolbar.displayMode = .iconOnly
        workspaceToolbar.sizeMode = .regular
        workspaceToolbar.allowsUserCustomization = false
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        attachToolbar()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        attachToolbar()
        updateTabWidth()
    }

    override func splitViewDidResizeSubviews(_ notification: Notification) {
        super.splitViewDidResizeSubviews(notification)
        updateTabWidth()
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
        tabHost.update(tabs: configuration.tabs, selectedTabID: configuration.selectedTabID,
                       actions: configuration.tabActions)
        guard isViewLoaded else { return }
        isApplyingConfiguration = true
        splitViewItems.first?.isCollapsed = !configuration.isSidebarVisible
        splitViewItems.last?.minimumThickness = configuration.isSettingsSelected ? 500 : 300
        isApplyingConfiguration = false
        updatePinItem()
        updateTabWidth()
    }

    func detachToolbar() {
        tabHost.finishRename(commit: true)
        if attachedWindow?.toolbar === workspaceToolbar {
            attachedWindow?.toolbar = nil
        }
        attachedWindow = nil
    }

    private func attachToolbar() {
        guard let window = view.window else { return }
        attachedWindow = window
        guard window.toolbar !== workspaceToolbar else { return }
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        // The connected tab outline owns this boundary; a native full-width
        // separator would draw a second line through the selected tab's join.
        window.titlebarSeparatorStyle = .none
        window.toolbar = workspaceToolbar
    }

    private func updateTabWidth() {
        guard isViewLoaded, let tabWidth else { return }
        // This is a maximum, not a required width. AppKit must also reserve
        // native traffic lights and sidebar controls when the sidebar is hidden.
        // A required detail-derived width pushed the entire tab item into overflow.
        let width = max(80, detailController.view.bounds.width - 112)
        if abs(tabWidth.constant - width) > 0.5 {
            tabWidth.constant = width
        }
    }

    private func updatePinItem() {
        let label = String(localized: "Always on Top")
        pinItem?.style = configuration.isWindowPinned ? .prominent : .plain
        pinItem?.image = NSImage(
            systemSymbolName: configuration.isWindowPinned ? "pin.fill" : "pin",
            accessibilityDescription: label
        )
        pinItem?.toolTip = configuration.isWindowPinned
            ? String(localized: "Disable Always on Top")
            : String(localized: "Enable Always on Top")
    }

    @objc private func newDocument(_ sender: Any?) {
        configuration.onNewDocument()
    }

    @objc private func togglePin(_ sender: Any?) {
        configuration.onTogglePin()
    }

    func toolbarWillAddItem(_ notification: Notification) {
        guard let item = notification.userInfo?[NSToolbarUserInfoKey.itemKey] as? NSToolbarItem else {
            return
        }
        // Configure the public item view, including AppKit's built-in Sidebar
        // button, without replacing controls or traversing private chrome.
        item.view?.focusRingType = .none
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .sidebarTrackingSeparator, Item.tabs, Item.newDocument, Item.pin]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier identifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch identifier {
        case .sidebarTrackingSeparator:
            return NSTrackingSeparatorToolbarItem(
                identifier: identifier,
                splitView: splitView,
                dividerIndex: 0
            )
        case Item.tabs:
            let item = NSToolbarItem(itemIdentifier: identifier)
            item.label = String(localized: "Documents")
            item.view = tabHost
            item.isBordered = false
            item.visibilityPriority = .user
            return item
        case Item.newDocument:
            let item = NSToolbarItem(itemIdentifier: identifier)
            item.label = String(localized: "New Document")
            item.toolTip = item.label
            item.image = NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: item.label)
            item.target = self
            item.action = #selector(newDocument(_:))
            return item
        case Item.pin:
            let item = NSToolbarItem(itemIdentifier: identifier)
            item.label = String(localized: "Always on Top")
            item.target = self
            item.action = #selector(togglePin(_:))
            pinItem = item
            updatePinItem()
            return item
        default:
            return nil
        }
    }
}

/// The rule is a native sibling above the hosting view, not a subview whose
/// ordering or layout is owned by SwiftUI's hosting implementation.
private final class WorkspaceEditorViewController: NSViewController {
    private let host: NSHostingController<AnyView>
    let topRule = EditorTabTopRuleView()

    var rootView: AnyView {
        get { host.rootView }
        set { host.rootView = newValue }
    }

    init(rootView: AnyView) {
        host = NSHostingController(rootView: rootView)
        super.init(nibName: nil, bundle: nil)
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
}

private extension WorkspaceSplitView {
    func isSidebarVisibleChanged(_ visible: Bool) {
        // Native split notifications can arrive during SwiftUI layout.
        Task { @MainActor in
            onSidebarVisibilityChange(visible)
        }
    }
}
