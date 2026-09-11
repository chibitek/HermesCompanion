import XCTest
@testable import HermesCompanion

@MainActor
final class ProjectStoreTests: XCTestCase {
    func testCreatesProjectAndAssignsSession() {
        let defaults = isolatedDefaults()
        let store = ProjectStore(defaults: defaults)

        let project = store.createProject(name: "Chibitek Labs")
        store.assign(sessionID: "session-1", to: project.id)

        XCTAssertEqual(store.project(for: "session-1")?.name, "Chibitek Labs")
        XCTAssertEqual(store.sessionIDs(in: project.id), ["session-1"])
    }

    func testChangingProjectMovesSession() {
        let defaults = isolatedDefaults()
        let store = ProjectStore(defaults: defaults)
        let first = store.createProject(name: "Personal")
        let second = store.createProject(name: "Intercept TeleHealth")

        store.assign(sessionID: "session-1", to: first.id)
        store.assign(sessionID: "session-1", to: second.id)

        XCTAssertEqual(store.project(for: "session-1")?.id, second.id)
        XCTAssertTrue(store.sessionIDs(in: first.id).isEmpty)
    }

    func testRemovingSessionFromProjectKeepsProject() {
        let defaults = isolatedDefaults()
        let store = ProjectStore(defaults: defaults)
        let project = store.createProject(name: "SkillOps")
        store.assign(sessionID: "session-1", to: project.id)

        store.assign(sessionID: "session-1", to: nil)

        XCTAssertNil(store.project(for: "session-1"))
        XCTAssertEqual(store.projects.map(\.id), [project.id])
    }

    func testDeletingProjectUnassignsItsSessions() {
        let defaults = isolatedDefaults()
        let store = ProjectStore(defaults: defaults)
        let project = store.createProject(name: "Archive")
        store.assign(sessionID: "session-1", to: project.id)

        store.deleteProject(project.id)

        XCTAssertTrue(store.projects.isEmpty)
        XCTAssertNil(store.project(for: "session-1"))
    }

    func testStatePersistsAcrossInstances() {
        let defaults = isolatedDefaults()
        let firstStore = ProjectStore(defaults: defaults)
        let project = firstStore.createProject(name: "Mochii")
        firstStore.assign(sessionID: "session-42", to: project.id)

        let reloaded = ProjectStore(defaults: defaults)

        XCTAssertEqual(reloaded.projects.first?.name, "Mochii")
        XCTAssertEqual(reloaded.project(for: "session-42")?.id, project.id)
    }

    func testProjectsAreScopedPerServer() {
        let defaults = isolatedDefaults()
        let store = ProjectStore(defaults: defaults)
        store.configure(for: "http://server-a:8642")
        let project = store.createProject(name: "Server A")
        store.assign(sessionID: "session-a", to: project.id)

        let remote = ProjectStore(defaults: defaults)
        remote.configure(for: "http://server-b:8642")
        XCTAssertTrue(remote.projects.isEmpty)

        let sameServer = ProjectStore(defaults: defaults)
        sameServer.configure(for: "http://server-a:8642")
        XCTAssertEqual(sameServer.projects.first?.id, project.id)
        XCTAssertEqual(sameServer.project(for: "session-a")?.id, project.id)
    }

    func testPrunesAssignmentsForDeletedSessions() {
        let defaults = isolatedDefaults()
        let store = ProjectStore(defaults: defaults)
        store.configure(for: "http://server-a:8642")
        let project = store.createProject(name: "Archive")
        store.assign(sessionID: "deleted", to: project.id)
        store.assign(sessionID: "current", to: project.id)

        store.pruneSessions(Set(["current"]))

        XCTAssertNil(store.project(for: "deleted"))
        XCTAssertEqual(store.project(for: "current")?.id, project.id)
    }

    private func isolatedDefaults() -> UserDefaults {
        let suite = "ProjectStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
