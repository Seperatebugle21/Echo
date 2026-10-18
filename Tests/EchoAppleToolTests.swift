import XCTest
#if canImport(FoundationModels)
import FoundationModels

@MainActor final class EchoAppleToolTests: XCTestCase {
    func testTypedFavoriteOnlyCallsFavoriteWithBooleanAndCurrentTarget() async throws {
        var calls: [AIToolCall] = []
        let bridge = AppleActionBridge { call in calls.append(call); return "{\"status\":\"completed\"}" }
        let tool = AppleFavoriteTool(bridge: bridge)
        _ = try await tool.call(arguments: .init(enabled: true, songID: nil))
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.name, "favorite")
        let args = try EchoToolRegistry.definition("favorite").validate(try XCTUnwrap(calls.first?.arguments))
        XCTAssertEqual(args["enabled"] as? Bool, true); XCTAssertNil(args["songID"])
    }
    func testTypedStatusCallsReadOnlyRegistryWithoutInventedJSON() async throws {
        var calls: [AIToolCall] = []
        let bridge = AppleActionBridge { call in calls.append(call); return "{\"current\":{}}" }
        let tool = ApplePlaybackStatusTool(bridge: bridge)
        _ = try await tool.call(arguments: .init(includeUpcoming: true))
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.name, "playback_status")
        XCTAssertNoThrow(try EchoToolRegistry.definition("playback_status").validate(try XCTUnwrap(calls.first?.arguments)))
    }
    func testNativeBridgeReturnsValidationFailureButPropagatesCancellation() async throws {
        let failing = AppleActionBridge { _ in throw AIError.invalidArguments }
        let result = try await AppleFavoriteTool(bridge: failing).call(arguments: .init(enabled: true, songID: nil))
        let json = try JSONSerialization.jsonObject(with: Data(result.utf8)) as? [String: String]
        XCTAssertEqual(json?["status"], "failed")
        XCTAssertEqual(json?["action"], "favorite")
        let cancelled = AppleActionBridge { _ in throw CancellationError() }
        do {
            _ = try await ApplePlaybackStatusTool(bridge: cancelled).call(arguments: .init(includeUpcoming: true))
            XCTFail("Cancellation must stop generation rather than return a recoverable tool result")
        } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
    }
}
#endif
