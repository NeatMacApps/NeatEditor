enum EditorTheme: String, Codable, CaseIterable {
    case warm
    case whiteBlack

    static let defaultValue: Self = .warm

    /// Shared sRGB palette; each platform resolves its own native appearance.
    func surfaceRGB(dark: Bool) -> UInt32 {
        switch self {
        case .warm: dark ? 0x211F1D : 0xFAF8F5
        case .whiteBlack: dark ? 0x000000 : 0xFFFFFF
        }
    }

    func bandRGB(dark: Bool) -> UInt32 {
        switch self {
        case .warm: dark ? 0x2D2925 : 0xEEE8E0
        case .whiteBlack: dark ? 0x1C1C1E : 0xEEEEEE
        }
    }

    var localizedNameKey: String {
        switch self {
        case .warm: "theme.warm"
        case .whiteBlack: "theme.whiteBlack"
        }
    }

    var settingsSymbol: String {
        switch self {
        case .warm: "paintpalette"
        case .whiteBlack: "circle.lefthalf.filled"
        }
    }
}
