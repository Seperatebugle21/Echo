import XCTest

@MainActor final class EchoIntelligencePersistenceTests: XCTestCase {
    func testDeletingAnOpenConversationCannotResurrectItOnSave() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let settings = AISettingsStore.shared.value
        defer { AISettingsStore.shared.value = settings }
        AISettingsStore.shared.value.saveHistory = true
        let history = AIHistoryStore(directory: directory)
        var conversation = AIConversation()
        conversation.messages = [AIMessage(role: .user, text: "Private question")]
        history.save(conversation)
        XCTAssertEqual(history.conversations.count, 1)
        history.delete(conversation.id)
        history.save(conversation)
        XCTAssertTrue(history.conversations.isEmpty)
        XCTAssertTrue(AIHistoryStore(directory: directory).conversations.isEmpty)
        XCTAssertNil(history.error)
    }
    func testClearHistoryRemovesAuditAndOpenConversation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let settings = AISettingsStore.shared.value
        defer { AISettingsStore.shared.value = settings }
        AISettingsStore.shared.value.saveHistory = true
        let history = AIHistoryStore(directory: directory)
        var conversation = AIConversation()
        conversation.messages = [AIMessage(role: .user, text: "Question")]
        history.save(conversation)
        history.record(AIActionRecord(name: "transport", result: "completed"))
        history.clear()
        history.save(conversation)
        XCTAssertTrue(history.actions.isEmpty)
        XCTAssertTrue(history.conversations.isEmpty)
        let restored = AIHistoryStore(directory: directory)
        XCTAssertTrue(restored.actions.isEmpty)
        XCTAssertTrue(restored.conversations.isEmpty)
    }
    func testSavingDisabledDoesNotWriteNewConversation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let settings = AISettingsStore.shared.value
        defer { AISettingsStore.shared.value = settings }
        AISettingsStore.shared.value.saveHistory = false
        let history = AIHistoryStore(directory: directory)
        var conversation = AIConversation()
        conversation.messages = [AIMessage(role: .user, text: "Do not save")]
        history.save(conversation)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("history.json").path))
        XCTAssertTrue(history.conversations.isEmpty)
    }
    func testHistoryNeverPersistsAssistantReasoningButKeepsUserInput() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let settings = AISettingsStore.shared.value
        defer { AISettingsStore.shared.value = settings }
        AISettingsStore.shared.value.saveHistory = true
        let history = AIHistoryStore(directory: directory)
        var conversation = AIConversation()
        conversation.messages = [AIMessage(role: .user, text: "Explain <think> tags"),
                                 AIMessage(role: .assistant, text: "<think>private reasoning</think>Visible answer")]
        history.save(conversation)
        let restored = AIHistoryStore(directory: directory)
        XCTAssertEqual(restored.conversations.first?.messages[0].text, "Explain <think> tags")
        XCTAssertEqual(restored.conversations.first?.messages[1].text, "Visible answer")
        let data = try Data(contentsOf: directory.appendingPathComponent("history.json"))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("private reasoning"))
    }
}
