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
}
