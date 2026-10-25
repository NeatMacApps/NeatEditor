import AppKit
import SwiftUI
import Testing

@testable import NeatEditor

/// One native compact row (empty `.unifiedCompact` toolbar) holds the traffic
/// lights, the sidebar accessory and the editor column's tab band with + and pin.
@MainActor
struct WorkspaceTitlebarTests {
    private func makeWindow(sidebarVisible: Bool = true, pinned: Bool = false,
                            styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable,
                                                             .resizable, .fullSizeContentView]) -> NSWindow {
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
                              styleMask: styleMask,
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        window.setContentSize(CGSize(width: 900, height: 500))
        window.layoutIfNeeded()
        return window
    }

    private func sidebarButton(_ window: NSWindow) throws -> NSButton {
        let accessory = try #require(window.titlebarAccessoryViewControllers.first { $0.layoutAttribute == .leading })
        return try #require(accessory.view as? NSButton)
    }

    private func pinButton(_ window: NSWindow) throws -> NSButton {
        let strip = try #require(window.contentView.flatMap(findStrip))
        let siblings = strip.superview?.subviews.compactMap { $0 as? NSButton } ?? []
        return try #require(siblings.first { $0.accessibilityLabel() == String(localized: "Always on Top") })
    }

    @Test("an empty compact toolbar gives the native 40 pt row with centred traffic lights")
    func compactRow() throws {
        let window = makeWindow()
        defer { window.close() }
        let toolbar = try #require(window.toolbar)
        #expect(toolbar.items.isEmpty)
        #expect(window.toolbarStyle == .unifiedCompact)
        #expect(!toolbar.allowsUserCustomization && !toolbar.allowsDisplayModeCustomization)
        #expect(window.frame.height - window.contentLayoutRect.height == EditorTabLayout.stripHeight)
        let close = try #require(window.standardWindowButton(.closeButton))
        let closeFrame = close.convert(close.bounds, to: nil)
        #expect(abs(window.frame.height - closeFrame.midY - EditorTabLayout.stripHeight / 2) < 0.5)
    }

    @Test("sidebar is a native accessory; pin is a peer of + without focus rings")
    func titlebarControls() throws {
        let window = makeWindow()
        defer { window.close() }
        #expect(window.titlebarAccessoryViewControllers.count == 1)
        let sidebar = try sidebarButton(window)
        let pin = try pinButton(window)
        #expect(sidebar.action == #selector(NSSplitViewController.toggleSidebar(_:)))
        #expect(sidebar.focusRingType == .none && pin.focusRingType == .none)
        #expect(!sidebar.isBordered && !pin.isBordered)
        #expect(pin.symbolConfiguration == NSImage.SymbolConfiguration(
            pointSize: EditorTabLayout.titleFontSize, weight: .regular))
        let strip = try #require(window.contentView.flatMap(findStrip))
        let plus = try #require(strip.subviews.compactMap { $0 as? NSButton }.first)
        let plusFrame = plus.convert(plus.bounds, to: nil)
        let pinFrame = pin.convert(pin.bounds, to: nil)
        #expect(abs(plusFrame.midY - pinFrame.midY) < 0.5)
        #expect(plusFrame.height == pinFrame.height)
    }

    @Test("pin button reflects the pinned state", arguments: [false, true])
    func pinState(pinned: Bool) throws {
        let window = makeWindow(pinned: pinned)
        defer { window.close() }
        let pin = try pinButton(window)
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
        let pin = try pinButton(window)
        let stripFrame = strip.convert(strip.bounds, to: nil)
        let pinFrame = pin.convert(pin.bounds, to: nil)
        #expect(abs(strip.contentInsets.right - (stripFrame.maxX - pinFrame.minX)) < 0.5)
        #expect(stripFrame.maxX - pinFrame.maxX == EditorTabLayout.trailingMargin)
        let sidebar = try sidebarButton(window)
        let sidebarFrame = sidebar.convert(sidebar.bounds, to: nil)
        if sidebarFrame.maxX > stripFrame.minX {
            #expect(abs(strip.contentInsets.left - (sidebarFrame.maxX - stripFrame.minX)) < 0.5)
        } else {
            #expect(strip.contentInsets.left == 0)
        }
    }

    @Test("without a titlebar safe area (full screen) the band is still reserved above the editor")
    func bandReservedWithoutTitlebar() throws {
        let window = makeWindow(styleMask: [.borderless, .resizable])
        defer { window.close() }
        window.contentView?.layoutSubtreeIfNeeded()
        let strip = try #require(window.contentView.flatMap(findStrip))
        let column = try #require(strip.superview)
        #expect(strip.frame.height == EditorTabLayout.stripHeight)
        #expect(strip.frame.maxY == column.bounds.maxY)
        #expect(column.safeAreaInsets.top == EditorTabLayout.stripHeight)
        let rule = try #require(strip.topRule)
        #expect(abs(rule.frame.maxY - strip.frame.minY) < 0.5)
    }

    private func findStrip(in view: NSView) -> EditorTabStripView? {
        if let strip = view as? EditorTabStripView { return strip }
        for subview in view.subviews {
            if let strip = findStrip(in: subview) { return strip }
        }
        return nil
    }
}
