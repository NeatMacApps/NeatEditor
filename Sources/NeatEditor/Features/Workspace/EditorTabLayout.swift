import AppKit

/// Lightweight UI input: editor buffers never enter the tab component.
struct EditorTabDescriptor: Identifiable, Equatable {
    let id: UUID
    let title: String
    let fileURL: URL?

    init(id: UUID, title: String, fileURL: URL? = nil) {
        self.id = id
        self.title = title
        self.fileURL = fileURL
    }

    init(_ tab: EditorTab) {
        self.init(id: tab.id, title: tab.title, fileURL: tab.fileURL)
    }
}

@MainActor
struct EditorTabActions {
    var onSelect: (UUID) -> Void = { _ in }
    var onSelectRelative: (Int) -> Void = { _ in }
    var onRename: (UUID, String) -> Void = { _, _ in }
    var onClose: (UUID) -> Void = { _ in }
    var onDelete: (UUID) -> Void = { _ in }
    var onCloseOthers: (UUID) -> Void = { _ in }
}

enum EditorTabLayout {
    static let stripHeight: CGFloat = 52
    static let tabHeight: CGFloat = 32
    static let trailingPadding: CGFloat = 12
    static let fadeWidth: CGFloat = 16
    static let titleFontSize: CGFloat = 13
    static let horizontalPadding = textWidth("untit")
    static let minimumTabWidth = ceil(textWidth("untitleduntitled") + 2 * horizontalPadding)
    static let minimumWindowEdge = ceil(76 + 12 + 52 + 2 * minimumTabWidth + 24)

    @MainActor
    static func width(for field: NSTextField) -> CGFloat {
        // Cell insets depend on the configured alignment and editing style.
        // Measure the displayed field rather than a separately configured copy.
        let width = field.cell?.cellSize.width ?? field.intrinsicContentSize.width
        return max(minimumTabWidth, ceil(width + 2 * horizontalPadding))
    }

    private static func textWidth(_ title: String) -> CGFloat {
        (title as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: titleFontSize, weight: .medium)
        ]).width
    }

    static func revealedOffset(
        selectedFrame: CGRect?, viewportWidth: CGFloat, contentWidth: CGFloat, currentOffset: CGFloat
    ) -> CGFloat {
        let limit = max(0, contentWidth - viewportWidth)
        var offset = min(max(currentOffset, 0), limit)
        guard let selectedFrame, viewportWidth > 0 else { return offset }
        if selectedFrame.width > viewportWidth {
            offset = selectedFrame.midX - viewportWidth / 2
        } else if selectedFrame.minX < offset {
            offset = selectedFrame.minX
        } else if selectedFrame.maxX > offset + viewportWidth {
            offset = selectedFrame.maxX - viewportWidth
        }
        return min(max(offset, 0), limit)
    }

    static func sanitizedTitle(_ title: String) -> String {
        title.components(separatedBy: CharacterSet(charactersIn: "/:"))
            .joined(separator: "-")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
    }
}

/// The single stepped curve used by both fill and open outline.
enum ConnectedTabGeometry {
    static let topInset: CGFloat = 6
    static let topCornerRadius: CGFloat = 9
    static let bottomJoinRadius: CGFloat = 9
    static let baselineOutset: CGFloat = bottomJoinRadius - topInset
    static let baselineCenterDrop: CGFloat = 0.5

    static func outline(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        let inset = min(topInset, rect.width / 4)
        let radius = min(topCornerRadius, rect.width / 2, rect.height / 2)
        let bottomRadius = min(bottomJoinRadius, rect.width / 2, rect.height / 2)
        let bottom = rect.maxY + baselineCenterDrop
        path.move(to: CGPoint(x: rect.minX + inset - bottomRadius, y: bottom))
        path.addArc(
            tangent1End: CGPoint(x: rect.minX + inset, y: bottom),
            tangent2End: CGPoint(x: rect.minX + inset, y: rect.minY),
            radius: bottomRadius
        )
        path.addLine(to: CGPoint(x: rect.minX + inset, y: rect.minY + radius))
        path.addArc(
            tangent1End: CGPoint(x: rect.minX + inset, y: rect.minY),
            tangent2End: CGPoint(x: rect.maxX - inset, y: rect.minY),
            radius: radius
        )
        path.addLine(to: CGPoint(x: rect.maxX - inset - radius, y: rect.minY))
        path.addArc(
            tangent1End: CGPoint(x: rect.maxX - inset, y: rect.minY),
            tangent2End: CGPoint(x: rect.maxX - inset, y: bottom),
            radius: radius
        )
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: bottom - bottomRadius))
        path.addArc(
            tangent1End: CGPoint(x: rect.maxX - inset, y: bottom),
            tangent2End: CGPoint(x: rect.maxX - inset + bottomRadius, y: bottom),
            radius: bottomRadius
        )
        return path
    }

    static func fill(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        path.addPath(outline(in: rect))
        path.closeSubpath()
        return path
    }
}

/// Retains the existing wheel/trackpad stepping policy without view state.
struct EditorTabScrollStepper {
    private var accumulated: CGFloat = 0
    private var lastTimestamp: TimeInterval = 0

    mutating func reset() {
        accumulated = 0
        lastTimestamp = 0
    }

    mutating func steps(delta: CGFloat, timestamp: TimeInterval, precise: Bool) -> [Int] {
        guard delta != 0 else { return [] }
        if timestamp - lastTimestamp > 0.35 { accumulated = 0 }
        let scaled = delta * (precise ? 1 / 36 : 0.005)
        if accumulated != 0, scaled.sign != accumulated.sign { accumulated = 0 }
        accumulated += scaled
        lastTimestamp = timestamp
        var result: [Int] = []
        while abs(accumulated) >= 1 {
            result.append(accumulated > 0 ? -1 : 1)
            accumulated += accumulated > 0 ? -1 : 1
        }
        return result
    }
}
