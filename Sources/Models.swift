import Foundation

// MARK: - Connection

struct ConnectionConfig: Codable, Equatable, Sendable {
    var baseURL: String
    var apiKey: String
    var label: String

    var isValid: Bool {
        !baseURL.isEmpty && !apiKey.isEmpty && URL(string: baseURL) != nil
    }

    /// Strip trailing slash for consistent URL joining
    var normalizedBaseURL: String {
        baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
    }
}

// MARK: - Health

struct HealthResponse: Codable {
    let status: String
    let platform: String?
    let version: String?

    /// Whether this looks like a real Hermes API server
    var isHermes: Bool {
        platform == "hermes-agent" || platform == "webhook"
    }
}

// MARK: - Capabilities

struct CapabilitiesResponse: Codable {
    let object: String
    let platform: String
    let model: String
    let auth: AuthInfo
    let features: Features
    let endpoints: [String: EndpointInfo]

    struct AuthInfo: Codable {
        let type: String
        let required: Bool
    }

    struct Features: Codable {
        let chatCompletions: Bool
        let chatCompletionsStreaming: Bool
        let sessionChat: Bool
        let sessionChatStreaming: Bool
        let runSubmission: Bool
        let runEventsSSE: Bool
        let runStop: Bool
        let runApprovalResponse: Bool
        let toolProgressEvents: Bool
        let approvalEvents: Bool
        let sessionResources: Bool
        let sessionFork: Bool
        let skillsAPI: Bool
    }

    struct EndpointInfo: Codable {
        let method: String
        let path: String
    }
}

// MARK: - Sessions

struct HermesSession: Codable, Identifiable, Hashable {
    let id: String
    let title: String?
    let source: String?
    let startedAt: Double?
    let lastActive: Double?
    let messageCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, title, source
        case startedAt = "started_at"
        case lastActive = "last_active"
        case messageCount = "message_count"
    }

    var date: Date? {
        guard let ts = startedAt else { return nil }
        return Date(timeIntervalSince1970: ts)
    }
}

/// Wrapper for POST /api/sessions response: {"object": "hermes.session", "session": {...}}
struct CreateSessionResponse: Codable {
    let object: String
    let session: HermesSession
}

struct SessionListResponse: Codable {
    let object: String
    let data: [HermesSession]
}

struct CreateSessionRequest: Codable {
    let title: String?

    enum CodingKeys: String, CodingKey {
        case title
    }
}

// MARK: - Messages

struct SessionMessage: Codable, Identifiable, Hashable {
    let id: String
    let role: String
    let content: String
    let timestamp: String?

    var isUser: Bool { role == "user" }
    var isAssistant: Bool { role == "assistant" }
    var isSystem: Bool { role == "system" }
    var isTool: Bool { role == "tool" }
}

struct SessionMessagesResponse: Codable {
    let object: String
    let data: [SessionMessage]
}

// MARK: - Chat Request

struct SessionChatRequest: Codable {
    let message: String
    let systemMessage: String?

    enum CodingKeys: String, CodingKey {
        case message
        case systemMessage = "system_message"
    }
}

// MARK: - Chat Response (non-streaming)

struct SessionChatResponse: Codable {
    let object: String
    let sessionId: String
    let message: ChatMessageContent
    let usage: Usage?

    enum CodingKeys: String, CodingKey {
        case object
        case sessionId = "session_id"
        case message
        case usage
    }
}

struct ChatMessageContent: Codable {
    let role: String
    let content: String
}

struct Usage: Codable {
    let inputTokens: Int?
    let outputTokens: Int?
    let totalTokens: Int?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case totalTokens = "total_tokens"
    }
}

// MARK: - SSE Events (streaming)

enum SSEEvent: String, Codable {
    case runStarted = "run.started"
    case messageStarted = "message.started"
    case assistantDelta = "assistant.delta"
    case assistantCompleted = "assistant.completed"
    case toolProgress = "tool.progress"
    case toolStarted = "tool.started"
    case toolCompleted = "tool.completed"
    case toolFailed = "tool.failed"
    case runCompleted = "run.completed"
    case error = "error"
    case done = "done"
}

struct SSEEventPayload: Codable, Sendable {
    var event: String
    let sessionId: String?
    let runId: String?
    let message_id: String?
    let delta: String?
    let content: String?
    let toolName: String?
    let preview: String?
    let args: AnyCodable?
    let completed: Bool?
    let partial: Bool?
    let interrupted: Bool?
    let usage: Usage?
    let message: String?  // error message

    enum CodingKeys: String, CodingKey {
        case event
        case sessionId = "session_id"
        case runId = "run_id"
        case message_id
        case delta
        case content
        case toolName = "tool_name"
        case preview
        case args
        case completed
        case partial
        case interrupted
        case usage
        case message
    }

