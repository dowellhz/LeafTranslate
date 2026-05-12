import Foundation

enum LLMProvider: String, CaseIterable {
    case deepSeekPro
    case deepSeekFlash
    case minimax
    case claude
    case gemini
    case custom

    var displayName: String {
        switch self {
        case .deepSeekPro: return "DeepSeek Pro"
        case .deepSeekFlash: return "DeepSeek Flash"
        case .minimax: return "MiniMax"
        case .claude: return "Claude"
        case .gemini: return "Gemini"
        case .custom: return "Custom"
        }
    }

    var defaultEndpoint: String {
        switch self {
        case .deepSeekPro, .deepSeekFlash:
            return "https://api.deepseek.com/chat/completions"
        case .minimax:
            return "https://api.minimax.chat/v1/chat/completions"
        case .claude:
            return "https://api.anthropic.com/v1/messages"
        case .gemini:
            return "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"
        case .custom:
            return "https://api.example.com/v1/chat/completions"
        }
    }

    var defaultModel: String {
        switch self {
        case .deepSeekPro:
            return "deepseek-chat"
        case .deepSeekFlash:
            return "deepseek-v4-flash"
        case .minimax:
            return "MiniMax-Text-01"
        case .claude:
            return "claude-3-5-haiku-latest"
        case .gemini:
            return "gemini-2.0-flash"
        case .custom:
            return "custom-model"
        }
    }
}
