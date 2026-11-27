import CoreGraphics
import Foundation

/// Discrete interface chrome font size levels (sidebar, top tab bar, search bar,
/// status pill, and workspace chrome). Independent of the document editor's font size.
enum InterfaceFontSize: String, Codable, CaseIterable, Hashable, Sendable {
    case extraSmall
    case small
    case standard
    case large
    case extraLarge

    static let defaultValue: Self = .standard

    var stepIndex: Int {
        switch self {
        case .extraSmall: 0
        case .small: 1
        case .standard: 2
        case .large: 3
        case .extraLarge: 4
        }
    }

    init(stepIndex: Int) {
        let clamped = min(max(stepIndex, 0), Self.allCases.count - 1)
        self = Self.allCases[clamped]
    }

    var localizedNameKey: String {
        switch self {
        case .extraSmall: "interfaceFontSize.extraSmall"
        case .small: "interfaceFontSize.small"
        case .standard: "interfaceFontSize.standard"
        case .large: "interfaceFontSize.large"
        case .extraLarge: "interfaceFontSize.extraLarge"
        }
    }

    /// Relative scale factor around `.standard` (1.0), used for secondary chrome controls.
    var scaleFactor: CGFloat {
        switch self {
        case .extraSmall: 0.85
        case .small: 0.92
        case .standard: 1.0
        case .large: 1.12
        case .extraLarge: 1.24
        }
    }

    /// Top tab bar document title point size (fits cleanly inside the 36 pt tab height).
    var tabTitleFontSize: CGFloat {
        switch self {
        case .extraSmall: 11
        case .small: 12
        case .standard: 13
        case .large: 14.5
        case .extraLarge: 16
        }
    }

    /// Sidebar section folder header point size.
    var sidebarHeaderFontSize: CGFloat {
        switch self {
        case .extraSmall: 10
        case .small: 10.5
        case .standard: 11
        case .large: 12
        case .extraLarge: 13.5
        }
    }

    /// Sidebar file row title point size.
    var sidebarTitleFontSize: CGFloat {
        switch self {
        case .extraSmall: 11
        case .small: 12
        case .standard: 13
        case .large: 14.5
        case .extraLarge: 16
        }
    }

    /// Sidebar file row 2-line preview point size.
    var sidebarPreviewFontSize: CGFloat {
        switch self {
        case .extraSmall: 9.5
        case .small: 10
        case .standard: 11
        case .large: 12
        case .extraLarge: 13
        }
    }

    /// Fixed single-line title slot height in the sidebar so all rows stay equal height without clipping.
    var sidebarTitleLineHeight: CGFloat {
        switch self {
        case .extraSmall: 16
        case .small: 17
        case .standard: 18
        case .large: 21
        case .extraLarge: 23
        }
    }

    /// Fixed two-line preview slot height in the sidebar so all rows stay equal height without clipping.
    var sidebarPreviewHeight: CGFloat {
        switch self {
        case .extraSmall: 25
        case .small: 27
        case .standard: 28
        case .large: 32
        case .extraLarge: 35
        }
    }

    /// Scales a base chrome font size (e.g. search bar, character count, shortcut hint) to 0.5 pt increments.
    func scaledFontSize(from base: CGFloat) -> CGFloat {
        (base * scaleFactor * 2).rounded() / 2
    }
}
