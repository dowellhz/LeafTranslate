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

struct LLMSettings {
    var provider: LLMProvider
    var endpoint: String
    var model: String
    var token: String
    var targetLanguage: String

    var endpointURL: URL? {
        URL(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var usesAzureAPIKeyHeader: Bool {
        guard provider == .custom,
              let host = endpointURL?.host?.lowercased() else {
            return false
        }
        return host.hasSuffix(".openai.azure.com")
            || host.hasSuffix(".services.ai.azure.com")
            || host.hasSuffix(".cognitiveservices.azure.com")
    }

    var usesAzureDeploymentEndpoint: Bool {
        guard usesAzureAPIKeyHeader else { return false }
        return endpointURL?.path.lowercased().contains("/openai/deployments/") == true
    }

    var usesResponsesEndpoint: Bool {
        guard let path = endpointURL?.path.lowercased() else { return false }
        return path.hasSuffix("/openai/responses") || path.hasSuffix("/openai/v1/responses")
    }
}

final class LLMClient {
    func translate(paragraph: String, settings: LLMSettings) async throws -> String {
        guard !settings.token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Token is empty. Configure an API token before translation."
        }
        guard let url = URL(string: settings.endpoint),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            throw NSError(domain: "LeafTranslate", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid LLM endpoint URL."])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        switch settings.provider {
        case .claude:
            request.setValue(settings.token, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.httpBody = try JSONSerialization.data(withJSONObject: claudePayload(paragraph: paragraph, settings: settings))
        case .deepSeekPro, .deepSeekFlash, .minimax, .gemini, .custom:
            if settings.usesAzureAPIKeyHeader {
                request.setValue(settings.token, forHTTPHeaderField: "api-key")
            } else {
                request.setValue("Bearer \(settings.token)", forHTTPHeaderField: "Authorization")
            }
            request.httpBody = try JSONSerialization.data(withJSONObject: llmPayload(paragraph: paragraph, settings: settings))
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "LeafTranslate", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "LLM request failed: \(http.statusCode)\n\(body)"])
        }

        switch settings.provider {
        case .claude:
            return try parseClaudeResponse(data)
        case .deepSeekPro, .deepSeekFlash, .minimax, .gemini, .custom:
            return try parseGenericResponse(data)
        }
    }

    private func llmPayload(paragraph: String, settings: LLMSettings) -> [String: Any] {
        let systemPrompt = "Translate the user's text into \(settings.targetLanguage). Return only the translation."
        if settings.usesResponsesEndpoint {
            return [
                "model": settings.model,
                "instructions": systemPrompt,
                "input": paragraph,
                "max_output_tokens": 2048
            ]
        }

        var payload: [String: Any] = [
            "messages": [
                [
                    "role": "system",
                    "content": systemPrompt
                ],
                [
                    "role": "user",
                    "content": paragraph
                ]
            ],
            "temperature": 0.2
        ]
        if !settings.usesAzureDeploymentEndpoint {
            payload["model"] = settings.model
        }
        return payload
    }

    private func claudePayload(paragraph: String, settings: LLMSettings) -> [String: Any] {
        [
            "model": settings.model,
            "max_tokens": 2048,
            "temperature": 0.2,
            "system": "Translate the user's text into \(settings.targetLanguage). Return only the translation.",
            "messages": [
                [
                    "role": "user",
                    "content": paragraph
                ]
            ]
        ]
    }

    private func parseGenericResponse(_ data: Data) throws -> String {
        let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let outputText = payload?["output_text"] as? String {
            return outputText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let output = payload?["output"] as? [[String: Any]] {
            let text = output.compactMap { item -> String? in
                guard let content = item["content"] as? [[String: Any]] else { return nil }
                return content.compactMap { block in
                    (block["text"] as? String) ?? (block["content"] as? String)
                }.joined()
            }.joined(separator: "\n")
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        if let choices = payload?["choices"] as? [[String: Any]],
           let message = choices.first?["message"] as? [String: Any],
           let content = message["content"] as? String {
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        throw NSError(domain: "LeafTranslate", code: 3, userInfo: [NSLocalizedDescriptionKey: "Unable to parse LLM response."])
    }

    private func parseClaudeResponse(_ data: Data) throws -> String {
        let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let content = payload?["content"] as? [[String: Any]] {
            let text = content.compactMap { item -> String? in
                guard item["type"] as? String == "text" else { return nil }
                return item["text"] as? String
            }.joined(separator: "\n")
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        throw NSError(domain: "LeafTranslate", code: 4, userInfo: [NSLocalizedDescriptionKey: "Unable to parse Claude response."])
    }
}
