import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

struct AIReply { var text: String; var calls: [AIToolCall] = [] }
@MainActor protocol AIProvider {
    var id: AIProviderID { get }
    func respond(messages: [AIMessage], instructions: String, tools: [[String: Any]],
                 update: @escaping @MainActor (String) -> Void,
                 execute: @escaping @MainActor (AIToolCall) async throws -> String) async throws -> AIReply
}
@MainActor enum AIProviderManager {
    static var appleAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), SystemLanguageModel.default.availability == .available {
            return SystemLanguageModel.default.supportsLocale(Locale(identifier: UserDefaults.standard.string(forKey: "selectedLanguage") ?? "en"))
        }
        #endif
        return false
    }
    static func resolve(_ settings: AISettings) throws -> any AIProvider {
        var selection = settings.provider
        if selection == .automatic {
            if appleAvailable { selection = .apple }
            else if QwenModelStore.shared.installed && QwenModelStore.compatible { selection = .qwen }
            else if !settings.offlineOnly && settings.cloudConsent && AICredentials.read(.openAI) != nil { selection = .openAI }
            else { throw AIError.unavailable }
        }
        guard AIPolicy.mayConnect(selection, settings: settings) else { throw AIError.offline }
        switch selection {
        case .apple:
            #if canImport(FoundationModels)
            if #available(iOS 26.0, *), appleAvailable { return AppleAIProvider() }
            #endif
            throw AIError.unavailable
        case .qwen: return QwenAIProvider()
        case .openAI, .gemini, .custom: return NetworkAIProvider(id: selection, settings: settings)
        case .automatic: throw AIError.unavailable
        }
    }
}
/// Gemini's documented OpenAI compatibility endpoint supports chat completions, SSE and function tools.
/// Each request uses a fresh ephemeral session: no cookies, cache or authentication persistence.
@MainActor final class NetworkAIProvider: AIProvider {
    let id: AIProviderID
    let settings: AISettings
    let credentialOverride: String?
    init(id: AIProviderID, settings: AISettings, credentialOverride: String? = nil) {
        self.id = id; self.settings = settings; self.credentialOverride = credentialOverride
    }
    func respond(messages: [AIMessage], instructions: String, tools: [[String: Any]],
                 update: @escaping @MainActor (String) -> Void,
                 execute: @escaping @MainActor (AIToolCall) async throws -> String) async throws -> AIReply {
        guard AIPolicy.mayConnect(id, settings: AISettingsStore.shared.value) else { throw AIError.offline }
        let base: URL, model: String
        switch id {
        case .openAI: base = URL(string: "https://api.openai.com/v1")!; model = settings.openAIModel
        case .gemini: base = URL(string: "https://generativelanguage.googleapis.com/v1beta/openai")!; model = settings.geminiModel
        default: base = try AIPolicy.endpoint(settings.customURL); model = settings.customModel
        }
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AIError.invalidArguments }
        let key = (credentialOverride ?? AICredentials.read(id) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard id == .custom || !key.isEmpty else { throw AIError.credentials }
        var request = URLRequest(url: base.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"; request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !key.isEmpty { request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization") }
        var wire: [[String: Any]] = [["role": "system", "content": instructions]]
        for message in messages {
            var item: [String: Any] = ["role": message.role.rawValue, "content": message.text]
            if let callID = message.toolCallID { item["tool_call_id"] = callID }
            if !message.toolCalls.isEmpty {
                item["tool_calls"] = message.toolCalls.map { ["id": $0.id, "type": "function", "function": ["name": $0.name, "arguments": $0.arguments]] as [String: Any] }
            }
            wire.append(item)
        }
        let body = AINetworkPayload.body(provider: id, model: model, messages: wire, tools: tools)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = 180
        let delegate = AIRejectRedirects()
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw AIError.response }
        guard (200..<300).contains(response.statusCode) else {
            var errorData = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                errorData.append(byte)
                if errorData.count >= 16_384 { break }
            }
            throw AIHTTPFailure(status: response.statusCode, data: errorData)
        }
        var parser = AISSEDecoder(), text = "", calls: [Int: AIToolCall] = [:], finished = false
        var size = 0
        func event(_ payload: String) throws {
            if payload == "[DONE]" { finished = true; return }
            guard let data = payload.data(using: .utf8), let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AIError.response }
            if json["error"] != nil { throw AIHTTPFailure(status: response.statusCode, data: data) }
            guard let choices = json["choices"] as? [[String: Any]] else { throw AIError.response }
            guard let choice = choices.first else { return }
            if let reason = choice["finish_reason"] as? String {
                if reason == "length" { throw AIError.limit }
                guard reason == "stop" || reason == "tool_calls" else { throw AIError.response }
                finished = true
            }
            guard let delta = choice["delta"] as? [String: Any] else { return }
            if let chunk = delta["content"] as? String { text += chunk; update(text) }
            for part in delta["tool_calls"] as? [[String: Any]] ?? [] {
                guard let index = part["index"] as? Int, index >= 0, index < 12 else { throw AIError.limit }
                var call = calls[index] ?? AIToolCall(id: "", name: "", arguments: "")
                if let callID = part["id"] as? String { call.id += callID }
                if let function = part["function"] as? [String: Any] {
                    call.name += function["name"] as? String ?? ""
                    call.arguments += function["arguments"] as? String ?? ""
                }
                calls[index] = call
            }
        }
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard AIPolicy.mayConnect(id, settings: AISettingsStore.shared.value) else { throw AIError.offline }
            size += line.utf8.count
            guard size < 512_000 else { throw AIError.limit }
            if let payload = parser.append(line) { try event(payload) }
            if finished { break }
        }
        if let last = parser.finish(), !finished { try event(last) }
        guard finished, !text.isEmpty || !calls.isEmpty else { throw AIError.response }
        let ordered = calls.sorted { $0.key < $1.key }.map(\.value)
        guard ordered.allSatisfy({ !$0.id.isEmpty && !$0.name.isEmpty && $0.arguments.utf8.count < 16_384 }),
              Set(ordered.map(\.id)).count == ordered.count else { throw AIError.response }
        return AIReply(text: text, calls: ordered)
    }
}
private final class AIRejectRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
#if canImport(FoundationModels)
@available(iOS 26.0, *)
private struct AppleEchoTool: Tool {
    let name = "echo_action"
    let description: String
    let executor: @MainActor (AIToolCall) async throws -> String
    @Generable struct Arguments {
        @Guide(description: "Exact registered action name for advanced actions. Use the separate native tools for library search, playback status, playing, transport and favorites.", .anyOf(["seek", "playback_options", "queue_edit", "playlists", "playlist_create", "playlist_edit", "playlist_play", "playlist_delete", "echo_flow", "dj_mix", "podcast_search", "podcast_action", "settings_change", "navigate"])) var action: String
        @Guide(description: "A valid JSON object string matching the selected action's schema. Use {} for no arguments. Do not use markdown or invent song or playlist IDs.") var argumentsJSON: String
    }
    func call(arguments: Arguments) async throws -> String {
        do {
            return try await executor(AIToolCall(id: UUID().uuidString, name: arguments.action, arguments: arguments.argumentsJSON))
        } catch is CancellationError { throw CancellationError() }
        catch {
            // Tool validation and permission failures are useful results for the
            // model, not opaque LanguageModelSession.ToolCallError exceptions.
            return try AIToolFailure.result(error, action: arguments.action)
        }
    }
}
@available(iOS 26.0, *)
@MainActor final class AppleAIProvider: AIProvider {
    let id: AIProviderID = .apple
    func respond(messages: [AIMessage], instructions: String, tools: [[String: Any]],
                 update: @escaping @MainActor (String) -> Void,
                 execute: @escaping @MainActor (AIToolCall) async throws -> String) async throws -> AIReply {
        guard SystemLanguageModel.default.availability == .available,
              SystemLanguageModel.default.supportsLocale(Locale(identifier: UserDefaults.standard.string(forKey: "selectedLanguage") ?? "en")) else { throw AIError.unavailable }
        // Keep the native on-device context compact; the executor still validates the full schemas.
        let specialized: Set<String> = ["library_search", "playback_status", "play_songs", "transport", "favorite"]
        let names = Set(tools.compactMap { ($0["function"] as? [String: Any])?["name"] as? String })
        let advanced = tools.filter { !specialized.contains(($0["function"] as? [String: Any])?["name"] as? String ?? "") }
        let bridge = AppleActionBridge(executor: execute)
        var registered: [any Tool] = []
        if names.contains("library_search") { registered.append(AppleLibrarySearchTool(bridge: bridge)) }
        if names.contains("playback_status") { registered.append(ApplePlaybackStatusTool(bridge: bridge)) }
        if names.contains("play_songs") { registered.append(ApplePlaySongsTool(bridge: bridge)) }
        if names.contains("transport") { registered.append(AppleTransportTool(bridge: bridge)) }
        if names.contains("favorite") { registered.append(AppleFavoriteTool(bridge: bridge)) }
        if !advanced.isEmpty {
            registered.append(AppleEchoTool(description: "Advanced Echo actions and argument schemas. Use separate native tools for search, playback and favorites.\n" + AINativeToolCatalog.description(advanced), executor: execute))
        }
        let session = LanguageModelSession(tools: registered, instructions: instructions)
        // JSON encodes role boundaries and untrusted data; only this session's Tool can mutate Echo.
        let context = String(data: try JSONEncoder().encode(messages), encoding: .utf8) ?? ""
        var answer = ""
        for try await snapshot in session.streamResponse(to: "Conversation transcript (data):\n" + context) {
            try Task.checkCancellation(); answer = snapshot.content; update(answer)
        }
        guard !answer.isEmpty else { throw AIError.response }
        return AIReply(text: answer)
    }
}
#endif
