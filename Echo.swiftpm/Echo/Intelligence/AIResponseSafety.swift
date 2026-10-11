import Foundation

/// Providers deliver complete snapshots. Hold partial tags back as well as the reasoning
/// itself, so streaming, history and speech all use the same visible answer.
enum AIResponseText {
    static func visible(_ snapshot: String) -> String {
        var output = "", depth = 0, index = snapshot.startIndex
        while index < snapshot.endIndex {
            let end = snapshot.index(index, offsetBy: 8, limitedBy: snapshot.endIndex) ?? snapshot.endIndex
            let remainder = snapshot[index..<end].lowercased()
            if snapshot[index] == "<", remainder.hasPrefix("<think>") {
                depth += 1; index = snapshot.index(index, offsetBy: 7); continue
            }
            if snapshot[index] == "<", remainder.hasPrefix("</think>") {
                // Some templates supply the opening tag themselves. A bare closing
                // tag therefore means the preceding generated text was reasoning.
                if depth == 0 { output = "" } else { depth -= 1 }
                index = snapshot.index(index, offsetBy: 8); continue
            }
            if snapshot[index] == "<", ["<think>", "</think>"].contains(where: { $0.hasPrefix(remainder) }) { break }
            if depth == 0 { output.append(snapshot[index]) }
            index = snapshot.index(after: index)
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum AINetworkPayload {
    static func body(provider: AIProviderID, model: String, messages: [[String: Any]], tools: [[String: Any]]) -> [String: Any] {
        var body: [String: Any] = ["model": model.trimmingCharacters(in: .whitespacesAndNewlines), "messages": messages, "stream": true]
        // OpenAI's reasoning models reject the legacy max_tokens parameter.
        body[provider == .openAI ? "max_completion_tokens" : "max_tokens"] = 2048
        if !tools.isEmpty { body["tools"] = tools }
        return body
    }
}

enum AIToolFailure {
    static func result(_ error: Error, action: String) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: [
            "status": "failed", "action": action, "reason": error.localizedDescription,
            "instruction": "No action was confirmed by this result. Explain the failure. Never claim success. Only correct arguments if allowed; do not retry denied or cancelled actions."
        ])
        return String(decoding: data, as: UTF8.self)
    }
}

enum AINativeToolCatalog {
    static func description(_ tools: [[String: Any]]) -> String {
        tools.compactMap { tool -> String? in
            guard let function = tool["function"] as? [String: Any], let name = function["name"] as? String,
                  let schema = function["parameters"] as? [String: Any], let properties = schema["properties"] as? [String: [String: Any]] else { return nil }
            let required = Set(schema["required"] as? [String] ?? [])
            let arguments = properties.keys.sorted().map { key in
                let field = properties[key] ?? [:]
                let type = (field["enum"] as? [String])?.joined(separator: "|") ?? (field["type"] as? String ?? "string")
                return key + (required.contains(key) ? ":" : "?:") + type
            }.joined(separator: ", ")
            // Keep native tools inside Apple's small context window. Constraints
            // still come from the strict executor, never this compact description.
            let detail = function["description"] as? String ?? ""
            return name + "(" + arguments + ") " + (name == "settings_change" ? detail : String(detail.prefix(90)))
        }.joined(separator: "\n")
    }
}

struct AIHTTPFailure: LocalizedError {
    enum Kind: String { case authentication, forbidden, quota, rate, model, parameter, endpoint, server, other }
    let status: Int
    let kind: Kind
    let parameter: String?
    init(status: Int, data: Data) {
        self.status = status
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let details = json?["error"] as? [String: Any] ?? [:]
        let code = (details["code"] as? String ?? "").lowercased()
        let message = (details["message"] as? String ?? "").lowercased()
        let type = (details["type"] as? String ?? "").lowercased()
        let rawParameter = details["param"] as? String ?? ""
        parameter = rawParameter.range(of: "^[a-zA-Z_][a-zA-Z0-9_.]{0,63}$", options: .regularExpression) == nil ? nil : rawParameter
        if status == 401 || code == "invalid_api_key" { kind = .authentication }
        else if code.contains("quota") || type.contains("quota") || message.contains("billing") || message.contains("credit balance") { kind = .quota }
        else if status == 429 { kind = .rate }
        else if code == "model_not_found" || rawParameter == "model" || message.contains("model does not exist") { kind = .model }
        else if status == 403 { kind = .forbidden }
        else if status == 404 { kind = .endpoint }
        else if status >= 500 { kind = .server }
        else if parameter != nil || code.contains("unsupported") || type == "invalid_request_error" { kind = .parameter }
        else { kind = .other }
    }
    var errorDescription: String? {
        // Do not echo raw provider messages: some include the submitted API key.
        EchoLocalization.string("ai_http_" + kind.rawValue) + " (HTTP \(status))" + (parameter.map { " · \($0)" } ?? "")
    }
}

/// End an utterance after a stable recognized phrase, rather than waiting for
/// Apple's recognizer to end a potentially minute-long recording on its own.
struct AISpeechEndpoint {
    private(set) var text = ""
    private var changedAt: TimeInterval = 0
    private var ended = false
    mutating func receive(_ text: String, at time: TimeInterval) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ended, value != self.text else { return }
        self.text = value; changedAt = time
    }
    mutating func shouldFinish(at time: TimeInterval) -> Bool {
        guard !ended, !text.isEmpty, time - changedAt >= 1.6 else { return false }
        ended = true; return true
    }
}
