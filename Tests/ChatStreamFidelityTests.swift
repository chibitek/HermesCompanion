import XCTest
@testable import HermesCompanion

final class ChatStreamFidelityTests: XCTestCase {
    @MainActor
    private func store() -> AppStore {
        AppStore(client: HermesAPIClient(config: ConnectionConfig(
            baseURL: "https://hermes.invalid", apiKey: "", label: "Test")))
    }

    private func event(_ type: String, _ fields: [String: String]) throws -> SSEEventPayload {
        var parser = SSEParser()
        _ = try parser.consume("event: \(type)")
        let data = try JSONSerialization.data(withJSONObject: fields)
        _ = try parser.consume("data: " + String(decoding: data, as: UTF8.self))
        return try XCTUnwrap(parser.finish())
    }

    @MainActor
    func testLiveTextRetainsEverySpaceNewlineAndIndentation() async throws {
        let store = store()
        let chunks = ["Right", " ", "now", "\n\n", "```python", "\n", "def run():", "\n    ", "return", " ", "42", "\n", "```", "\n"]
        var expected = ""
        for chunk in chunks {
            expected += chunk
            _ = await store.handleSSEEvent(try event("assistant.delta", ["delta": chunk]))
            XCTAssertEqual(store.streamingText, expected, "Live output must not depend on token boundaries")
        }
        let completed = await store.handleSSEEvent(try event("assistant.completed", ["message_id": "answer"]))
        XCTAssertEqual(completed?.content, expected)
        XCTAssertEqual(store.messages.last?.content, expected)
    }

    @MainActor
    func testJSONAndLiteralMarkupRemainTheActualAssistantAnswer() async throws {
        for answer in [#"{"score":100,"valid":true}"#, #"{"content":"keep this envelope"}"#, "Explain <think>example</think> markup.", "  indented answer\n"] {
            let store = store()
            _ = await store.handleSSEEvent(try event("assistant.delta", ["delta": answer]))
            XCTAssertEqual(store.streamingText, answer)
            let completed = await store.handleSSEEvent(try event("assistant.completed", ["content": answer, "message_id": "answer"]))
            XCTAssertEqual(completed?.content, answer)
        }
    }

    @MainActor
    func testReasoningChannelIsSeparateAndRunCompletionKeepsUncommittedText() async throws {
        let store = store()
        _ = await store.handleSSEEvent(try event("assistant.delta", ["delta": "reasoning", "tool_name": "_thinking"]))
        XCTAssertEqual(store.streamingThinking, "reasoning")
        XCTAssertEqual(store.streamingText, "")
        _ = await store.handleSSEEvent(try event("assistant.delta", ["delta": "Visible answer\n"]))
        _ = await store.handleSSEEvent(try event("run.completed", [:]))
        XCTAssertEqual(store.streamingText, "Visible answer\n", "The send pipeline must still be able to save the final text")
    }
}
