import Foundation
import Observation
import Security

@MainActor @Observable final class AISettingsStore {
    static let enabledKey = "echo.intelligence.enabled.v1"
    static let shared = AISettingsStore()
    var value: AISettings { didSet { if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: "echo.intelligence.settings.v1") } } }
    init() {
        value = UserDefaults.standard.data(forKey: "echo.intelligence.settings.v1")
            .flatMap { try? JSONDecoder().decode(AISettings.self, from: $0) } ?? AISettings()
    }
}
/// Separate service namespace; errors are surfaced instead of pretending credentials were saved.
enum AICredentials {
    static func read(_ provider: AIProviderID) -> String? {
        var query = base(provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func save(_ text: String, provider: AIProviderID) throws {
        let query = base(provider)
        if text.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw AIError.storage }
            return
        }
        let values = [kSecValueData as String: Data(text.utf8)]
        var status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            var attributes = query.merging(values) { _, new in new }
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(attributes as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw AIError.storage }
    }
    private static func base(_ provider: AIProviderID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.echomusic.intelligence", kSecAttrAccount as String: provider.rawValue]
    }
}
@MainActor @Observable final class AIHistoryStore {
    static let shared = AIHistoryStore()
    private(set) var conversations: [AIConversation] = []
    private(set) var actions: [AIActionRecord] = []
    var error: String?
    @ObservationIgnored private var deletedConversationIDs: Set<UUID> = []
    private let directory: URL
    private struct Archive: Codable { var conversations: [AIConversation]; var actions: [AIActionRecord] }
    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Intelligence")
        let directory = self.directory
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var url = directory
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            try url.setResourceValues(values)
            let file = directory.appendingPathComponent("history.json")
            if FileManager.default.fileExists(atPath: file.path) {
                let archive = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: file))
                conversations = archive.conversations; actions = archive.actions
            }
        } catch { self.error = AIError.storage.localizedDescription }
    }
    func save(_ conversation: AIConversation) {
        guard AISettingsStore.shared.value.saveHistory, !conversation.messages.isEmpty, !deletedConversationIDs.contains(conversation.id) else { return }
        var conversation = conversation
        for index in conversation.messages.indices where conversation.messages[index].role == .assistant {
            conversation.messages[index].text = AIResponseText.visible(conversation.messages[index].text)
        }
        conversations.removeAll { $0.id == conversation.id }
        conversations.insert(conversation, at: 0)
        conversations = Array(conversations.prefix(50)); persist()
    }
    func record(_ record: AIActionRecord) { actions.insert(record, at: 0); actions = Array(actions.prefix(200)); persist() }
    func delete(_ id: UUID) { deletedConversationIDs.insert(id); conversations.removeAll { $0.id == id }; persist() }
    func clear() { deletedConversationIDs.formUnion(conversations.map(\.id)); conversations.removeAll(); actions.removeAll(); persist() }
    private func persist() {
        do {
            let data = try JSONEncoder().encode(Archive(conversations: conversations, actions: actions))
            try data.write(to: directory.appendingPathComponent("history.json"), options: [.atomic, .completeFileProtection])
        } catch { self.error = AIError.storage.localizedDescription }
    }
}
