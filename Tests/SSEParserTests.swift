import XCTest
@testable import HermesCompanion

final class SSEParserTests: XCTestCase {
    func testByteDecoderDispatchesFramesBeforeEOFIncludingUnicodeAndCRLF() throws {
        var lines = SSELineDecoder()
        var parser = SSEParser()
        let bytes = Data("event: assistant.delta\r\ndata: {\"delta\":\"Hello 世界\"}\r\n\r\nevent: done\ndata: {}\n\n".utf8)
        var events: [SSEEventPayload] = []
        for byte in bytes {
            if let line = try lines.consume(byte), let event = try parser.consume(line) { events.append(event) }
        }
        XCTAssertEqual(events.map(\.event), ["assistant.delta", "done"])
        XCTAssertEqual(events.first?.delta, "Hello 世界")
        XCTAssertNil(try parser.finish())
    }

    func testNestedMessageStartAndMultilineData() throws {
        var parser = SSEParser()
        XCTAssertNil(try parser.consume(": keepalive"))
        XCTAssertNil(try parser.consume("event: message.started\r"))
        XCTAssertNil(try parser.consume("data: {\"message\":\n".trimmingCharacters(in: .newlines)))
        XCTAssertNil(try parser.consume("data: {\"id\":\"message-1\",\"role\":\"assistant\"}}"))
        let event = try XCTUnwrap(parser.consume(""))
        XCTAssertEqual(event.event, "message.started")
        XCTAssertEqual(event.structuredMessage?.id, "message-1")
        XCTAssertEqual(event.structuredMessage?.role, "assistant")
        XCTAssertNil(try parser.finish())
    }

    func testInvalidDeltaFailsExplicitlyInsteadOfLosingText() throws {
        var parser = SSEParser()
        _ = try parser.consume("event: assistant.delta")
        _ = try parser.consume("data: {broken")
        XCTAssertThrowsError(try parser.consume("")) { error in
            XCTAssertTrue(error.localizedDescription.contains("assistant.delta"))
        }
    }

