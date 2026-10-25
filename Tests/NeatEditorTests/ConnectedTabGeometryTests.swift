import AppKit
import Testing

@testable import NeatEditor

@MainActor
struct ConnectedTabGeometryTests {
    private func makeStrip() -> (NSWindow, EditorTabStripView, EditorTabTopRuleView) {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1200, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let strip = EditorTabStripView(frame: CGRect(x: 240, y: 548, width: 900, height: 52))
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
                let rect = CGRect(origin: origin, size: CGSize(width: width, height: 32))
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
            strip.setFrameSize(CGSize(width: width, height: 52))
            strip.layoutSubtreeIfNeeded()
            let gap = try #require(strip.selectedTabGap(in: rule))
            let frame = rule.convert(item.tabBounds, from: item)
            if width - 12 >= frame.width + 6 {
                #expect(abs(gap.lowerBound - (frame.minX - 3)) < 0.000_001)
                #expect(abs(gap.upperBound - (frame.maxX + 3)) < 0.000_001)
            }
            #expect(gap.lowerBound >= 40)
            #expect(gap.upperBound <= 40 + width - 12)
            #expect(item.titleField.frame.midX == item.tabBounds.midX)
        }
        let before = try #require(strip.selectedTabGap(in: rule))
        strip.setFrameOrigin(CGPoint(x: 300, y: 548))
        let after = try #require(strip.selectedTabGap(in: rule))
        #expect(abs(after.lowerBound - before.lowerBound - 60) < 0.000_001)
        #expect(abs(after.upperBound - before.upperBound - 60) < 0.000_001)
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
