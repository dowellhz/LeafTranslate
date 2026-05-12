import Foundation

struct TranslationSettings {
    var provider: LLMProvider
    var endpoint: String
    var model: String
    var token: String
    var targetLanguage: String
    var cacheDirectory: URL?

    var asDictionary: [String: Any] {
        var dictionary: [String: Any] = [
            "provider": provider.rawValue,
            "endpoint": endpoint,
            "model": model,
            "token": token,
            "targetLanguage": targetLanguage
        ]
        if let cacheDirectory {
            dictionary["cacheDirectory"] = cacheDirectory.path
        }
        return dictionary
    }
}
