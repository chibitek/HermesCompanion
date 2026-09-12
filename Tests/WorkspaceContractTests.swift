import XCTest
@testable import HermesCompanion

final class WorkspaceContractTests: XCTestCase {
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
