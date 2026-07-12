import Foundation

struct ChatProject: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    let createdAt: Date

    init(id: UUID = UUID(), name: String, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}

@MainActor
final class ProjectStore: ObservableObject {
    @Published private(set) var projects: [ChatProject] = []
    @Published private(set) var sessionAssignments: [String: UUID] = [:]

    private let defaults: UserDefaults
    private let storageKey = "hermes_chat_projects_v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    @discardableResult
    func createProject(name: String) -> ChatProject {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let project = ChatProject(name: cleaned.isEmpty ? "Untitled Project" : cleaned)
        projects.append(project)
        sortProjects()
        save()
        return project
    }

    func renameProject(_ id: UUID, name: String) {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, let index = projects.firstIndex(where: { $0.id == id }) else { return }
        projects[index].name = cleaned
        sortProjects()
        save()
    }

    func deleteProject(_ id: UUID) {
        projects.removeAll { $0.id == id }
        sessionAssignments = sessionAssignments.filter { $0.value != id }
        save()
    }

    func assign(sessionID: String, to projectID: UUID?) {
        if let projectID, projects.contains(where: { $0.id == projectID }) {
            sessionAssignments[sessionID] = projectID
        } else {
            sessionAssignments.removeValue(forKey: sessionID)
        }
        save()
    }

    func project(for sessionID: String) -> ChatProject? {
        guard let projectID = sessionAssignments[sessionID] else { return nil }
        return projects.first { $0.id == projectID }
    }

    func sessionIDs(in projectID: UUID) -> [String] {
        sessionAssignments
            .filter { $0.value == projectID }
            .map(\.key)
            .sorted()
    }

    func sessionCount(in projectID: UUID) -> Int {
        sessionAssignments.values.filter { $0 == projectID }.count
    }

    private struct PersistedState: Codable {
        var projects: [ChatProject]
        var assignments: [String: UUID]
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data) else { return }
        projects = state.projects
        sessionAssignments = state.assignments
        sortProjects()
    }

    private func save() {
        let state = PersistedState(projects: projects, assignments: sessionAssignments)
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private func sortProjects() {
        projects.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
