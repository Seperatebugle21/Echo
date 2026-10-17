import Foundation

enum AIProviderID: String, Codable, CaseIterable, Identifiable {
    case automatic, apple, qwen, openAI, gemini, custom
    var id: String { rawValue }
    var key: String { "ai_provider_" + rawValue }
    var isOnline: Bool { [.openAI, .gemini, .custom].contains(self) }
}
enum AIPermission: String, Codable, CaseIterable, Identifiable {
    case chatOnly, ask, full
    var id: String { rawValue }
    var key: String { "ai_permission_" + rawValue }
}
enum UniversePhase: Float { case idle, listening, thinking, speaking, executing, success, failure }
struct AIMessage: Codable, Identifiable, Equatable {
    enum Role: String, Codable { case user, assistant, tool }
    var id = UUID()
    var role: Role
    var text: String
    var date = Date()
    var toolCalls: [AIToolCall] = []
    var toolCallID: String? = nil
}
struct AIConversation: Codable, Identifiable {
    var id = UUID()
    var messages: [AIMessage] = []
    var updatedAt = Date()
    var title: String { String(messages.first(where: { $0.role == .user })?.text.prefix(70) ?? "") }
}
struct AIToolCall: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var arguments: String
}
struct AIActionRecord: Codable, Identifiable {
    var id = UUID()
    var date = Date()
    var name: String
    var result: String
}
enum AIError: Error, LocalizedError {
    case unavailable, offline, credentials, invalidArguments, invalidEndpoint, response, limit, permission, missing, playback, storage, voice, localModel, http(Int)
    var errorDescription: String? {
        let key: String
        switch self {
        case .http(let status): return EchoLocalization.string("ai_error_http") + " (\(status))"
        case .unavailable: key = "unavailable"
        case .offline: key = "offline"
        case .credentials: key = "credentials"
        case .invalidArguments: key = "arguments"
        case .invalidEndpoint: key = "endpoint"
        case .response: key = "response"
        case .limit: key = "limit"
        case .permission: key = "permission"
        case .missing: key = "missing"
        case .playback: key = "playback"
        case .storage: key = "storage"
        case .voice: key = "voice"
        case .localModel: key = "local"
        }
        return EchoLocalization.string("ai_error_" + key)
    }
}
struct AISettings: Codable, Equatable {
    var provider: AIProviderID = .automatic
    var offlineOnly = true
    var permission: AIPermission = .ask
    var cloudConsent = false
    var openAIModel = "gpt-4.1-mini"
    var geminiModel = "gemini-2.5-flash"
    var customURL = ""
    var customModel = ""
    var voiceInput = false
    var spokenResponses = false
    var voiceID = ""
    var speechBehavior = "mix"
    var intensity = 0.45
    var quality = "automatic"
    var autoRotate = true
    var saveHistory = true
}
/// Pure policy used at request dispatch AND immediately before each mutation.
enum AIPolicy {
    static func mayConnect(_ provider: AIProviderID, settings: AISettings) -> Bool {
        !provider.isOnline || (!settings.offlineOnly && settings.cloudConsent)
    }
    static func requiresConfirmation(mutating: Bool, sensitive: Bool, mode: AIPermission) throws -> Bool {
        if mutating && mode == .chatOnly { throw AIError.permission }
        return mutating && (mode == .ask || sensitive)
    }
    static func endpoint(_ value: String) throws -> URL {
        guard let url = URL(string: value), url.scheme == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { throw AIError.invalidEndpoint }
        return url
    }
}
/// SSE events can contain comments and multiple data lines; finish also handles an unterminated last event.
struct AISSEDecoder {
    private var lines: [String] = []
    mutating func append(_ line: String) -> String? {
        if line.isEmpty { return finish() }
        if line.hasPrefix("data:") { lines.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)) }
        return nil
    }
    mutating func finish() -> String? {
        guard !lines.isEmpty else { return nil }
        defer { lines.removeAll(keepingCapacity: true) }
        return lines.joined(separator: "\n")
    }
}
