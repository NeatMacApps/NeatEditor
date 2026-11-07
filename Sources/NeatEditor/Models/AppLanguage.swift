import Foundation

enum AppLanguage: String, Codable, CaseIterable {
    case system = "system"
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    var settingsSymbol: String {
        switch self {
        case .system: "globe"
        case .english: "textformat.abc"
        case .simplifiedChinese: "character.textbox"
        }
    }

    var localizedNameKey: String {
        switch self {
        case .system:
            "System Default"
        case .english:
            "English"
        case .simplifiedChinese:
            "Simplified Chinese"
        }
    }
}
