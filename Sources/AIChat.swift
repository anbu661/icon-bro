import Foundation

/// "Agentic chat": optional AI chat with the person's own API key.
/// Supports OpenAI, Anthropic (Claude), Google Gemini, or any OpenAI-compatible service.
/// Bro never ships with a key; it's stored only on this Mac (ai.key, readable by this user only).
enum AIProvider: String, CaseIterable {
    case off, openai, anthropic, gemini, custom

    var title: String {
        switch self {
        case .off: return "Off (offline commands only)"
        case .openai: return "OpenAI"
        case .anthropic: return "Anthropic (Claude)"
        case .gemini: return "Google Gemini"
        case .custom: return "Other (OpenAI-compatible)"
        }
    }

    /// Pre-filled model; the person can change it in Settings.
    var defaultModel: String {
        switch self {
        case .off, .custom: return ""
        case .openai: return "gpt-4.1-mini"
        case .anthropic: return "claude-opus-5-5"
        case .gemini: return "gemini-2.5-flash"
        }
    }

    var baseURL: String {
        switch self {
        case .openai: return "https://api.openai.com/v1"
        case .gemini: return "https://generativelanguage.googleapis.com/v1beta/openai"
        default: return ""
        }
    }
}

enum AIChat {
    static var keyURL: URL { supportDir.appendingPathComponent("ai.key") }

    static var apiKey: String? {
        let k = (try? String(contentsOf: keyURL, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (k?.isEmpty ?? true) ? nil : k
    }

    static func saveKey(_ key: String) {
        try? key.trimmingCharacters(in: .whitespacesAndNewlines).write(to: keyURL, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyURL.path)
    }

    static func removeKey() { try? FileManager.default.removeItem(at: keyURL) }

    static func provider(_ config: Config) -> AIProvider { AIProvider(rawValue: config.aiProvider) ?? .off }

    static func isConfigured(_ config: Config) -> Bool {
        let p = provider(config)
        guard p != .off, apiKey != nil else { return false }
        return p != .custom || !config.aiBaseURL.isEmpty
    }

    /// history: ("user" | "assistant", text). Calls back on the main queue with the reply text or an error.
    static func send(system: String, history: [(String, String)], config: Config,
                     done: @escaping (String?, String?) -> Void) {
        let p = provider(config)
        guard let key = apiKey else { return done(nil, "No API key") }
        let model = config.aiModel.isEmpty ? p.defaultModel : config.aiModel
        var req: URLRequest
        var body: [String: Any]

        if p == .anthropic {
            // Messages API (raw HTTPS: there is no official Swift SDK)
            req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
            req.setValue(key, forHTTPHeaderField: "x-api-key")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            req.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
            var msgs = history.map { ["role": $0.0, "content": $0.1] }
            while msgs.first?["role"] == "assistant" { msgs.removeFirst() }      // must start with the user
            body = ["model": model, "max_tokens": 16000, "system": system, "messages": msgs,
                    "output_config": ["effort": "low"],                           // short chat replies: keep it quick
                    "fallbacks": "default"]                                       // a declined request is retried on another Claude model
        } else {
            let base = (p == .custom ? config.aiBaseURL : p.baseURL).trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
            guard let url = URL(string: base + "/chat/completions") else { return done(nil, "Bad base URL") }
            req = URLRequest(url: url)
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            body = ["model": model, "temperature": 0.7,
                    "messages": [["role": "system", "content": system]] + history.map { ["role": $0.0, "content": $0.1] }]
        }
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: req) { data, resp, err in
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            var text: String?
            var problem: String?
            if let err {
                problem = err.localizedDescription
            } else if status != 200 {
                let msg = ((json?["error"] as? [String: Any])?["message"] as? String) ?? "HTTP \(status)"
                problem = msg
            } else if p == .anthropic {
                if json?["stop_reason"] as? String == "refusal" {
                    problem = "The model declined that one."
                } else {
                    let blocks = json?["content"] as? [[String: Any]] ?? []
                    text = blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
                }
            } else {
                let choice = (json?["choices"] as? [[String: Any]])?.first
                text = (choice?["message"] as? [String: Any])?["content"] as? String
            }
            if let t = text, let end = t.range(of: "</think>") { text = String(t[end.upperBound...]) }
            let clean = text?.trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async {
                if let clean, !clean.isEmpty { done(clean, nil) } else { done(nil, problem ?? "Empty reply") }
            }
        }.resume()
    }
}
