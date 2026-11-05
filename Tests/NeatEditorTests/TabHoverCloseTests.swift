import AppKit
import Testing

@testable import NeatEditor

@MainActor
struct TabHoverCloseTests {
    @Test("hover reveals a native close button without moving the title or selecting the tab")
    func hoverAndClose() throws {
        let window = makeWindow()
        defer { window.close() }
        let strip = try #require(window.contentView as? EditorTabStripView)
        var selected: [UUID] = []
        var closed: [UUID] = []
        let tabs = ["Short.txt", "A very long filename that must fade before the close button.txt", "中文标题.txt"]
            .map { EditorTabDescriptor(id: UUID(), title: $0) }
        var actions = EditorTabActions()
        actions.onSelect = { selected.append($0) }
        actions.onClose = { closed.append($0) }
        strip.update(tabs: tabs, selectedTabID: tabs[0].id, actions: actions)
        strip.layoutSubtreeIfNeeded()
        let enter = try trackingEvent(.mouseEntered, window: window)
        let exit = try trackingEvent(.mouseExited, window: window)
        var frames: [CGRect] = []
        for tab in tabs {
            let item = try #require(strip.tabViews[tab.id])
            item.layoutSubtreeIfNeeded()
            item.mouseExited(with: exit)
            #expect(item.closeButton.isHidden)
            let titleFrame = item.titleField.frame
            item.mouseEntered(with: enter)
            #expect(!item.closeButton.isHidden)
            #expect(!item.closeButton.isBordered)
            #expect(item.closeButton.focusRingType == .none)
            #expect(item.titleField.frame == titleFrame)
            let point = item.convert(CGPoint(x: item.closeButton.bounds.midX, y: item.closeButton.bounds.midY),
                                     from: item.closeButton)
            let hit = strip.hitTest(strip.convert(point, from: item))
            #expect(hit === item.closeButton)
            item.closeButton.performClick(nil)
            #expect(closed.last == tab.id)
            #expect(strip.selectedTabID == tabs[0].id)
            item.mouseExited(with: exit)
            #expect(item.closeButton.isHidden)
            #expect(item.hitTest(item.convert(point, to: item.superview)) === item)
            frames.append(item.closeButton.frame)
        }
        #expect(selected.isEmpty)
        #expect(closed == tabs.map(\.id))
        #expect(frames.dropFirst().allSatisfy { $0 == frames.first })
    }

    @Test("inline rename suppresses close, and the gradient tracks theme and selection",
          arguments: [NSAppearance.Name.aqua, .darkAqua], EditorTheme.allCases)
    func renameAndPalette(appearanceName: NSAppearance.Name, theme: EditorTheme) throws {
        let window = makeWindow()
        defer { window.close() }
        window.appearance = NSAppearance(named: appearanceName)
        let strip = try #require(window.contentView as? EditorTabStripView)
        strip.theme = theme
        let tab = EditorTabDescriptor(id: UUID(), title: "Long filename with 中文 and text.txt")
        strip.update(tabs: [tab], selectedTabID: tab.id, actions: EditorTabActions())
        strip.layoutSubtreeIfNeeded()
        let item = try #require(strip.tabViews[tab.id])
        item.mouseEntered(with: try trackingEvent(.mouseEntered, window: window))
        item.layoutSubtreeIfNeeded()
        let fade = try #require(item.layer?.sublayers?.compactMap { $0 as? CAGradientLayer }.first)
        #expect(!fade.isHidden)
        #expect(fade.frame.minX < item.closeButton.frame.minX)
        #expect(fade.frame.maxX >= item.closeButton.frame.maxX)
        #expect(fade.frame.maxX < item.tabBounds.maxX - ConnectedTabGeometry.topInset)
        #expect(fade.zPosition < (item.closeButton.layer?.zPosition ?? 0))
        let titleFrame = item.titleField.frame
        for selected in [false, true] {
            item.update(descriptor: tab, selected: selected)
            item.layoutSubtreeIfNeeded()
            let expected = EditorChrome.resolvedColor(
                selected ? EditorChrome.editorSurfaceColor(for: theme) : EditorChrome.tabBarBackgroundColor(for: theme),
                for: item.effectiveAppearance
            )
            let colors = try #require(fade.colors as? [CGColor])
            #expect(colors.count == 3)
            #expect(colors[0].alpha == 0)
            #expect(colors[1] == expected.cgColor && colors[2] == expected.cgColor)
            #expect(item.titleField.frame == titleFrame)
        }
        strip.editingTabID = tab.id
        item.setEditing(true)
        #expect(item.closeButton.isHidden && fade.isHidden)
        item.mouseEntered(with: try trackingEvent(.mouseEntered, window: window))
        #expect(item.closeButton.isHidden)
        strip.editingTabID = nil
        item.setEditing(false)
        #expect(!item.closeButton.isHidden && !fade.isHidden)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 40),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = EditorTabStripView(frame: CGRect(x: 0, y: 0, width: 800, height: 40))
        return window
    }

    private func trackingEvent(_ type: NSEvent.EventType, window: NSWindow) throws -> NSEvent {
        try #require(NSEvent.enterExitEvent(with: type, location: .zero, modifierFlags: [],
                                           timestamp: 0, windowNumber: window.windowNumber,
                                           context: nil, eventNumber: 0, trackingNumber: 0, userData: nil))
    }
}
