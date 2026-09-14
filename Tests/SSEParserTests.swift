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
        XCTAssertEqual(try parser.consume("")?.event, "message.started")
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
}
