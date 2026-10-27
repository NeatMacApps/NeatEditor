import AppKit
import SwiftUI
import Testing

@testable import NeatEditor

/// One native compact row (empty `.unifiedCompact` toolbar) holds the traffic
/// lights, the sidebar accessory and the editor column's tab band with + and pin.
@MainActor
struct WorkspaceTitlebarTests {
    private func makeWindow(sidebarVisible: Bool = true, pinned: Bool = false,
                            width: CGFloat = 900, settingsSelected: Bool = false,
                            titles: [String] = ["One.md"], hosted: Bool = false,
                            styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable,
                                                             .resizable, .fullSizeContentView]) -> NSWindow {
        let tabs = titles.map { EditorTabDescriptor(id: UUID(), title: $0) }
        let configuration = WorkspaceSplitView(
            sidebar: AnyView(EmptyView()),
            detail: AnyView(EmptyView()),
            tabs: tabs,
            selectedTabID: tabs.first?.id,
            tabActions: EditorTabActions(),
            isSidebarVisible: sidebarVisible,
            isSettingsSelected: settingsSelected,
            isWindowPinned: pinned,
            onSidebarVisibilityChange: { _ in },
            onTogglePin: {}
        )
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: width, height: 500),
                              styleMask: styleMask,
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        if hosted {
            window.contentViewController = NSHostingController(rootView: configuration
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(.container, edges: .top))
        } else {
            window.contentViewController = WorkspaceSplitViewController(configuration: configuration)
        }
        window.setContentSize(CGSize(width: width, height: 500))
        window.layoutIfNeeded()
        return window
    }

    private func sidebarButton(_ window: NSWindow) throws -> NSButton {
        let accessory = try #require(window.titlebarAccessoryViewControllers.first { $0.layoutAttribute == .leading })
        return try #require(accessory.view as? NSButton)
    }

    private func pinButton(_ window: NSWindow) throws -> NSButton {
        let strip = try #require(findStrip(in: window))
        let siblings = strip.superview?.subviews.compactMap { $0 as? NSButton } ?? []
        return try #require(siblings.first { $0.accessibilityLabel() == String(localized: "Always on Top") })
    }

    @Test("an empty compact toolbar gives the native 40 pt row with centred traffic lights")
    func compactRow() throws {
        let window = makeWindow()
        defer { window.close() }
        let toolbar = try #require(window.toolbar)
        let delegate = try #require(toolbar.delegate)
        #expect(delegate.responds(to: #selector(NSToolbarDelegate.toolbar(_:itemForItemIdentifier:willBeInsertedIntoToolbar:))))
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
        #expect(window.titlebarAccessoryViewControllers.count == 2)
        let sidebar = try sidebarButton(window)
        let pin = try pinButton(window)
        #expect(sidebar.action == #selector(NSSplitViewController.toggleSidebar(_:)))
        #expect(sidebar.focusRingType == .none && pin.focusRingType == .none)
        #expect(!sidebar.isBordered && !pin.isBordered)
        #expect(pin.symbolConfiguration == NSImage.SymbolConfiguration(
            pointSize: EditorTabLayout.actionSymbolSize, weight: .regular))
        let strip = try #require(findStrip(in: window))
        let plus = try #require(strip.subviews.compactMap { $0 as? NSButton }.first)
        let plusFrame = plus.convert(plus.bounds, to: nil)
        let pinFrame = pin.convert(pin.bounds, to: nil)
        #expect(abs(plusFrame.midY - pinFrame.midY) < 0.5)
        #expect(plusFrame.height == pinFrame.height)
        #expect(sidebar.symbolConfiguration == pin.symbolConfiguration)
        #expect(plus.symbolConfiguration == pin.symbolConfiguration)
        let close = try #require(window.standardWindowButton(.closeButton))
        let axis = close.convert(close.bounds, to: nil).midY
        for control in [sidebar, plus, pin] {
            #expect(abs(control.convert(control.bounds, to: nil).midY - axis) < 0.5)
        }
        for tab in strip.tabViews.values {
            #expect(abs(tab.titleField.convert(tab.titleField.bounds, to: nil).midY - axis) < 0.5)
        }
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
        let strip = try #require(findStrip(in: window))
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

    @Test("minimum windows contain the split and all actions with sidebar open or closed",
          arguments: [true, false], [CGFloat(470), 600, 1100])
    func narrowWindowContainment(sidebarVisible: Bool, width: CGFloat) throws {
        for titles in [[], ["短.txt", "我的职业技术规划以及未来五年的详细规划.txt", "Readme.md"]] {
            let window = makeWindow(sidebarVisible: sidebarVisible, width: width, titles: titles)
            defer { window.close() }
            window.contentView?.layoutSubtreeIfNeeded()
            let content = try #require(window.contentView)
            let visible = content.convert(content.bounds, to: nil)
            let strip = try #require(findStrip(in: window))
            let pin = try pinButton(window)
            let plus = try #require(strip.subviews.compactMap { $0 as? NSButton }.first)
            let column = try #require(strip.superview)
            let columnFrame = column.convert(column.bounds, to: nil)
            #expect(columnFrame.minX >= visible.minX - 0.5)
            #expect(columnFrame.maxX <= visible.maxX + 0.5)
            for action in [plus, pin] {
                let frame = action.convert(action.bounds, to: nil)
                #expect(frame.minX >= columnFrame.minX)
                #expect(frame.maxX <= visible.maxX - EditorTabLayout.trailingMargin + 0.5)
            }
            let plusFrame = plus.convert(plus.bounds, to: nil)
            let pinFrame = pin.convert(pin.bounds, to: nil)
            #expect(plusFrame.maxX <= pinFrame.minX + 0.5)
            #expect(abs(visible.maxX - pinFrame.maxX - EditorTabLayout.trailingMargin) < 0.5)
        }
    }

    @Test("Settings minimum includes the visible sidebar instead of overflowing the window",
          arguments: [true, false])
    func settingsMinimum(sidebarVisible: Bool) throws {
        let width = WorkspaceSplitView.minimumWindowWidth(sidebarVisible: sidebarVisible, settingsSelected: true)
        #expect(width == (sidebarVisible ? 701 : 500))
        #expect(WorkspaceSplitView.minimumWindowWidth(sidebarVisible: sidebarVisible, settingsSelected: false) == 470)
        let window = makeWindow(sidebarVisible: sidebarVisible, width: width, settingsSelected: true)
        defer { window.close() }
        window.contentView?.layoutSubtreeIfNeeded()
        let strip = try #require(findStrip(in: window))
        let column = try #require(strip.topRule?.superview)
        #expect(column.bounds.width >= WorkspaceSplitView.settingsMinimumWidth)
        let content = try #require(window.contentView)
        let pin = try pinButton(window)
        #expect(pin.convert(pin.bounds, to: nil).maxX <= content.convert(content.bounds, to: nil).maxX)
    }

    @Test("without a titlebar safe area (full screen) the band is still reserved above the editor")
    func bandReservedWithoutTitlebar() throws {
        let window = makeWindow(styleMask: [.borderless, .resizable])
        defer { window.close() }
        window.contentView?.layoutSubtreeIfNeeded()
        let strip = try #require(findStrip(in: window))
        let column = try #require(strip.superview?.superview)
        #expect(strip.frame.height == EditorTabLayout.stripHeight)
        #expect(strip.convert(strip.bounds, to: column).maxY == column.bounds.maxY)
        #expect(column.safeAreaInsets.top == EditorTabLayout.stripHeight)
        let rule = try #require(strip.topRule)
        #expect(abs(rule.frame.maxY - strip.convert(strip.bounds, to: column).minY) < 0.5)
    }

    @Test("blank titlebar hits reach native chrome through the complete content host",
          arguments: [true, false], [true, false])
    func blankTitlebarRouting(sidebarVisible: Bool, hosted: Bool) throws {
        let window = makeWindow(sidebarVisible: sidebarVisible, hosted: hosted)
        defer { window.close() }
        window.contentView?.layoutSubtreeIfNeeded()
        let content = try #require(window.contentView)
        let root = try #require(content.superview)
        let strip = try #require(findStrip(in: window))
        let plus = try #require(strip.subviews.compactMap { $0 as? NSButton }.first)
        let stripFrame = strip.convert(strip.bounds, to: nil)
        let plusFrame = plus.convert(plus.bounds, to: nil)
        let pin = try pinButton(window)
        let pinFrame = pin.convert(pin.bounds, to: nil)
        let sidebar = try sidebarButton(window)
        let sidebarFrame = sidebar.convert(sidebar.bounds, to: nil)
        let points = [
            NSPoint(x: stripFrame.midX, y: stripFrame.maxY - 2),
            NSPoint(x: (plusFrame.maxX + pinFrame.minX) / 2, y: plusFrame.midY),
            NSPoint(x: sidebarFrame.midX, y: stripFrame.maxY - 2)
        ]
        #expect(!window.titlebarAppearsTransparent)
        for point in points {
            let hit = try #require(root.hitTest(root.convert(point, from: nil)))
            #expect(hit !== content && !hit.isDescendant(of: content))
            #expect(hit !== strip.superview && !hit.isDescendant(of: strip))
        }
        for button in [plus, pin, sidebar] {
            let point = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
            #expect(root.hitTest(root.convert(point, from: nil)) === button)
        }
        let tab = try #require(strip.tabViews.values.first)
        let titlePoint = tab.convert(NSPoint(x: tab.tabBounds.midX, y: tab.tabBounds.midY), to: nil)
        let titleHit = try #require(root.hitTest(root.convert(titlePoint, from: nil)))
        #expect(titleHit === tab || titleHit.isDescendant(of: tab))
    }

    @Test("native full-screen notifications rehome the same tab controls without losing the join")
    func fullScreenTabBandOwnership() throws {
        let window = makeWindow()
        defer { window.close() }
        let strip = try #require(findStrip(in: window))
        let topRule = try #require(strip.topRule)
        NotificationCenter.default.post(name: NSWindow.didEnterFullScreenNotification, object: window)
        window.contentView?.layoutSubtreeIfNeeded()
        #expect(window.titlebarAccessoryViewControllers.count == 1)
        #expect(strip.isDescendant(of: try #require(window.contentView)))
        #expect(strip.superview?.superview === topRule.superview)
        NotificationCenter.default.post(name: NSWindow.didExitFullScreenNotification, object: window)
        window.layoutIfNeeded()
        window.contentView?.layoutSubtreeIfNeeded()
        #expect(window.titlebarAccessoryViewControllers.count == 2)
        #expect(findStrip(in: window) === strip)
        #expect(!strip.isDescendant(of: try #require(window.contentView)))
        #expect(abs(strip.convert(strip.bounds, to: nil).minY - window.contentLayoutRect.maxY) < 0.5)
    }

    private func findStrip(in window: NSWindow) -> EditorTabStripView? {
        let accessories = window.styleMask.contains(.titled)
            ? window.titlebarAccessoryViewControllers.map(\.view) : []
        let views = accessories + [window.contentView].compactMap { $0 }
        return views.lazy.compactMap { findStrip(in: $0) }.first
    }

    private func findStrip(in view: NSView) -> EditorTabStripView? {
        if let strip = view as? EditorTabStripView { return strip }
        for subview in view.subviews {
            if let strip = findStrip(in: subview) { return strip }
        }
        return nil
    }
}
