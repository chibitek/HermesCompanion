import XCTest
@testable import HermesCompanion

final class WorkspaceContractTests: XCTestCase {
    func testTaskDetailRetainsFullTextAndValidatesOwnership() throws {
        let text = String(repeating: "Full result. ", count: 100)
        let payload: [String: Any] = [
            "board": "engineering",
            "task": ["id": "task", "title": "Review", "status": "done", "result": text, "latest_summary": text],
            "comments": [["id": 1, "task_id": "task", "author": "reviewer", "body": text, "created_at": 1]],
            "runs": [["id": 2, "task_id": "task", "status": "completed", "summary": text, "started_at": 1]]
        ]
        let detail = try JSONDecoder().decode(ServerTaskDetail.self, from: JSONSerialization.data(withJSONObject: payload))
        XCTAssertEqual(detail.task.result, text)
        XCTAssertEqual(detail.task.latest_summary, text)
        XCTAssertEqual(detail.comments[0].body, text)
        XCTAssertEqual(detail.runs[0].summary, text)
        XCTAssertTrue(detail.matches(board: "engineering", taskID: "task"))
        XCTAssertFalse(detail.matches(board: "other", taskID: "task"))
        XCTAssertFalse(detail.matches(board: "engineering", taskID: "other"))
        var foreign = payload
        foreign["comments"] = [["id": 1, "task_id": "foreign", "author": "reviewer", "body": text, "created_at": 1]]
        let mismatched = try JSONDecoder().decode(ServerTaskDetail.self, from: JSONSerialization.data(withJSONObject: foreign))
        XCTAssertFalse(mismatched.matches(board: "engineering", taskID: "task"))
    }

    func testBotHistoryPreservesDisplayProjectionAndHidesCompactionInternals() throws {
        let data = Data(#"{"profile":"assistant","session_id":"canonical","messages":[{"id":1,"role":"user","content":"internal summary","display_content":"Original question"},{"id":2,"role":"system","content":"hidden summary","display_kind":"hidden"}],"pagination":{"offset":0,"limit":100,"returned":2}}"#.utf8)
        let history = try JSONDecoder().decode(BotHistory.self, from: data)
        XCTAssertEqual(history.profile, "assistant")
        XCTAssertEqual(history.messages[0].visibleText, "Original question")
        XCTAssertNil(history.messages[1].visibleText)
        XCTAssertEqual(history.pagination.returned, 2)
    }

    func testProjectsKeepProfileOwnershipAndEmptyFolders() throws {
        let data = Data(#"{"groups":[{"profile":"default","projects":[{"id":"same","label":"Empty project","path":null,"sessionCount":0,"repos":[{"id":"repo","label":"Sources","path":"/workspace/sources","groups":[]}]}]},{"profile":"assistant","projects":[{"id":"same","label":"Different project","path":null,"sessionCount":0,"repos":[]}]}],"errors":[]}"#.utf8)
        let snapshot = try JSONDecoder().decode(WorkspaceProjects.self, from: data)
        XCTAssertNotEqual(snapshot.groups[0].id, snapshot.groups[1].id)
        XCTAssertEqual(snapshot.groups[0].projects[0].repos[0].path, "/workspace/sources")
        XCTAssertEqual(snapshot.groups[0].projects[0].sessionCount, 0)
    }

    func testBotsUseAuthoritativeModelAndFallbackName() throws {
        let data = Data(#"{"profiles":[{"name":"local","display_name":"","model":"local-model","provider":"custom","last_session":null,"canonical_session":null}]}"#.utf8)
        let bot = try JSONDecoder().decode(WorkspaceBots.self, from: data).profiles[0]
        XCTAssertEqual(bot.title, "local")
        XCTAssertEqual(bot.model, "local-model")
        XCTAssertEqual(bot.provider, "custom")
    }

    func testKanbanKeepsUnknownServerColumns() throws {
        let data = Data(#"{"columns":[{"name":"needs_approval","tasks":[{"id":"task","title":"Review change","status":"needs_approval","body":null,"assignee":null}]}]}"#.utf8)
        let board = try JSONDecoder().decode(ServerBoardDetail.self, from: data)
        XCTAssertEqual(board.columns[0].name, board.columns[0].tasks[0].status)
    }
}
