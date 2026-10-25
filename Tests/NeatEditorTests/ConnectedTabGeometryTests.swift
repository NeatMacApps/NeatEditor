import SwiftUI
import Testing

@testable import NeatEditor

struct ConnectedTabGeometryTests {
    @Test("the local outline follows the fill at every tab size and origin")
    func outlineSharesFillGeometry() {
        for width: CGFloat in [160, 240, 400] {
            for origin in [CGPoint.zero, CGPoint(x: 71, y: 20)] {
                let rect = CGRect(origin: origin, size: CGSize(width: width, height: 32))
                let fill = ConnectedTabFillShape(
                    topInset: ConnectedTabGeometry.topInset,
                    topCornerRadius: ConnectedTabGeometry.topCornerRadius,
                    bottomJoinRadius: ConnectedTabGeometry.bottomJoinRadius
                ).path(in: rect)
                let outline = ConnectedTabOutlineShape().path(in: rect)
                let fillComponents = components(of: fill)
                let outlineComponents = components(of: outline)
                #expect(fillComponents.count == outlineComponents.count)
                for (filled, stroked) in zip(fillComponents, outlineComponents) {
                    #expect(filled.count == stroked.count)
                    for (lhs, rhs) in zip(filled, stroked) {
                        #expect(abs(lhs - rhs) < 0.000_000_001)
                    }
                }
                #expect(outline.boundingRect.maxY == rect.maxY + ConnectedTabGeometry.baselineCenterDrop)
                #expect(outline.boundingRect.minX == rect.minX - ConnectedTabGeometry.baselineOutset)
                #expect(outline.boundingRect.maxX == rect.maxX + ConnectedTabGeometry.baselineOutset)
            }
        }
    }

    private func components(of path: Path) -> [[CGFloat]] {
        var result: [[CGFloat]] = []
        path.forEach { element in
            switch element {
            case .move(to: let point):
                result.append([0, point.x, point.y])
            case .line(to: let point):
                result.append([1, point.x, point.y])
            case .quadCurve(to: let point, control: let control):
                result.append([2, point.x, point.y, control.x, control.y])
            case .curve(to: let point, control1: let first, control2: let second):
                result.append([3, point.x, point.y, first.x, first.y, second.x, second.y])
            case .closeSubpath:
                break
            }
        }
        return result
    }
}