    func testJSONEventNameSurvivesWithoutEventLineAndEOFFlush() throws {
        var parser = SSEParser()
        _ = try parser.consume(#"data: {"event":"assistant.delta","delta":"Hello"}"#)
        let event = try XCTUnwrap(parser.finish())
        XCTAssertEqual(event.event, "assistant.delta")
        XCTAssertEqual(event.delta, "Hello")
    }

    func testPlainErrorAndDoneSentinel() throws {
        var parser = SSEParser()
        _ = try parser.consume("event:error")
        _ = try parser.consume("data:Provider timed out")
        XCTAssertEqual(try parser.consume("")?.message, "Provider timed out")
        _ = try parser.consume("data: [DONE]")
        XCTAssertEqual(try parser.finish()?.event, "done")
    }

    func testStructuredMessageSurvivesWireRoundTrip() throws {
        let data = Data(#"{"event":"message.started","message":{"id":"msg_1","role":"assistant","content":"Keep spaces and \nnewlines"}}"#.utf8)
        let event = try JSONDecoder().decode(SSEEventPayload.self, from: data)
        let encoded = try JSONEncoder().encode(event)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let message = try XCTUnwrap(object["message"] as? [String: String])
        XCTAssertEqual(message["id"], "msg_1")
        XCTAssertEqual(message["role"], "assistant")
        XCTAssertEqual(message["content"], "Keep spaces and \nnewlines")
        XCTAssertNil(event.message, "A chat object must not become an error/progress string")
        XCTAssertEqual(event.structuredMessage?.content, message["content"])
    }

    func testInvalidMessageTypesAreNotSilentlyDiscarded() throws {
        for message in ["42", "true", "[]", #"{"id":42}"#, #"{"role":false}"#, #"{"content":[]}"#] {
            var parser = SSEParser()
            _ = try parser.consume("event: message.started")
            _ = try parser.consume("data: {\"message\":\(message)}")
            XCTAssertThrowsError(try parser.finish(), "Invalid message field: \(message)")
        }
    }

    func testStringAndNullMessageFormsKeepTheirMeaning() throws {
        let event = try JSONDecoder().decode(SSEEventPayload.self, from: Data(#"{"event":"error","message":"Provider unavailable"}"#.utf8))
        XCTAssertEqual(event.message, "Provider unavailable")
        XCTAssertNil(event.structuredMessage)
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(event)) as? [String: Any])
        XCTAssertEqual(encoded["message"] as? String, "Provider unavailable")
        for data in [#"{"event":"run.started"}"#, #"{"event":"run.started","message":null}"#] {
            let event = try JSONDecoder().decode(SSEEventPayload.self, from: Data(data.utf8))
            XCTAssertNil(event.message)
            XCTAssertNil(event.structuredMessage)
        }
    }

    func testParseDiagnosticNamesFieldWithoutExposingPayloadOrUnknownEventName() throws {
        let privateValue = "PAYLOAD_\(UUID().uuidString)"
        var parser = SSEParser()
        _ = try parser.consume("event: \(privateValue)")
        _ = try parser.consume("data: {\"message\":{\"content\":{\"\(privateValue)\":\"\(privateValue)\"}}}")
        XCTAssertThrowsError(try parser.finish()) { error in
            XCTAssertTrue(error.localizedDescription.contains("message.content"))
            XCTAssertTrue(error.localizedDescription.contains("unexpected JSON type"))
            XCTAssertFalse(error.localizedDescription.contains(privateValue))
        }
        #if DEBUG
        let docs = try XCTUnwrap(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first)
        let log = try String(contentsOf: docs.appendingPathComponent("hermes-companion.log"), encoding: .utf8)
        XCTAssertTrue(log.contains("SSEParser: The gateway sent an invalid unrecognized frame. Field 'message.content'"))
        XCTAssertFalse(log.contains(privateValue))
        #endif
    }

    func testWrongDeltaTypeUsesJSONEventNameAndMissingEventKeepsSpecificError() throws {
        var parser = SSEParser()
        _ = try parser.consume(#"data: {"event":"assistant.delta","delta":42}"#)
        XCTAssertThrowsError(try parser.finish()) { error in
            XCTAssertTrue(error.localizedDescription.contains("assistant.delta"))
            XCTAssertTrue(error.localizedDescription.contains("Field 'delta'"))
        }
        _ = try parser.consume(#"data: {"content":"Text without an event"}"#)
        XCTAssertThrowsError(try parser.finish()) { error in
            XCTAssertTrue(error.localizedDescription.contains("omitted the event type"))
        }
    }

    func testJSONErrorStringIsDecodedButInvalidRootTypesAreRejected() throws {
        var parser = SSEParser()
        _ = try parser.consume("event: error")
        _ = try parser.consume(#"data: "Provider unavailable""#)
        XCTAssertEqual(try parser.finish()?.message, "Provider unavailable")
        for body in ["[]", "42", "true"] {
            _ = try parser.consume("event: error")
            _ = try parser.consume("data: \(body)")
            XCTAssertThrowsError(try parser.finish())
        }
    }

    @MainActor
    func testStructuredStartAcknowledgesWithoutInsertingUnconfirmedContent() async throws {
        let store = AppStore(client: HermesAPIClient(config: ConnectionConfig(baseURL: "https://hermes.invalid", apiKey: "", label: "Test")))
        let event = try JSONDecoder().decode(SSEEventPayload.self, from: Data(#"{"event":"message.started","message":{"id":"msg_1","role":"assistant","content":"Unconfirmed text"}}"#.utf8))
        _ = await store.handleSSEEvent(event)
        XCTAssertEqual(store.responseActivity, "Hermes accepted the message")
        XCTAssertTrue(store.messages.isEmpty)
        XCTAssertTrue(store.streamingText.isEmpty)
        XCTAssertEqual(event.structuredMessage?.content, "Unconfirmed text")
    }
}