    /// Custom decoder: the `event` field is NOT in the SSE JSON data — it comes
    /// from the `event:` SSE protocol line. We decode without it and inject it after.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.event = try c.decodeIfPresent(String.self, forKey: .event) ?? ""
        self.sessionId = try c.decodeIfPresent(String.self, forKey: .sessionId)
        self.runId = try c.decodeIfPresent(String.self, forKey: .runId)
        self.message_id = try c.decodeIfPresent(String.self, forKey: .message_id)
        self.delta = try c.decodeIfPresent(String.self, forKey: .delta)
        self.content = try c.decodeIfPresent(String.self, forKey: .content)
        self.toolName = try c.decodeIfPresent(String.self, forKey: .toolName)
        self.preview = try c.decodeIfPresent(String.self, forKey: .preview)
        self.args = try c.decodeIfPresent(AnyCodable.self, forKey: .args)
        self.completed = try c.decodeIfPresent(Bool.self, forKey: .completed)
        self.partial = try c.decodeIfPresent(Bool.self, forKey: .partial)
        self.interrupted = try c.decodeIfPresent(Bool.self, forKey: .interrupted)
        self.usage = try c.decodeIfPresent(Usage.self, forKey: .usage)
        // The `message` field is overloaded: in `message.started` events it's an
        // object ({"id": ..., "role": ...}), in `error` events it's a string.
        // Try string first; if that fails, decode as object and extract nothing
        // (we don't need the message object's fields — we only use the string form).
        if let msg = try? c.decodeIfPresent(String.self, forKey: .message) {
            self.message = msg
        } else {
            // It's an object or absent — not an error message, so nil is fine
            self.message = nil
        }
    }

    /// Direct initializer for fallback construction
    init(event: String, sessionId: String?, runId: String?, message_id: String?,
         delta: String?, content: String?, toolName: String?, preview: String?,
         args: AnyCodable?, completed: Bool?, partial: Bool?, interrupted: Bool?,
         usage: Usage?, message: String?) {
        self.event = event
        self.sessionId = sessionId
        self.runId = runId
        self.message_id = message_id
        self.delta = delta
        self.content = content
        self.toolName = toolName
        self.preview = preview
        self.args = args
        self.completed = completed
        self.partial = partial
        self.interrupted = interrupted
        self.usage = usage
        self.message = message
    }
}

// MARK: - AnyCodable (for flexible JSON args)

struct AnyCodable: Codable, @unchecked Sendable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self.value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            self.value = bool
        } else if let int = try? container.decode(Int.self) {
            self.value = int
        } else if let double = try? container.decode(Double.self) {
            self.value = double
        } else if let string = try? container.decode(String.self) {
            self.value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            self.value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            self.value = dict.mapValues { $0.value }
        } else {
            self.value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case is NSNull: try container.encodeNil()
        case let bool as Bool: try container.encode(bool)
        case let int as Int: try container.encode(int)
        case let double as Double: try container.encode(double)
        case let string as String: try container.encode(string)
        case let array as [Any]: try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]: try container.encode(dict.mapValues { AnyCodable($0) })
        default: try container.encodeNil()
        }
    }
}

// MARK: - Skills

struct Skill: Codable, Identifiable, Hashable {
    let name: String
    let description: String?
    let category: String?

    var id: String { name }
}

struct SkillsResponse: Codable {
    let object: String
    let data: [Skill]
}

// MARK: - Runs (async agent execution)

struct RunRequest: Codable {
    let input: String
    let instructions: String?
    let sessionId: String?

    enum CodingKeys: String, CodingKey {
        case input
        case instructions
        case sessionId = "session_id"
    }
}

struct RunResponse: Codable {
    let runId: String
    let status: String
    let sessionId: String?

    enum CodingKeys: String, CodingKey {
        case runId = "run_id"
        case status
        case sessionId = "session_id"
    }
}

struct RunStatus: Codable {
    let runId: String
    let status: String
    let sessionId: String?
    let createdAt: Double?
    let lastEvent: String?
    let model: String?

    enum CodingKeys: String, CodingKey {
        case runId = "run_id"
        case status
        case sessionId = "session_id"
        case createdAt = "created_at"
        case lastEvent = "last_event"
        case model
    }
}

// MARK: - Approval

struct ApprovalRequest: Codable {
    let event: String
    let runId: String?
    let command: String?
    let tool: String?
    let choices: [String]?

    enum CodingKeys: String, CodingKey {
        case event
        case runId = "run_id"
        case command
        case tool
        case choices
    }
}

struct ApprovalResponse: Codable {
    let choice: String  // "once", "session", "always", "deny"
    let all: Bool?
}