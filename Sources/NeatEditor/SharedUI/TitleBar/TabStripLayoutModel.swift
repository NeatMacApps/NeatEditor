import SwiftUI

/// Whether the toolbar tab strip has document tabs and where the selected tab
/// meets the editor's top rule, measured in window coordinates.
///
/// The tab strip lives in a native toolbar item that is narrower than the
/// editor column. The editor column draws its own top rule, so it needs this
/// window-space range to keep that rule continuous without cutting through the
/// selected tab's opening to the page.
struct TabStripLayoutState: Equatable {
    var hasTabs = false
    var selectedTabGap: ClosedRange<CGFloat>?
}

@MainActor
@Observable
final class TabStripLayoutModel {
    var state = TabStripLayoutState()
}

/// The editor column's one-point top rule. The optional gap is where the
/// selected tab's outline joins the page and no horizontal rule may cross.
struct EditorTopRuleShape: Shape {
    var gap: ClosedRange<CGFloat>?

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let gap, gap.lowerBound < gap.upperBound else {
            path.addRect(fullRect(in: rect))
            return path
        }

        let lower = max(rect.minX, gap.lowerBound)
        let upper = min(rect.maxX, gap.upperBound)
        guard lower < upper else {
            path.addRect(fullRect(in: rect))
            return path
        }

        if lower > rect.minX {
            path.addRect(
                CGRect(
                    x: rect.minX,
                    y: rect.minY,
                    width: lower - rect.minX,
                    height: rect.height
                )
            )
        }
        if upper < rect.maxX {
            path.addRect(
                CGRect(
                    x: upper,
                    y: rect.minY,
                    width: rect.maxX - upper,
                    height: rect.height
                )
            )
        }
        return path
    }

    private func fullRect(in rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
    }
}
