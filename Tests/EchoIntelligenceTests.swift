import XCTest

final class EchoIntelligenceTests: XCTestCase {
    func testOfflinePolicyNeverAdmitsCloudProviders() {
        var settings = AISettings(); settings.cloudConsent = true
        for provider in [AIProviderID.openAI, .gemini, .custom] { XCTAssertFalse(AIPolicy.mayConnect(provider, settings: settings)) }
        XCTAssertTrue(AIPolicy.mayConnect(.apple, settings: settings))
        settings.offlineOnly = false; settings.cloudConsent = false
        XCTAssertFalse(AIPolicy.mayConnect(.openAI, settings: settings))
        settings.cloudConsent = true
        XCTAssertTrue(AIPolicy.mayConnect(.openAI, settings: settings))
    }
    func testPermissionModesAndSensitiveConfirmation() throws {
        XCTAssertThrowsError(try AIPolicy.requiresConfirmation(mutating: true, sensitive: false, mode: .chatOnly))
        XCTAssertFalse(try AIPolicy.requiresConfirmation(mutating: false, sensitive: false, mode: .chatOnly))
        XCTAssertTrue(try AIPolicy.requiresConfirmation(mutating: true, sensitive: false, mode: .ask))
        XCTAssertFalse(try AIPolicy.requiresConfirmation(mutating: true, sensitive: false, mode: .full))
        XCTAssertTrue(try AIPolicy.requiresConfirmation(mutating: true, sensitive: true, mode: .full))
    }
    func testEndpointCannotSmuggleCredentialsOrUsePlainHTTP() throws {
        XCTAssertEqual(try AIPolicy.endpoint("https://example.com/v1").path, "/v1")
        for value in ["http://example.com", "file:///etc/passwd", "https://user:secret@example.com", "https://example.com?key=secret", "https://example.com#fragment", "no url"] {
            XCTAssertThrowsError(try AIPolicy.endpoint(value), value)
        }
    }
    func testStrictToolValidationRejectsInjectionAndWrongTypes() throws {
        XCTAssertThrowsError(try EchoToolRegistry.definition("run_shell"))
        let seek = try EchoToolRegistry.definition("seek")
        XCTAssertThrowsError(try seek.validate("{\"seconds\":true}"))
        XCTAssertThrowsError(try seek.validate("{\"seconds\":-1}"))
        XCTAssertThrowsError(try seek.validate("{\"seconds\":90000}"))
        XCTAssertThrowsError(try seek.validate("{\"seconds\":1,\"shell\":\"delete\"}"))
        XCTAssertThrowsError(try seek.validate("{}"))
        XCTAssertNoThrow(try seek.validate("{\"seconds\":0.5}"))
        let favorite = try EchoToolRegistry.definition("favorite")
        XCTAssertThrowsError(try favorite.validate("{\"songID\":\"x\",\"enabled\":1}"))
        let search = try EchoToolRegistry.definition("library_search")
        XCTAssertThrowsError(try search.validate("{\"limit\":1.5}"))
        XCTAssertThrowsError(try search.validate("{\"sort\":\"shell\"}"))
    }
    func testToolLimitsAndRegistryIntegrity() throws {
        XCTAssertEqual(Set(EchoToolRegistry.all.map(\.name)).count, EchoToolRegistry.all.count)
        let play = try EchoToolRegistry.definition("play_songs")
        let data = try JSONSerialization.data(withJSONObject: ["songIDs": Array(repeating: "id", count: 101)])
        XCTAssertThrowsError(try play.validate(String(decoding: data, as: UTF8.self)))
        XCTAssertTrue(try EchoToolRegistry.definition("playlist_delete").sensitive)
        XCTAssertFalse(EchoToolRegistry.all.contains { $0.name.contains("permission") || $0.name.contains("credential") })
        for definition in EchoToolRegistry.all { XCTAssertTrue(JSONSerialization.isValidJSONObject(definition.wire)) }
    }
    func testSSECommentsMultilineAndFinalEvent() {
        var decoder = AISSEDecoder()
        XCTAssertNil(decoder.append(": keepalive"))
        XCTAssertNil(decoder.append("event: message"))
        XCTAssertNil(decoder.append("data: first"))
        XCTAssertNil(decoder.append("data: second"))
        XCTAssertEqual(decoder.append(""), "first\nsecond")
        XCTAssertNil(decoder.append(""))
        XCTAssertNil(decoder.append("data: [DONE]"))
        XCTAssertEqual(decoder.finish(), "[DONE]")
        XCTAssertNil(decoder.finish())
    }
    func testConversationRoundTripPreservesToolLinks() throws {
        let call = AIToolCall(id: "call1", name: "seek", arguments: "{\"seconds\":5}")
        var conversation = AIConversation()
        conversation.messages = [AIMessage(role: .user, text: "Seek"), AIMessage(role: .assistant, text: "", toolCalls: [call]), AIMessage(role: .tool, text: "done", toolCallID: call.id)]
        let restored = try JSONDecoder().decode(AIConversation.self, from: JSONEncoder().encode(conversation))
        XCTAssertEqual(restored.messages, conversation.messages)
        XCTAssertEqual(restored.title, "Seek")
    }
}
