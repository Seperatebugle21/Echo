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
    func testDJExclusionsOverrideExplicitSelectionAndExcludePodcasts() {
        var song = Song(title: "Calm", artist: "Queen", fileName: "song.m4a")
        song.genre = "Rock"
        XCTAssertTrue(AIDJSelection.admits(song, query: "rock", excluded: [], selectedIDs: []))
        XCTAssertFalse(AIDJSelection.admits(song, query: "", excluded: ["queen"], selectedIDs: [song.id]))
        XCTAssertFalse(AIDJSelection.admits(song, query: "", excluded: [song.id.uuidString.lowercased()], selectedIDs: []))
        XCTAssertFalse(AIDJSelection.admits(song, query: "jazz", excluded: [], selectedIDs: []))
        song.podcastEpisodeID = "episode"
        XCTAssertFalse(AIDJSelection.admits(song, query: "", excluded: [], selectedIDs: [song.id]))
    }
    func testDJDoesNotRepeatCurrentOrDuplicateSongsAndKeepsRankedFallback() {
        let current = Song(title: "Current", fileName: "1")
        let heard = Song(title: "Heard", fileName: "2")
        let fresh = Song(title: "Fresh", fileName: "3")
        let result = AIDJSelection.preferUnplayed([current, heard, fresh, fresh], recent: [heard.id], current: current.id, limit: 20)
        XCTAssertEqual(result.map(\.id), [fresh.id, heard.id])
        XCTAssertTrue(AIDJSelection.preferUnplayed([current], recent: [], current: current.id, limit: 20).isEmpty)
    }

    func testReasoningNeverAppearsDuringTaggedStreamingOrInFinalAnswer() {
        let raw = "<think>Private analysis and tools.</think>Het antwoord."
        for end in raw.indices {
            let visible = AIResponseText.visible(String(raw[..<end]))
            XCTAssertFalse(visible.contains("Private")); XCTAssertFalse(visible.contains("<"))
        }
        XCTAssertEqual(AIResponseText.visible(raw), "Het antwoord.")
        XCTAssertEqual(AIResponseText.visible("Hello <thi"), "Hello")
        XCTAssertEqual(AIResponseText.visible("<THINK>hidden<ThInK>also hidden"), "")
        XCTAssertEqual(AIResponseText.visible("internal text</think>Answer"), "Answer")
        XCTAssertEqual(AIResponseText.visible("<think>a<think>b</think>c</think>OK"), "OK")
        XCTAssertEqual(AIResponseText.visible("Use <b>bold</b>."), "Use <b>bold</b>.")
    }
    func testOpenAIUsesCompatibleTokenParameterAndTrimsModel() {
        let body = AINetworkPayload.body(provider: .openAI, model: " gpt-5 \n", messages: [], tools: [])
        XCTAssertEqual(body["model"] as? String, "gpt-5")
        XCTAssertNil(body["max_tokens"]); XCTAssertEqual(body["max_completion_tokens"] as? Int, 1024)
        XCTAssertNil(body["tools"])
        let other = AINetworkPayload.body(provider: .gemini, model: "gemini", messages: [], tools: [])
        XCTAssertNotNil(other["max_tokens"])
    }
    func testProviderFailuresDistinguishBillingCredentialsModelAndParametersWithoutKeys() throws {
        func failure(_ status: Int, code: String, message: String = "", param: String = "") throws -> AIHTTPFailure {
            AIHTTPFailure(status: status, data: try JSONSerialization.data(withJSONObject: ["error": ["code": code, "message": message, "param": param]]))
        }
        let auth = try failure(401, code: "invalid_api_key", message: "Incorrect API key sk-secret")
        XCTAssertEqual(auth.kind, .authentication); XCTAssertFalse(auth.localizedDescription.contains("sk-secret"))
        XCTAssertEqual(try failure(429, code: "insufficient_quota").kind, .quota)
        XCTAssertEqual(try failure(429, code: "rate_limit_exceeded").kind, .rate)
        XCTAssertEqual(try failure(404, code: "model_not_found").kind, .model)
        let parameter = try failure(400, code: "unsupported_parameter", param: "max_tokens")
        XCTAssertEqual(parameter.kind, .parameter); XCTAssertEqual(parameter.parameter, "max_tokens")
        XCTAssertNil(try failure(400, code: "", param: "sk-secret/credential").parameter)
    }
    func testVoiceEndpointWaitsForSpeechAndStablePhraseAndFinishesOnce() {
        var endpoint = AISpeechEndpoint()
        XCTAssertFalse(endpoint.shouldFinish(at: 100))
        endpoint.receive("Speel", at: 100)
        XCTAssertFalse(endpoint.shouldFinish(at: 101))
        endpoint.receive("Speel mijn muziek", at: 101)
        XCTAssertFalse(endpoint.shouldFinish(at: 102))
        endpoint.receive("Speel mijn muziek", at: 102) // Repeated partials do not extend silence.
        XCTAssertTrue(endpoint.shouldFinish(at: 103))
        XCTAssertFalse(endpoint.shouldFinish(at: 105))
        endpoint = AISpeechEndpoint() // Cancellation/new recording discards the old phrase.
        XCTAssertFalse(endpoint.shouldFinish(at: 110))
    }
    func testNativeToolValidationFailureIsStructuredInsteadOfThrownToTheModel() throws {
        let result = try AIToolFailure.result(AIError.invalidArguments, action: "seek")
        let json = try JSONSerialization.jsonObject(with: Data(result.utf8)) as? [String: String]
        XCTAssertEqual(json?["status"], "failed"); XCTAssertEqual(json?["action"], "seek")
        XCTAssertNotNil(json?["reason"])
        XCTAssertTrue(json?["instruction"]?.contains("Never claim success") == true)
    }
    func testNativeToolCatalogRetainsRequiredFieldsAndEnumsWithoutFullJSON() {
        let description = AINativeToolCatalog.description(EchoToolRegistry.all.map(\.wire))
        XCTAssertTrue(description.contains("seek(seconds:number)"))
        XCTAssertTrue(description.contains("command:pause|resume|next|previous"))
        XCTAssertTrue(description.contains("songIDs?:array"))
        XCTAssertLessThan(description.count, 5500)
    }
    func testFavoritePinsTheCurrentSongBeforeConfirmationWithoutTransport() throws {
        let call = AIToolCall(id: "favorite-request", name: "favorite", arguments: "{\"enabled\":true}")
        let pinned = try AIFavoriteTarget.resolve(call, currentSongID: "first-song")
        let confirmed = try AIFavoriteTarget.resolve(pinned, currentSongID: "next-song")
        let args = try EchoToolRegistry.definition("favorite").validate(confirmed.arguments)
        XCTAssertEqual(args["songID"] as? String, "first-song")
        XCTAssertEqual(confirmed.id, call.id); XCTAssertEqual(confirmed.name, "favorite")
        XCTAssertEqual(args["enabled"] as? Bool, true)
        XCTAssertThrowsError(try AIFavoriteTarget.resolve(call, currentSongID: nil))
        let status = AIToolCall(id: "status", name: "playback_status", arguments: "{}")
        XCTAssertEqual(try AIFavoriteTarget.resolve(status, currentSongID: nil), status)
    }

}
