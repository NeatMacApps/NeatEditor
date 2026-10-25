import AppKit

/// A native companion to the toolbar tabs. Geometry is pulled while drawing,
/// after layout, rather than forwarded through SwiftUI state on later turns.
final class EditorTabTopRuleView: NSView {
    weak var strip: EditorTabStripView?

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let strip, !strip.tabs.isEmpty else { return }
        NSColor.labelColor.withAlphaComponent(0.22).setFill()
        guard let gap = strip.selectedTabGap(in: self) else {
            bounds.fill()
            return
        }
        let lower = min(max(gap.lowerBound, bounds.minX), bounds.maxX)
        let upper = min(max(gap.upperBound, bounds.minX), bounds.maxX)
        if lower > bounds.minX {
            CGRect(x: bounds.minX, y: 0, width: lower - bounds.minX, height: bounds.height).fill()
        }
        if upper < bounds.maxX {
            CGRect(x: upper, y: 0, width: bounds.maxX - upper, height: bounds.height).fill()
        }
    }

    override func layout() {
        super.layout()
        needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
