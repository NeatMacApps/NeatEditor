import AppKit
import SwiftUI

/// AppKit owns the split, toolbar and tracking separator. Document tabs are
/// content of the native toolbar, never a second row beneath it.
struct WorkspaceSplitView: NSViewControllerRepresentable {
    let sidebar: AnyView
    let detail: AnyView
    let tabs: AnyView
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
    private let detailController: NSHostingController<AnyView>
    private let tabHost: NSHostingView<AnyView>
    private let workspaceToolbar = NSToolbar(identifier: "WorkspaceToolbar")
    private var tabWidth: NSLayoutConstraint?
    private var pinItem: NSToolbarItem?
    private weak var attachedWindow: NSWindow?
    private var isApplyingConfiguration = false

    init(configuration: WorkspaceSplitView) {
        self.configuration = configuration
        sidebarController = NSHostingController(rootView: configuration.sidebar)
        detailController = NSHostingController(rootView: configuration.detail)
        tabHost = NSHostingView(rootView: configuration.tabs)
        super.init(nibName: nil, bundle: nil)
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

        tabHost.sizingOptions = []
        tabHost.translatesAutoresizingMaskIntoConstraints = false
        let width = tabHost.widthAnchor.constraint(equalToConstant: 400)
        NSLayoutConstraint.activate([
            width,
            tabHost.heightAnchor.constraint(equalToConstant: EditorTabStripView.titleBarHeight),
        ])
        tabWidth = width

        workspaceToolbar.delegate = self
        workspaceToolbar.displayMode = .iconOnly
        workspaceToolbar.sizeMode = .small
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
        tabHost.rootView = configuration.tabs
        guard isViewLoaded else { return }
        isApplyingConfiguration = true
        splitViewItems.first?.isCollapsed = !configuration.isSidebarVisible
        splitViewItems.last?.minimumThickness = configuration.isSettingsSelected ? 500 : 300
        isApplyingConfiguration = false
        updatePinItem()
        updateTabWidth()
    }

    func detachToolbar() {
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
        window.toolbarStyle = .unifiedCompact
        window.toolbar = workspaceToolbar
    }

    private func updateTabWidth() {
        guard isViewLoaded, let tabWidth else { return }
        // Leave room for the two native trailing actions and toolbar margins.
        let width = max(80, detailController.view.bounds.width - 112)
        if abs(tabWidth.constant - width) > 0.5 {
            tabWidth.constant = width
        }
    }

    private func updatePinItem() {
        let label = String(localized: "Always on Top")
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
            item.visibilityPriority = .high
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

private extension WorkspaceSplitView {
    func isSidebarVisibleChanged(_ visible: Bool) {
        // Native split notifications can arrive during SwiftUI layout.
        Task { @MainActor in
            onSidebarVisibilityChange(visible)
        }
    }
}
