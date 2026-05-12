import Foundation

struct TranslationSettings {
    var provider: LLMProvider
    var endpoint: String
    var model: String
    var token: String
    var targetLanguage: String

    var asDictionary: [String: Any] {
        [
            "provider": provider.rawValue,
            "endpoint": endpoint,
            "model": model,
            "token": token,
            "targetLanguage": targetLanguage
        ]
    }
}
