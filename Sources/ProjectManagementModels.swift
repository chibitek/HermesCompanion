import Foundation

struct ManagedProjects: Decodable {
    let profile: String
    let projects: [ManagedProject]
    let active_id: String?
}

struct ManagedProjectReceipt: Decodable {
    let profile: String
    let project: ManagedProject
}

struct ManagedProject: Decodable, Identifiable {
    let id: String
    let slug: String
    let name: String
    let description: String?
    let icon: String?
    let color: String?
    let board_slug: String?
    let primary_path: String?
    let archived: Bool
    let folders: [ManagedProjectFolder]
}

struct ManagedProjectFolder: Decodable, Identifiable {
    let path: String
    let label: String?
    let is_primary: Bool
    var id: String { path }
}

struct ProjectWrite: Encodable {
    var name: String? = nil
    var description: String? = nil
    var slug: String? = nil
    var folders: [String]? = nil
    var icon: String? = nil
    var color: String? = nil
    var board_slug: String? = nil

    static func changes(from project: ManagedProject, name: String, description: String,
                        icon: String, color: String, board: String) -> ProjectWrite {
        var value = ProjectWrite()
        if name != project.name { value.name = name }
        if description != (project.description ?? "") { value.description = description }
        if icon != (project.icon ?? "") { value.icon = icon }
        if color != (project.color ?? "") { value.color = color }
        if board != (project.board_slug ?? "") { value.board_slug = board }
        return value
    }

    var isEmpty: Bool {
        name == nil && description == nil && slug == nil && folders == nil
            && icon == nil && color == nil && board_slug == nil
    }
}

struct ProjectFolderWrite: Encodable {
    let path: String
    var label: String? = nil
    var is_primary: Bool? = nil
}
