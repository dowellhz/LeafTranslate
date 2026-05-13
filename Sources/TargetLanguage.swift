import Foundation

enum TargetLanguage: String, CaseIterable {
    case chinese = "Chinese"
    case english = "English"
    case spanish = "Spanish"
    case french = "French"
    case japanese = "Japanese"
    case korean = "Korean"

    var displayName: String {
        switch self {
        case .chinese: return AppText.usesChinese ? "中文" : "Chinese"
        case .english: return AppText.usesChinese ? "英文" : "English"
        case .spanish: return AppText.usesChinese ? "西班牙语" : "Spanish"
        case .french: return AppText.usesChinese ? "法语" : "French"
        case .japanese: return AppText.usesChinese ? "日语" : "Japanese"
        case .korean: return AppText.usesChinese ? "韩语" : "Korean"
        }
    }

    var fileNameComponent: String {
        rawValue
    }

    static func normalized(_ value: String) -> TargetLanguage {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch trimmed {
        case "中文", "chinese", "zh", "cn", "简体中文":
            return .chinese
        case "英文", "english", "en":
            return .english
        case "西班牙语", "spanish", "es", "español":
            return .spanish
        case "法语", "french", "fr", "français":
            return .french
        case "日语", "japanese", "ja", "日本語":
            return .japanese
        case "韩语", "korean", "ko", "한국어":
            return .korean
        default:
            return Self(rawValue: value) ?? .chinese
        }
    }
}
