enum EditorTheme: String, Codable, CaseIterable {
    case warm
    case whiteBlack

    static let defaultValue: Self = .warm

    var localizedNameKey: String {
        switch self {
        case .warm: "theme.warm"
        case .whiteBlack: "theme.whiteBlack"
        }
    }
}
