import AppKit
import SwiftUI
import Testing

@testable import NeatEditor

/// The workspace window has no toolbar: one native 32 pt titlebar row holds the
/// traffic lights, accessory buttons and the editor column's tab band.
@MainActor
struct WorkspaceTitlebarTests {
    private func makeWindow(sidebarVisible: Bool = true, pinned: Bool = false) -> NSWindow {
        let controller = WorkspaceSplitViewController(configuration: WorkspaceSplitView(
            sidebar: AnyView(EmptyView()),
            detail: AnyView(EmptyView()),
            tabs: [EditorTabDescriptor(id: UUID(), title: "One.md")],
            selectedTabID: nil,
            tabActions: EditorTabActions(),
            isSidebarVisible: sidebarVisible,
            isSettingsSelected: false,
            isWindowPinned: pinned,
            onSidebarVisibilityChange: { _ in },
            onTogglePin: {}
        ))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 900, height: 500),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        window.setContentSize(CGSize(width: 900, height: 500))
        window.layoutIfNeeded()
        return window
    }

    private func button(_ window: NSWindow, _ attribute: NSLayoutConstraint.Attribute) throws -> NSButton {
        let accessory = try #require(window.titlebarAccessoryViewControllers.first { $0.layoutAttribute == attribute })
        return try #require(accessory.view as? NSButton)
    }

    @Test("no toolbar; sidebar and pin are native accessory buttons without focus rings")
    func titlebarAccessories() throws {
        let window = makeWindow()
        defer { window.close() }
        #expect(window.toolbar == nil)
        #expect(window.titlebarAccessoryViewControllers.count == 2)
        let sidebar = try button(window, .leading)
        let pin = try button(window, .trailing)
        #expect(sidebar.action == #selector(NSSplitViewController.toggleSidebar(_:)))
        #expect(sidebar.focusRingType == .none)
        #expect(pin.focusRingType == .none)
        #expect(!sidebar.isBordered && !pin.isBordered)
    }

    @Test("pin button reflects the pinned state", arguments: [false, true])
    func pinState(pinned: Bool) throws {
        let window = makeWindow(pinned: pinned)
        defer { window.close() }
        let pin = try button(window, .trailing)
        #expect(pin.contentTintColor == (pinned ? .controlAccentColor : .secondaryLabelColor))
        #expect(pin.toolTip == (pinned ? String(localized: "Disable Always on Top")
                                       : String(localized: "Enable Always on Top")))
    }

    @Test("the tab band spans the titlebar height and avoids accessory frames", arguments: [true, false])
    func tabBandAvoidsAccessories(sidebarVisible: Bool) throws {
        let window = makeWindow(sidebarVisible: sidebarVisible)
        defer { window.close() }
        window.contentView?.layoutSubtreeIfNeeded()
        let strip = try #require(window.contentView.flatMap(findStrip))
        let titlebarHeight = window.frame.height - window.contentLayoutRect.height
        #expect(strip.frame.height == titlebarHeight)
        let pin = try button(window, .trailing)
        let stripFrame = strip.convert(strip.bounds, to: nil)
        let pinFrame = pin.convert(pin.bounds, to: nil)
        #expect(abs(strip.contentInsets.right - (stripFrame.maxX - pinFrame.minX)) < 0.5)
        let sidebar = try button(window, .leading)
        let sidebarFrame = sidebar.convert(sidebar.bounds, to: nil)
        if sidebarFrame.maxX > stripFrame.minX {
            #expect(abs(strip.contentInsets.left - (sidebarFrame.maxX - stripFrame.minX)) < 0.5)
        } else {
            #expect(strip.contentInsets.left == 0)
        }
    }

    private func findStrip(in view: NSView) -> EditorTabStripView? {
        if let strip = view as? EditorTabStripView { return strip }
        for subview in view.subviews {
            if let strip = findStrip(in: subview) { return strip }
        }
        return nil
    }
}
