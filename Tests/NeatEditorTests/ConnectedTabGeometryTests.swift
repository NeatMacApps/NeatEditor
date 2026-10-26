import AppKit
import Testing

@testable import NeatEditor

@MainActor
struct ConnectedTabGeometryTests {
    private func makeStrip() -> (NSWindow, EditorTabStripView, EditorTabTopRuleView) {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1200, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let strip = EditorTabStripView(frame: CGRect(x: 240, y: 548, width: 900, height: 40))
        let rule = EditorTabTopRuleView(frame: CGRect(x: 200, y: 547, width: 1000, height: 1))
        window.contentView?.addSubview(strip)
        window.contentView?.addSubview(rule)
        strip.topRule = rule
        rule.strip = strip
        return (window, strip, rule)
    }

    @Test("the native outline and fill share the exact open stepped curve")
    func sharedCurve() {
        for width: CGFloat in [160, 240, 400] {
            for origin in [CGPoint.zero, CGPoint(x: 71, y: 20)] {
                let rect = CGRect(origin: origin, size: CGSize(width: width, height: EditorTabLayout.tabHeight))
                let outline = ConnectedTabGeometry.outline(in: rect)
                let fill = ConnectedTabGeometry.fill(in: rect)
                #expect(components(of: outline) == components(of: fill))
                #expect(abs(outline.boundingBoxOfPath.maxY - rect.maxY - 0.5) < 0.000_001)
                #expect(abs(outline.boundingBoxOfPath.minX - rect.minX + 3) < 0.000_001)
                #expect(abs(outline.boundingBoxOfPath.maxX - rect.maxX - 3) < 0.000_001)
            }
        }
    }

    @Test("resize and direction reversal reveal selection and update the join synchronously")
    func continuousResize() throws {
        let (window, strip, rule) = makeStrip()
        defer { window.close() }
        let tabs = ["One.md", "中英文长文件名.md", "Config.yml", "Readme.md"].map {
            EditorTabDescriptor(id: UUID(), title: $0)
        }
        let last = try #require(tabs.last)
        strip.update(tabs: tabs, selectedTabID: last.id, actions: EditorTabActions())
        let item = try #require(strip.tabViews[last.id])
        for width: CGFloat in [900, 700, 500, 300, 180, 350, 600, 900, 450, 800] {
            strip.setFrameSize(CGSize(width: width, height: 40))
            strip.layoutSubtreeIfNeeded()
            let gap = try #require(strip.selectedTabGap(in: rule))
            let frame = rule.convert(item.tabBounds, from: item)
            if width - 32 >= frame.width + 6 {
                #expect(abs(gap.lowerBound - (frame.minX - 3)) < 0.000_001)
                #expect(abs(gap.upperBound - (frame.maxX + 3)) < 0.000_001)
            }
            #expect(gap.lowerBound >= 40)
            #expect(gap.upperBound <= 40 + width - 32)
            #expect(item.titleField.frame.midX == item.tabBounds.midX)
            #expect(strip.convert(item.titleField.bounds, from: item.titleField).midY == EditorTabLayout.contentCenterY)
            #expect(item.tabBounds.height == EditorTabLayout.tabHeight)
            #expect(strip.convert(item.tabBounds, from: item).minY == 4)
        }
        let before = try #require(strip.selectedTabGap(in: rule))
        strip.setFrameOrigin(CGPoint(x: 300, y: 548))
        let after = try #require(strip.selectedTabGap(in: rule))
        #expect(abs(after.lowerBound - before.lowerBound - 60) < 0.000_001)
        #expect(abs(after.upperBound - before.upperBound - 60) < 0.000_001)
    }

