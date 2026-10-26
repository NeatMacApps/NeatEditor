import AppKit
import SwiftUI

enum EditorChrome {
    static let tabBarBackgroundColor = adaptiveColor(name: "TabBand", light: 0xE3E9F0, dark: 0x29333F)
    static let tabBarBackground = Color(nsColor: tabBarBackgroundColor)
    static let editorSurfaceColor = adaptiveColor(name: "EditorSurface", light: 0xFAF8F5, dark: 0x211F1D)
    static let editorSurface = Color(editorSurfaceColor)
    static let borderColor = NSColor.separatorColor
    static let border = Color(borderColor)
    static let tabOutlineColor = NSColor(name: "com.x0c.NeatEditor.TabOutline") { appearance in
        let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return (dark ? NSColor.white : .black).withAlphaComponent(dark ? 0.10 : 0.12)
    }
    static let tabOutline = Color(tabOutlineColor)
    static let lineWidth: CGFloat = 1
    static let hoverFill = Color.secondary.opacity(0.08)

    /// Layer colors and cached native backgrounds must resolve in their view's
    /// appearance, which can differ from the application's current appearance.
    static func resolvedColor(_ color: NSColor, for appearance: NSAppearance) -> NSColor {
        var resolved = color
        appearance.performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.sRGB) ?? color
        }
        return resolved
    }

    private static func adaptiveColor(name: String, light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: NSColor.Name("com.x0c.NeatEditor.\(name)")) { appearance in
            let rgb = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
                           green: CGFloat((rgb >> 8) & 0xFF) / 255,
                           blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
        }
    }
}

struct EditorSurfaceBorderShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}
