import Foundation

enum AppSettings {
    private static let providerKey = "provider"
    private static let endpointKey = "endpoint"
    private static let modelKey = "model"
    private static let targetLanguageKey = "targetLanguage"
    private static let appSupportFolderName = "LeafTranslate"
    private static let legacyAppSupportFolderName = "pdftranslate"
    private static let tokenFileName = "token.txt"

    static var provider: LLMProvider {
        get {
            guard let rawValue = UserDefaults.standard.string(forKey: providerKey) else {
                return .deepSeekPro
            }
            if rawValue == "deepSeek" {
                return .deepSeekPro
            }
            return LLMProvider(rawValue: rawValue) ?? .deepSeekPro
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: providerKey)
        }
    }

    static var endpoint: String {
        get { UserDefaults.standard.string(forKey: endpointKey) ?? provider.defaultEndpoint }
        set { UserDefaults.standard.set(newValue, forKey: endpointKey) }
    }

    static var model: String {
        get { UserDefaults.standard.string(forKey: modelKey) ?? provider.defaultModel }
        set { UserDefaults.standard.set(newValue, forKey: modelKey) }
    }

    static var targetLanguage: String {
        get { UserDefaults.standard.string(forKey: targetLanguageKey) ?? "Chinese" }
        set { UserDefaults.standard.set(newValue, forKey: targetLanguageKey) }
    }

    static var token: String {
        get { readToken() }
        set { writeToken(newValue) }
    }

    static func save(provider: LLMProvider, endpoint: String, model: String, token: String, targetLanguage: String) {
        self.provider = provider
        self.endpoint = endpoint
        self.model = model
        self.token = token
        self.targetLanguage = targetLanguage
        UserDefaults.standard.synchronize()
    }

    private static var appSupportDirectory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(appSupportFolderName, isDirectory: true)
    }

    private static var legacyAppSupportDirectory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(legacyAppSupportFolderName, isDirectory: true)
    }

    private static var tokenFileURL: URL? {
        appSupportDirectory?.appendingPathComponent(tokenFileName, isDirectory: false)
    }

    private static var legacyTokenFileURL: URL? {
        legacyAppSupportDirectory?.appendingPathComponent(tokenFileName, isDirectory: false)
    }

    private static func readToken() -> String {
        if let token = readToken(from: tokenFileURL), !token.isEmpty {
            return token
        }
        if let token = readToken(from: legacyTokenFileURL), !token.isEmpty {
            writeToken(token)
            return token
        }
        return ""
    }

    private static func readToken(from url: URL?) -> String? {
        guard let url,
              let data = try? Data(contentsOf: url),
              let token = String(data: data, encoding: .utf8) else {
            return nil
        }
        return token.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func writeToken(_ token: String) {
        guard let appSupportDirectory, let tokenFileURL else { return }
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            try FileManager.default.createDirectory(at: appSupportDirectory, withIntermediateDirectories: true)
            if trimmedToken.isEmpty {
                try? FileManager.default.removeItem(at: tokenFileURL)
                return
            }
            try (trimmedToken + "\n").write(to: tokenFileURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tokenFileURL.path)
        } catch {
            NSLog("Failed to save token: \(error.localizedDescription)")
        }
    }
}