    @Test("blank toolbar space passes through while tab and rename fields remain interactive")
    func blankChromeHitTesting() throws {
        let (window, strip, _) = makeStrip()
        defer { strip.finishRename(commit: false); window.close() }
        let tabs = ["One.md", "我的职业技术规划.txt"].map {
            EditorTabDescriptor(id: UUID(), title: $0)
        }
        let first = try #require(tabs.first)
        strip.update(tabs: tabs, selectedTabID: first.id, actions: EditorTabActions())
        for width: CGFloat in [900, 600, 250, 900] {
            strip.setFrameSize(CGSize(width: width, height: 40))
            strip.layoutSubtreeIfNeeded()
            for x in [CGFloat(10), width / 2, width - 1] {
                let point = strip.convert(CGPoint(x: x, y: 2), to: strip.superview)
                #expect(strip.hitTest(point) == nil)
            }
            let item = try #require(strip.tabViews[first.id])
            let titlePoint = item.convert(CGPoint(x: item.tabBounds.midX, y: item.tabBounds.midY),
                                          to: strip.superview)
            #expect(strip.hitTest(titlePoint) === item)
            #expect(strip.mouseDownCanMoveWindow)
        }
        let trailing = strip.convert(CGPoint(x: 850, y: 30), to: strip.superview)
        #expect(strip.hitTest(trailing) == nil)
        strip.beginRename(first.id)
        let item = try #require(strip.tabViews[first.id])
        let fieldPoint = item.convert(CGPoint(x: item.tabBounds.midX, y: item.tabBounds.midY),
                                      to: strip.superview)
        let hit = try #require(strip.hitTest(fieldPoint))
        #expect(hit === item.titleField || hit.isDescendant(of: item.titleField))
        strip.finishRename(commit: false)
        strip.update(tabs: [], selectedTabID: nil, actions: EditorTabActions())
        strip.layoutSubtreeIfNeeded()
        #expect(strip.hitTest(trailing) == nil)
    }

