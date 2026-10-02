import Foundation

struct DurableRunRequest: Codable, Sendable {
    let input: String
    let session_id: String?
    let model: String?
    let provider: String?
}

struct DurableRunAccepted: Decodable {
    let run_id: String
    let status: String
    let replayed: Bool?
}

struct DurableRunStatus: Decodable {
    let run_id: String
    let status: String
    let session_id: String?
    let last_event: String?
    let progress_kind: String?
    let progress_message: String?
    let progress_at: Double?
    let event_cursor: Int?
    let event_replay_floor: Int?
    let output: String?
    let error: String?
    let pending_steer: String?
    let approval: DurableRunApproval?

    var isTerminal: Bool { ["completed", "failed", "cancelled", "interrupted"].contains(status) }

    var activityDescription: String {
        if isTerminal { return status.capitalized }
        if status == "waiting_for_approval" { return "Hermes is waiting for approval" }
        if status == "stopping" { return "Hermes is stopping this run" }
        if let progress_message, !progress_message.isEmpty { return progress_message }
        switch last_event {
        case "message.delta": return "Hermes is generating a response"
        case "tool.started": return "Hermes is running a tool"
        case "tool.completed": return "Hermes finished a tool"
        case "approval.request": return "Hermes is waiting for approval"
        default: return status == "running" ? "Hermes run is active" : status.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

struct DurableRunApproval: Decodable, Identifiable {
    let request_id: String?
    let command: String?
    let description: String?
    let choices: [String]?
    var id: String { request_id ?? "missing-request-id" }
    var offeredChoices: [String] {
        guard let request_id, !request_id.isEmpty else { return [] }
        return ["once", "session", "always", "deny"].filter { choices?.contains($0) == true }
    }
}

struct DurableRunControlReceipt: Decodable {
    let run_id: String
    let accepted: Bool?
    let status: String?
    let choice: String?
    let request_id: String?
    let resolved: Int?
}

struct PendingDurableRun: Codable {
    let payload: DurableRunRequest
    let key: String
    let createdAt: Date
}
