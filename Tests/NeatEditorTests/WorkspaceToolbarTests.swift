import AppKit
import SwiftUI
import Testing

@testable import NeatEditor

@MainActor
struct WorkspaceToolbarTests {
    private func makeController() -> WorkspaceSplitViewController {
        WorkspaceSplitViewController(configuration: WorkspaceSplitView(
            sidebar: AnyView(EmptyView()),
            detail: AnyView(EmptyView()),
            tabs: [],
            selectedTabID: nil,
            tabActions: EditorTabActions(),
            isSidebarVisible: true,
            isSettingsSelected: false,
            isWindowPinned: false,
            onSidebarVisibilityChange: { _ in },
            onNewDocument: {},
            onTogglePin: {}
        ))
    }

    @Test("the built-in Sidebar toolbar button keeps native behavior without a focus ring")
    func nativeSidebarHasNoFocusRing() throws {
        let controller = makeController()
        let toolbar = NSToolbar(identifier: "WorkspaceToolbarFocusTest")
        toolbar.delegate = controller
        toolbar.insertItem(withItemIdentifier: .toggleSidebar, at: 0)

        let item = try #require(toolbar.items.first)
        let button = try #require(item.view as? NSButton)
        #expect(item.itemIdentifier == .toggleSidebar)
        #expect(button.focusRingType == .none)
        #expect(button.action == #selector(NSSplitViewController.toggleSidebar(_:)))
    }

    @Test("focus-ring policy applies to every public toolbar item view")
    func itemViewsHaveNoFocusRing() {
        let controller = makeController()
        for identifier in ["WorkspaceNewDocument", "WorkspacePin"] {
            let item = NSToolbarItem(itemIdentifier: NSToolbarItem.Identifier(identifier))
            let button = NSButton(title: identifier, target: nil, action: nil)
            button.focusRingType = .exterior
            item.view = button
            controller.toolbarWillAddItem(Notification(
                name: NSToolbar.willAddItemNotification,
                object: nil,
                userInfo: [NSToolbarUserInfoKey.itemKey: item]
            ))
            #expect(button.focusRingType == .none)
        }
    }

    @Test("toolbar notifications without an item are harmless")
    func missingNotificationItemIsIgnored() {
        makeController().toolbarWillAddItem(Notification(
            name: NSToolbar.willAddItemNotification,
            object: nil
        ))
    }
}