    @Test("new document button follows the last tab, stays visible on overflow and respects accessory insets")
    func newDocumentButtonPlacement() throws {
        let (window, strip, _) = makeStrip()
        defer { window.close() }
        var created = 0
        var actions = EditorTabActions()
        actions.onNewDocument = { created += 1 }
        let tabs = ["One.md", "Two.md"].map { EditorTabDescriptor(id: UUID(), title: $0) }
        strip.update(tabs: tabs, selectedTabID: tabs[0].id, actions: actions)
        strip.layoutSubtreeIfNeeded()
        let button = try #require(strip.subviews.compactMap { $0 as? NSButton }.first)
        #expect(button.frame.minX == 2 * EditorTabLayout.tabWidth)
        #expect(button.frame.midY == EditorTabLayout.contentCenterY)
        #expect(button.frame.height == EditorTabLayout.actionHeight)
        #expect(strip.hitTest(strip.convert(CGPoint(x: button.frame.midX, y: button.frame.midY),
                                            to: strip.superview)) === button)
        button.performClick(nil)
        #expect(created == 1)
        #expect(strip.accessibilityChildren()?.contains { ($0 as? NSButton) === button } == true)

        strip.contentInsets = NSEdgeInsets(top: 0, left: 120, bottom: 0, right: 40)
        strip.layoutSubtreeIfNeeded()
        let first = try #require(strip.tabViews[tabs[0].id])
        #expect(strip.convert(first.tabBounds, from: first).minX == 120)
        #expect(button.frame.minX == 120 + 2 * EditorTabLayout.tabWidth)

        strip.setFrameSize(CGSize(width: 400, height: 40))
        strip.layoutSubtreeIfNeeded()
        #expect(abs(button.frame.maxX - (400 - 40)) < 0.001)
    }

    @Test("inactive tabs never acquire a hover capsule or retain the selected fill")
    func noInactiveBackground() throws {
        let (window, strip, _) = makeStrip()
        defer { window.close() }
        let first = EditorTabDescriptor(id: UUID(), title: "One.md")
        let second = EditorTabDescriptor(id: UUID(), title: "我的职业技术规划.txt")
        strip.update(tabs: [first, second], selectedTabID: first.id, actions: EditorTabActions())
        strip.layoutSubtreeIfNeeded()
        let item = try #require(strip.tabViews[second.id])
        func renderedBackground() throws -> Data {
            let image = NSImage(size: item.bounds.size, flipped: true) { rect in
                NSColor.windowBackgroundColor.setFill()
                rect.fill()
                item.draw(rect)
                return true
            }
            return try #require(image.tiffRepresentation)
        }
        let inactive = try renderedBackground()
        func trackingEvent(_ type: NSEvent.EventType) throws -> NSEvent {
            try #require(NSEvent.enterExitEvent(
                with: type, location: .zero, modifierFlags: [], timestamp: 1,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                trackingNumber: 0, userData: nil
            ))
        }
        item.mouseEntered(with: try trackingEvent(.mouseEntered))
        #expect(try renderedBackground() == inactive)
        item.update(descriptor: second, selected: true)
        #expect(try renderedBackground() != inactive)
        item.update(descriptor: second, selected: false)
        #expect(try renderedBackground() == inactive)
        item.mouseExited(with: try trackingEvent(.mouseExited))
        #expect(try renderedBackground() == inactive)
    }

    @Test("native tab identities survive title updates and selection changes")
    func stableIdentity() throws {
        let (window, strip, rule) = makeStrip()
        defer { window.close() }
        let first = EditorTabDescriptor(id: UUID(), title: "One")
        let second = EditorTabDescriptor(id: UUID(), title: "Two")
        strip.update(tabs: [first, second], selectedTabID: first.id, actions: EditorTabActions())
        let view = try #require(strip.tabViews[first.id])
        let renamed = EditorTabDescriptor(id: first.id, title: "A much longer title.md")
        strip.update(tabs: [renamed, second], selectedTabID: second.id, actions: EditorTabActions())
        strip.layoutSubtreeIfNeeded()
        #expect(strip.tabViews[first.id] === view)
        #expect(view.titleField.stringValue == renamed.title)
        strip.update(tabs: [], selectedTabID: nil, actions: EditorTabActions())
        strip.layoutSubtreeIfNeeded()
        #expect(strip.tabViews.isEmpty)
        #expect(strip.selectedTabGap(in: rule) == nil)
    }

    @Test("native double-click only renames a tab selected before its first click")
    func doubleClickEligibility() throws {
        let (window, strip, _) = makeStrip()
        defer { strip.finishRename(commit: false); window.close() }
        let first = EditorTabDescriptor(id: UUID(), title: "One")
        let second = EditorTabDescriptor(id: UUID(), title: "Two")
        strip.update(tabs: [first, second], selectedTabID: first.id, actions: EditorTabActions())
        strip.handleClick(tabID: second.id, clickCount: 1)
        strip.update(tabs: [first, second], selectedTabID: second.id, actions: EditorTabActions())
        strip.handleClick(tabID: second.id, clickCount: 2)
        #expect(strip.editingTabID == nil)
        strip.handleClick(tabID: second.id, clickCount: 1)
        strip.handleClick(tabID: second.id, clickCount: 2)
        #expect(strip.editingTabID == second.id)
    }

    @Test("rename commits once, cancel restores the title and removed tabs do not retain drafts")
    func renameOwnership() throws {
        let (window, strip, _) = makeStrip()
        defer { strip.finishRename(commit: false); window.close() }
        let tab = EditorTabDescriptor(id: UUID(), title: "Original")
        var renames: [String] = []
        var actions = EditorTabActions()
        actions.onRename = { _, title in renames.append(title) }
        strip.update(tabs: [tab], selectedTabID: tab.id, actions: actions)
        strip.layoutSubtreeIfNeeded()
        let field = try #require(strip.tabViews[tab.id]?.titleField)
        strip.beginRename(tab.id)
        field.stringValue = "  Renamed / note  "
        strip.finishRename(commit: true)
        strip.finishRename(commit: true)
        #expect(renames == ["Renamed - note"])
        #expect(strip.renameClickMonitor == nil)
        strip.beginRename(tab.id)
        field.stringValue = "Discard this"
        strip.finishRename(commit: false)
        #expect(field.stringValue == "Original")
        #expect(renames.count == 1)
        strip.beginRename(tab.id)
        strip.update(tabs: [], selectedTabID: nil, actions: actions)
        #expect(strip.editingTabID == nil)
        #expect(strip.renameClickMonitor == nil)
    }

    @Test("tabs keep equal widths, compact centered type and native trailing ellipsis")
    func nativeTitleMeasurement() throws {
        let (window, strip, _) = makeStrip()
        defer { window.close() }
        let titles = ["短.txt", "我的职业技术规划以及未来五年的详细规划.txt",
                      "MacOS26-Compatibility-Check.txt", "Readme.md", "gjpq.txt"]
        let tabs = titles.map { EditorTabDescriptor(id: UUID(), title: $0) }
        for selected in tabs {
            strip.update(tabs: tabs, selectedTabID: selected.id, actions: EditorTabActions())
            strip.layoutSubtreeIfNeeded()
            for tab in tabs {
                let item = try #require(strip.tabViews[tab.id])
                let field = item.titleField
                #expect(item.tabBounds.width == 168)
                #expect(field.frame.width == 144)
                #expect(field.font?.pointSize == 13)
                #expect(field.frame.height >= field.intrinsicContentSize.height)
                #expect(strip.convert(field.bounds, from: field).midY == EditorTabLayout.contentCenterY)
                #expect(field.lineBreakMode == .byTruncatingTail)
                #expect(field.usesSingleLineMode)
                #expect(field.stringValue == tab.title)
                #expect(item.toolTip == tab.title)
            }
        }
    }

    @Test("two-tone surfaces follow the owning appearance and keep editor and gutter identical",
          arguments: [NSAppearance.Name.aqua, .darkAqua])
    func twoToneSurfaces(appearanceName: NSAppearance.Name) throws {
        let appearance = try #require(NSAppearance(named: appearanceName))
        let dark = appearanceName == .darkAqua
        let expectedBand: [CGFloat] = dark ? [41, 51, 63] : [227, 233, 240]
        let expectedSurface: [CGFloat] = dark ? [33, 31, 29] : [250, 248, 245]
        let band = EditorChrome.resolvedColor(EditorChrome.tabBarBackgroundColor, for: appearance)
        let surface = EditorChrome.resolvedColor(EditorChrome.editorSurfaceColor, for: appearance)
        for (component, expected) in zip([band.redComponent, band.greenComponent, band.blueComponent], expectedBand) {
            #expect(abs(component - expected / 255) < 0.0001)
        }
        for (component, expected) in zip([surface.redComponent, surface.greenComponent, surface.blueComponent], expectedSurface) {
            #expect(abs(component - expected / 255) < 0.0001)
        }
        #expect(band != surface)

        let container = EditorTextContainerView()
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = container
        window.appearance = appearance
        container.applyEditorTextAttributes()
        #expect(container.textView.backgroundColor == surface)
        let gutter = try #require(container.subviews.compactMap { $0 as? LineNumberGutterView }.first)
        gutter.updateColors()
        let gutterColor = try #require(gutter.layer?.backgroundColor).converted(
            to: try #require(CGColorSpace(name: CGColorSpace.sRGB)), intent: .defaultIntent, options: nil
        )
        #expect(try #require(gutterColor?.components).prefix(3).elementsEqual(
            [surface.redComponent, surface.greenComponent, surface.blueComponent],
            by: { abs($0 - $1) < 0.0001 }
        ))
    }

    @Test("overflow offsets are bounded and long selected titles are centered")
    func boundedOffsets() {
        #expect(EditorTabLayout.revealedOffset(selectedFrame: nil, viewportWidth: 500,
                                               contentWidth: 200, currentOffset: 90) == 0)
        #expect(EditorTabLayout.revealedOffset(selectedFrame: CGRect(x: 300, y: 0, width: 400, height: 32),
                                               viewportWidth: 100, contentWidth: 1000,
                                               currentOffset: 0) == 450)
        #expect(EditorTabLayout.sanitizedTitle(" .\nFoo:/\tBar. ") == "Foo-- Bar")
    }

    @Test("wheel stepping retains threshold and clears direction-reversal accumulation")
    func scrollStepping() {
        var stepper = EditorTabScrollStepper()
        #expect(stepper.steps(delta: 20, timestamp: 1, precise: true).isEmpty)
        #expect(stepper.steps(delta: -20, timestamp: 1.1, precise: true).isEmpty)
        #expect(stepper.steps(delta: -20, timestamp: 1.2, precise: true) == [1])
        stepper.reset()
        #expect(stepper.steps(delta: 400, timestamp: 2, precise: false) == [-1, -1])
    }

    private func components(of path: CGPath) -> [[CGFloat]] {
        var result: [[CGFloat]] = []
        path.applyWithBlock { element in
            let value = element.pointee
            let count: Int
            switch value.type {
            case .moveToPoint, .addLineToPoint: count = 1
            case .addQuadCurveToPoint: count = 2
            case .addCurveToPoint: count = 3
            case .closeSubpath: return
            @unknown default: return
            }
            var row = [CGFloat(value.type.rawValue)]
            for index in 0..<count {
                row.append(contentsOf: [value.points[index].x, value.points[index].y])
            }
            result.append(row)
        }
        return result
    }
}
