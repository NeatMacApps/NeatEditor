import AppKit

/// A native companion to the toolbar tabs. Geometry is pulled while drawing,
/// after layout, rather than forwarded through SwiftUI state on later turns.
final class EditorTabTopRuleView: NSView {
    weak var strip: EditorTabStripView?

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let strip, !strip.tabs.isEmpty else { return }
        EditorChrome.tabOutlineColor.setFill()
        guard let join = strip.selectedTabJoin(in: self) else {
            bounds.fill()
            return
        }
        let lower = min(max(join.gap.lowerBound, bounds.minX), bounds.maxX)
        let upper = min(max(join.gap.upperBound, bounds.minX), bounds.maxX)
        if lower > bounds.minX {
            CGRect(x: bounds.minX, y: 0, width: lower - bounds.minX, height: bounds.height).fill()
        }
        if upper < bounds.maxX {
            CGRect(x: upper, y: 0, width: bounds.maxX - upper, height: bounds.height).fill()
        }
        drawOutlineFoot(of: join.tabBounds, within: lower...upper)
    }

    /// The opaque titlebar clips the strip at the band's bottom edge, and the
    /// outline's lowest row falls in this rule. Stroke that row from the same
    /// path so the corner arcs meet the rule instead of stopping 1 pt short.
    private func drawOutlineFoot(of tabBounds: CGRect, within span: ClosedRange<CGFloat>) {
        guard span.upperBound > span.lowerBound,
              let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.clip(to: CGRect(x: span.lowerBound, y: bounds.minY,
                                width: span.upperBound - span.lowerBound, height: bounds.height))
        context.addPath(ConnectedTabGeometry.outline(in: tabBounds))
        context.setStrokeColor(EditorChrome.tabOutlineColor.cgColor)
        context.setLineWidth(EditorChrome.lineWidth)
        context.strokePath()
        context.restoreGState()
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
