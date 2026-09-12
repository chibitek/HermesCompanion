import Foundation

struct WorkspaceProjects: Decodable {
    let groups: [ProfileProjects]
    let errors: [ProfileReadError]
}

struct ProfileReadError: Decodable {
    let profile: String
    let message: String
}

struct ProfileProjects: Decodable, Identifiable {
    let profile: String
    let projects: [ServerProject]
    var id: String { profile }
}

struct ServerProject: Decodable, Identifiable {
    let id: String
    let label: String
    let path: String?
    let sessionCount: Int
    let repos: [ServerRepository]
}

struct ServerRepository: Decodable, Identifiable {
    let id: String
    let label: String
    let path: String?
    let groups: [ServerProjectLane]
}

struct ServerProjectLane: Decodable, Identifiable {
    let id: String
    let label: String
    let path: String?
    let sessions: [HermesSession]
}

struct ServerProjectDetail: Decodable {
    let project: ServerProject?
}

struct WorkspaceBots: Decodable {
    let profiles: [ServerBot]

    func profile(named name: String) -> ServerBot? {
        profiles.first { $0.name == name }
    }
}

struct ServerBot: Decodable, Identifiable {
    let name: String
    let display_name: String?
    let description: String?
    let model: String?
    let provider: String?
    let skill_count: Int?
    let last_session: BotSession?
    let canonical_session: BotSession?
    var id: String { name }
    var title: String { display_name.flatMap { $0.isEmpty ? nil : $0 } ?? name }
}

struct BotSession: Decodable {
    let id: String
    let title: String?
    let preview: String?
}

struct BotHistory: Decodable {
    let profile: String
    let session_id: String?
    let messages: [BotHistoryMessage]
    let pagination: HistoryPagination
}

struct ProjectSessionHistory: Decodable {
    let project_id: String
    let requested_session_id: String
    let history: BotHistory

    func matches(profile: String, projectID: String, sessionID: String, offset: Int) -> Bool {
        project_id == projectID && requested_session_id == sessionID
            && history.profile == profile && history.pagination.offset == offset
    }
}

struct HistoryPagination: Decodable {
    let offset: Int
    let limit: Int
    let returned: Int
}

struct BotHistoryMessage: Decodable, Identifiable {
    let id: Int
    let role: String
    let content: String?
    let display_content: String?
    let display_kind: String?

    var visibleText: String? {
        guard display_kind != "hidden" else { return nil }
        return display_content ?? content
    }
}

struct WorkspaceBoards: Decodable {
    let boards: [ServerBoard]
    let current: String
}

struct ServerBoard: Decodable, Identifiable {
    let slug: String
    let name: String?
    let total: Int?
    let project_name: String?
    var id: String { slug }
    var title: String { name.flatMap { $0.isEmpty ? nil : $0 } ?? slug }
}

struct ServerBoardDetail: Decodable {
    let columns: [ServerBoardColumn]
}

struct ServerBoardColumn: Decodable, Identifiable {
    let name: String
    let tasks: [ServerBoardTask]
    var id: String { name }
}

struct ServerBoardTask: Decodable, Identifiable {
    let id: String
    let title: String
    let body: String?
    let status: String
    let assignee: String?
    let latest_summary: String?
    let result: String?
}

struct ServerTaskDetail: Decodable {
    let board: String
    let task: ServerBoardTask
    let comments: [ServerTaskComment]
    let runs: [ServerTaskRun]
    let links: ServerTaskLinks?
    let child_results: [ServerBoardTask]?

    func matches(board: String, taskID: String) -> Bool {
        self.board == board && task.id == taskID
            && comments.allSatisfy { $0.task_id == taskID }
            && runs.allSatisfy { $0.task_id == taskID }
            && (child_results ?? []).allSatisfy { links?.children.contains($0.id) == true }
    }
}

struct ServerTaskLinks: Decodable {
    let parents: [String]
    let children: [String]
}

struct ServerTaskComment: Decodable, Identifiable {
    let id: Int
    let task_id: String
    let author: String
    let body: String
    let created_at: Double
}

struct ServerTaskRun: Decodable, Identifiable {
    let id: Int
    let task_id: String
    let status: String
    let profile: String?
    let outcome: String?
    let summary: String?
    let error: String?
    let started_at: Double
}
