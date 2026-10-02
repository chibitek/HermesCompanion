import XCTest
@testable import HermesCompanion

final class ChatHistoryVisibilityTests: XCTestCase {
    func testAssistantCommentaryAndToolNamesSurviveHistoryProjection() throws {
        let data = Data(#"{"id":701,"role":"assistant","content":"I found the issue. Reading the page next.","tool_calls":[{"id":"call_one","type":"function","function":{"name":"read_file","arguments":"{\"path\":\"page.tsx\"}"}}]}"#.utf8)
        let message = try JSONDecoder().decode(SessionMessage.self, from: data)
        let visible = ChatDisplayMessage(from: message)
        XCTAssertTrue(visible.shouldDisplay)
        XCTAssertEqual(visible.content, "I found the issue. Reading the page next.")
        XCTAssertEqual(visible.toolNames, ["read_file"])
        let toolOnly = try JSONDecoder().decode(SessionMessage.self, from: Data(#"{"id":702,"role":"assistant","content":null,"tool_calls":[{"function":{"name":"patch"}}]}"#.utf8))
        XCTAssertTrue(ChatDisplayMessage(from: toolOnly).shouldDisplay)
        XCTAssertEqual(ChatDisplayMessage(from: toolOnly).toolNames, ["patch"])
    }

    func testJSONAnswersAreVisibleWhileServerHiddenRowsAndRawToolOutputStayHidden() throws {
        for (role, kind, content, expected) in [
            ("assistant", "", "{\"total\":5}", true),
            ("assistant", "hidden", "Internal transcript record", false),
            ("user", "hidden", "Internal user projection", false),
            ("tool", "", "Raw tool output", false),
            ("assistant", "", "", false)
        ] {
            let data = try JSONSerialization.data(withJSONObject: ["id": 1, "role": role, "display_kind": kind, "content": content])
            let message = try JSONDecoder().decode(SessionMessage.self, from: data)
            XCTAssertEqual(ChatDisplayMessage(from: message).shouldDisplay, expected)
            let roundTrip = try JSONDecoder().decode(SessionMessage.self, from: JSONEncoder().encode(message))
            XCTAssertEqual(roundTrip.displayKind, kind)
        }
    }
}
