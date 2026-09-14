import XCTest
@testable import HermesCompanion

final class WorkspaceContractTests: XCTestCase {
    func testBoardCreationNormalizesNativeSlugAndRejectsInvalidPaths() throws {
        var payload = ServerBoardWrite()
        payload.slug = " Engineering_2 "
        XCTAssertEqual(try payload.validatedCreation().slug, "engineering_2")
        for slug in ["", "../escape", "_hidden", "with spaces", String(repeating: "a", count: 65)] {
            payload.slug = slug
            XCTAssertThrowsError(try payload.validatedCreation())
        }
        payload = ServerBoardWrite()
        payload.description = "Changed description"
        let fields = try JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as! [String: Any]
        XCTAssertEqual(Set(fields.keys), ["description"], "Unchanged board fields must not overwrite desktop edits")
    }

    func testConnectionConfigRejectsDemoAndEmptyGatewayConfigurations() {
        XCTAssertFalse(ConnectionConfig(baseURL: "demo://local", apiKey: "demo", label: "Demo").isValid)
        XCTAssertFalse(ConnectionConfig(baseURL: "", apiKey: "secret", label: "Hermes").isValid)
        XCTAssertFalse(ConnectionConfig(baseURL: "https://hermes.local:8642", apiKey: "", label: "Hermes").isValid)
        XCTAssertTrue(ConnectionConfig(baseURL: "https://hermes.local:8642", apiKey: "secret", label: "Hermes").isValid)
    }

    func testAttachmentNamesCannotEscapeDownloadDirectory() throws {
        for (name, expected) in [("../../report.txt", "report.txt"), ("C:\\private\\report.txt", "report.txt"), ("..", "attachment"), ("", "attachment")] {
            let data = try JSONSerialization.data(withJSONObject: ["id": 1, "task_id": "task", "filename": name, "size": 10])
            let attachment = try JSONDecoder().decode(ServerTaskAttachment.self, from: data)
            XCTAssertEqual(attachment.safeFilename, expected)
        }
    }

    func testTaskRejectsForeignAttachmentMetadata() throws {
        let data = Data(#"{"board":"board","task":{"id":"task","title":"Task","status":"done"},"comments":[],"runs":[],"attachments":[{"id":1,"task_id":"foreign","filename":"report.txt","size":10}]}"#.utf8)
        let detail = try JSONDecoder().decode(ServerTaskDetail.self, from: data)
        XCTAssertFalse(detail.matches(board: "board", taskID: "task"))
    }

    func testTaskHierarchyPreservesLinksAndRejectsUnlinkedChildResults() throws {
        let payload: [String: Any] = [
            "board": "engineering", "task": ["id": "parent", "title": "Parent", "status": "running"],
            "comments": [], "runs": [], "links": ["parents": ["dependency"], "children": ["child"]],
            "child_results": [["id": "child", "title": "Child", "status": "done", "latest_summary": "Full child summary", "result": "Child output"]]
        ]
        let detail = try JSONDecoder().decode(ServerTaskDetail.self, from: JSONSerialization.data(withJSONObject: payload))
        XCTAssertTrue(detail.matches(board: "engineering", taskID: "parent"))
        XCTAssertEqual(detail.links?.parents, ["dependency"])
        XCTAssertEqual(detail.child_results?.first?.result, "Child output")
        var invalid = payload
        invalid["links"] = ["parents": [], "children": []]
        let unlinked = try JSONDecoder().decode(ServerTaskDetail.self, from: JSONSerialization.data(withJSONObject: invalid))
        XCTAssertFalse(unlinked.matches(board: "engineering", taskID: "parent"))
    }

    func testProjectHistoryValidatesOwnerAndAllowsServerResolvedResume() throws {
        let data = Data(#"{"project_id":"project","requested_session_id":"original","history":{"profile":"assistant","session_id":"resumed","messages":[],"pagination":{"offset":100,"limit":100,"returned":0}}}"#.utf8)
        let result = try JSONDecoder().decode(ProjectSessionHistory.self, from: data)
        XCTAssertTrue(result.matches(profile: "assistant", projectID: "project", sessionID: "original", offset: 100))
        XCTAssertFalse(result.matches(profile: "default", projectID: "project", sessionID: "original", offset: 100))
        XCTAssertFalse(result.matches(profile: "assistant", projectID: "other", sessionID: "original", offset: 100))
        XCTAssertFalse(result.matches(profile: "assistant", projectID: "project", sessionID: "other", offset: 100))
        XCTAssertFalse(result.matches(profile: "assistant", projectID: "project", sessionID: "original", offset: 0))
    }

    func testRefreshedBotRosterDoesNotSubstituteOrRetainRemovedProfile() throws {
        let data = Data(#"{"profiles":[{"name":"local","display_name":"Local","model":"updated-model","provider":"custom","last_session":{"id":"unrelated","title":"Other conversation"},"canonical_session":null}]}"#.utf8)
        let snapshot = try JSONDecoder().decode(WorkspaceBots.self, from: data)
        XCTAssertEqual(snapshot.profile(named: "local")?.model, "updated-model")
        XCTAssertNil(snapshot.profile(named: "local")?.canonical_session)
        XCTAssertNil(snapshot.profile(named: "removed"))
        XCTAssertNil(snapshot.profile(named: "Local"))
        let removed = try JSONDecoder().decode(WorkspaceBots.self, from: Data(#"{"profiles":[]}"#.utf8))
        XCTAssertNil(removed.profile(named: "local"))
    }

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
