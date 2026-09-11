import Foundation

// MARK: - On-device file logger
/// Writes log lines to the app's Documents directory so they can be pulled
/// with `devicectl device copy` when the Xcode console / syslog path is
/// unavailable. Used to diagnose voice / Hermes callback issues.
struct FileLogger {
    static let shared = FileLogger()

    private let queue = DispatchQueue(label: "com.chibitek.hermescompanion.filelogger", qos: .utility)
    private let logURL: URL
    private let maxFileSize: Int64 = 512_000 // 512 KB cap

    // ponytail: shared formatter — ISO8601DateFormatter allocates calendar/locale on init; creating per-call burns cycles
    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
     }()

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
             ?? FileManager.default.temporaryDirectory
        logURL = docs.appendingPathComponent("hermes-companion.log")
     }

    func log(_ message: String) {
        let timestamp = Self.formatter.string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        queue.sync { [logURL, maxFileSize] in
            // Rotate if file exceeds size cap
            if let attrs = try? FileManager.default.attributesOfItem(atPath: logURL.path),
               let size = attrs[.size] as? Int64, size > maxFileSize {
                try? FileManager.default.removeItem(at: logURL)
            }
            if let data = line.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: logURL.path) {
                    if let handle = try? FileHandle(forWritingTo: logURL) {
                        _ = handle.seekToEndOfFile()
                        handle.write(data)
                        try? handle.close()
                    }
                } else {
                    try? data.write(to: logURL, options: .atomic)
                }
            }
        }
    }

    func clear() {
        queue.sync { [logURL] in
            try? FileManager.default.removeItem(at: logURL)
        }
    }
}

// MARK: - Connection

struct ConnectionConfig: Codable, Identifiable, Equatable {
    var baseURL: String
    var apiKey: String
    var label: String
    var isDemoMode: Bool = false

    var id: String { baseURL }

    var isValid: Bool {
        if isDemoMode { return true }
        return !baseURL.isEmpty && !apiKey.isEmpty && URL(string: baseURL) != nil
    }

    /// Strip trailing slash for consistent URL joining
    var normalizedBaseURL: String {
        baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
    }

    enum CodingKeys: String, CodingKey {
        case baseURL, apiKey, label, isDemoMode
    }

    init(baseURL: String, apiKey: String, label: String, isDemoMode: Bool = false) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.label = label
        self.isDemoMode = isDemoMode
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        baseURL = try c.decode(String.self, forKey: .baseURL)
        apiKey = try c.decode(String.self, forKey: .apiKey)
        label = try c.decode(String.self, forKey: .label)
        isDemoMode = try c.decodeIfPresent(Bool.self, forKey: .isDemoMode) ?? false
    }
}

// MARK: - Health

struct HealthResponse: Codable {
    let status: String
    let platform: String?
    let version: String?

    /// Whether this looks like a real Hermes API server
    var isHermesAPI: Bool {
        platform == "hermes-agent"
    }
}

// MARK: - Capabilities

struct CapabilitiesResponse: Codable {
    let object: String
    let platform: String
    let model: String
    let currentProvider: String?
    let currentModel: String?
    let auth: AuthInfo
    let features: Features
    let endpoints: [String: EndpointInfo]

    enum CodingKeys: String, CodingKey {
        case object, platform, model, auth, features, endpoints
        case currentProvider = "current_provider"
        case currentModel = "current_model"
    }

    struct AuthInfo: Codable {
        let type: String
        let required: Bool
    }

    struct Features: Codable {
        let browserExtensionControl: Bool?
        let modelOptions: Bool?
        let sessionModelLock: Bool?
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
        let artifactTransport: Bool?
        let sessionFork: Bool
        let skillsAPI: Bool

        enum CodingKeys: String, CodingKey {
            case chatCompletions = "chat_completions"
            case browserExtensionControl = "browser_extension_control"
            case chatCompletionsStreaming = "chat_completions_streaming"
            case sessionChat = "session_chat"
            case sessionChatStreaming = "session_chat_streaming"
            case runSubmission = "run_submission"
            case runEventsSSE = "run_events_sse"
            case runStop = "run_stop"
        case runApprovalResponse = "run_approval_response"
        case modelOptions = "model_options"
        case sessionModelLock = "session_model_lock"
            case toolProgressEvents = "tool_progress_events"
            case approvalEvents = "approval_events"
            case sessionResources = "session_resources"
            case artifactTransport = "artifact_transport"
            case sessionFork = "session_fork"
            case skillsAPI = "skills_api"
        }
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
    var model: String? = nil
    var provider: String? = nil
    let startedAt: Double?
    let lastActive: Double?
    let messageCount: Int?
    let cwd: String?
    let gitRepoRoot: String?
    var billingProvider: String? = nil
    var isPinned: Bool?
    var isArchived: Bool?
    var isHidden: Bool?

    enum CodingKeys: String, CodingKey {
    case id, title, source, model, provider
        case startedAt = "started_at"
        case lastActive = "last_active"
        case messageCount = "message_count"
        case cwd, gitRepoRoot = "git_repo_root"
        case billingProvider = "billing_provider"
        case isPinned = "pinned"
        case isArchived = "archived"
        case isHidden = "hidden"
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
    let total: Int?
}

struct CreateSessionRequest: Codable {
    let title: String?
}

// MARK: - Messages

struct SessionMessage: Codable, Identifiable, Hashable {
    let id: Int
    let role: String
    let content: String?
    let timestamp: Double?
    let toolCalls: [ToolCall]?
    let toolCallId: String?

    enum CodingKeys: String, CodingKey {
        case id, role, content, timestamp
        case toolCalls = "tool_calls"
        case toolCallId = "tool_call_id"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(Int.self, forKey: .id)
        self.role = try c.decodeIfPresent(String.self, forKey: .role) ?? ""
        // Content can be null for tool-call assistant messages
        self.content = try c.decodeIfPresent(String.self, forKey: .content) ?? ""
        self.timestamp = try c.decodeIfPresent(Double.self, forKey: .timestamp)
        self.toolCalls = try c.decodeIfPresent([ToolCall].self, forKey: .toolCalls)
        self.toolCallId = try c.decodeIfPresent(String.self, forKey: .toolCallId)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(role, forKey: .role)
        try c.encodeIfPresent(content, forKey: .content)
        try c.encodeIfPresent(timestamp, forKey: .timestamp)
        try c.encodeIfPresent(toolCalls, forKey: .toolCalls)
        try c.encodeIfPresent(toolCallId, forKey: .toolCallId)
    }

    var idString: String { String(id) }
    var isUser: Bool { role == "user" }
    var isAssistant: Bool { role == "assistant" }
    var isSystem: Bool { role == "system" }
    var isTool: Bool { role == "tool" }
    /// True for assistant messages that are tool-call wrappers (no visible text).
    var isToolCall: Bool { isAssistant && (toolCalls?.isEmpty == false) }
    /// True for messages that should be hidden from the chat UI.
    var shouldHide: Bool {
        if isTool || isSystem { return true }
        if isToolCall { return true }
        // Hide assistant messages with null/empty content (tool-call intermediates)
        if isAssistant && (content?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
            return true
        }
        // Hide assistant messages whose content is raw JSON (tool-call artifacts)
        if isAssistant, let c = content {
            let trimmed = c.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("{\"") || trimmed.hasPrefix("[{") || trimmed.hasPrefix("{\"role\"") {
                return true
            }
        }
        return false
    }

    var date: Date? {
        guard let ts = timestamp else { return nil }
        return Date(timeIntervalSince1970: ts)
    }
}

struct ToolCall: Codable, Hashable {
    let id: String?
    let type: String?
    let function: ToolCallFunction?
}

struct ToolCallFunction: Codable, Hashable {
    let name: String?
    let arguments: String?
}

struct SessionMessagesResponse: Codable {
    let object: String
    let data: [SessionMessage]
}

// MARK: - Chat Request

struct SessionChatRequest: Codable {
    let message: String
    let systemMessage: String?
    let model: String?

    enum CodingKeys: String, CodingKey {
        case message
        case systemMessage = "system_message"
        case model
    }
}

// MARK: - Session Runtime

struct SessionRuntime: Codable, Hashable, Sendable {
    let provider: String?
    let model: String?
    let routeSource: String?
    let requested: RequestedRuntime?
    let modelLock: String?

    struct RequestedRuntime: Codable, Hashable, Sendable {
        let provider: String?
        let model: String?
    }

    enum CodingKeys: String, CodingKey {
        case provider, model
        case routeSource = "route_source"
        case requested
        case modelLock = "model_lock"
    }

    var effectiveProvider: String? {
        nonEmpty(provider) ?? nonEmpty(requested?.provider)
    }

    var effectiveModel: String? {
        nonEmpty(model) ?? nonEmpty(requested?.model)
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }
}

struct SessionModelLockRequest: Codable {
    let model: String
    var provider: String? = nil
    let requireModelLock: Bool

    enum CodingKeys: String, CodingKey {
        case model, provider
        case requireModelLock = "require_model_lock"
    }
}

struct SessionModelLockResponse: Codable {
    let object: String
    let sessionId: String
    let runtime: SessionRuntime

    enum CodingKeys: String, CodingKey {
        case object, runtime
        case sessionId = "session_id"
    }
}

// MARK: - Chat Response (non-streaming)

struct SessionChatResponse: Codable {
    let object: String
    let sessionId: String
    let message: ChatMessageContent

    enum CodingKeys: String, CodingKey {
        case object
        case sessionId = "session_id"
        case message
    }
}

struct ChatMessageContent: Codable {
    let role: String
    let content: String
}

// MARK: - SSE Events (streaming)

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
    let message: String?  // error message
    let runtime: SessionRuntime?

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
        case message
        case runtime
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
        self.runtime = try c.decodeIfPresent(SessionRuntime.self, forKey: .runtime)
    }

    /// Direct initializer for fallback construction
    init(event: String, sessionId: String?, runId: String?, message_id: String?,
         delta: String?, content: String?, toolName: String?, preview: String?,
         args: AnyCodable?, completed: Bool?, partial: Bool?, interrupted: Bool?,
         message: String?, runtime: SessionRuntime? = nil) {
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
        self.message = message
        self.runtime = runtime
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

// MARK: - Models (/v1/models)

struct ModelInfo: Codable, Identifiable, Hashable {
    let id: String
    let object: String?
    let ownedBy: String?
    let provider: String?

    enum CodingKeys: String, CodingKey {
        case id, object, provider
        case ownedBy = "owned_by"
    }

    init(id: String, object: String = "model", ownedBy: String? = nil, provider: String? = nil) {
        self.id = id
        self.object = object
        self.ownedBy = ownedBy
        self.provider = provider
    }
}

struct ModelsResponse: Codable {
    let object: String?
    let data: [ModelInfo]
    let providers: [ProviderInfo]?
}

struct ModelOptionProvider: Codable, Identifiable, Hashable {
    let slug: String
    let name: String
    let models: [String]
    let isCurrent: Bool?

    enum CodingKeys: String, CodingKey {
        case slug, name, models
        case isCurrent = "is_current"
    }

    var id: String { slug }
}

struct ModelOptionsResponse: Codable {
    let providers: [ModelOptionProvider]
    let model: String
    let provider: String?
}

struct ProviderInfo: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let modelCount: Int

    enum CodingKeys: String, CodingKey {
        case id, name
        case modelCount = "model_count"
    }
}

// MARK: - Toolsets (/v1/toolsets)

struct ToolsetInfo: Codable, Identifiable, Hashable {
    let name: String
    let label: String
    let description: String
    let enabled: Bool
    let configured: Bool
    let tools: [String]

    var id: String { name }
}

struct ToolsetsResponse: Codable {
    let object: String
    let platform: String
    let data: [ToolsetInfo]
}

// MARK: - Session Detail (/api/sessions/{id} GET)

/// Extended session metadata returned by GET /api/sessions/{id}.
/// The list endpoint returns a subset; the single-session endpoint returns
/// the full _session_response payload including token counts and cost.
struct SessionDetail: Codable, Identifiable, Hashable {
    let id: String
    let source: String?
    let model: String?
    let provider: String?
    let title: String?
    let startedAt: Double?
    let messageCount: Int?
    let toolCallCount: Int?
    let inputTokens: Int?
    let outputTokens: Int?
    let reasoningTokens: Int?
    let lastActive: Double?
    let preview: String?
    let hasModelConfig: Bool?
    let cwd: String?
    let gitRepoRoot: String?
    var billingProvider: String? = nil
    let isPinned: Bool?
    let isArchived: Bool?
    let isHidden: Bool?

    enum CodingKeys: String, CodingKey {
        case id, source, model, provider, title, preview
        case hasModelConfig = "has_model_config"
        case cwd, gitRepoRoot = "git_repo_root"
        case billingProvider = "billing_provider"
        case isPinned = "pinned"
        case isArchived = "archived"
        case isHidden = "hidden"
        case startedAt = "started_at"
        case messageCount = "message_count"
        case toolCallCount = "tool_call_count"
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case reasoningTokens = "reasoning_tokens"
        case lastActive = "last_active"
    }

    var date: Date? {
        guard let ts = startedAt else { return nil }
        return Date(timeIntervalSince1970: ts)
    }

    var lastActiveDate: Date? {
        guard let ts = lastActive else { return nil }
        return Date(timeIntervalSince1970: ts)
    }
}

/// Wrapper for GET /api/sessions/{id} response: {"object": "hermes.session", "session": {...}}
struct GetSessionResponse: Codable {
    let object: String
    let session: SessionDetail
}

// MARK: - Session Patch (rename)

struct PatchSessionRequest: Encodable {
    var title: String?
    var isPinned: Bool?
    var isArchived: Bool?
    var isHidden: Bool?

    enum CodingKeys: String, CodingKey {
        case title
        case isPinned = "pinned"
        case isArchived = "archived"
        case isHidden = "hidden"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let title { try container.encode(title, forKey: .title) }
        if let isPinned { try container.encode(isPinned, forKey: .isPinned) }
        if let isArchived { try container.encode(isArchived, forKey: .isArchived) }
        if let isHidden { try container.encode(isHidden, forKey: .isHidden) }
    }
}

// MARK: - Session Fork

struct ForkSessionRequest: Codable {
    let title: String?

    // The server accepts an optional id/session_id but we let it auto-generate.
}

struct ForkSessionResponse: Codable {
    let object: String
    let session: HermesSession
}

// MARK: - Platform Health

struct PlatformHealthResponse: Codable {
    let status: String
    let platform: String?
    let version: String?
    let gatewayState: String?
    let activeAgents: Int?
    let gatewayBusy: Bool?
    let gatewayDrainable: Bool?
    let updatedAt: String?
    let platforms: [String: HermesPlatformStatus]?
    let readiness: HermesReadiness?

    enum CodingKeys: String, CodingKey {
        case status, platform, version, platforms, readiness
        case gatewayState = "gateway_state"
        case activeAgents = "active_agents"
        case gatewayBusy = "gateway_busy"
        case gatewayDrainable = "gateway_drainable"
        case updatedAt = "updated_at"
    }
}

struct HermesPlatformStatus: Codable, Identifiable, Hashable {
    var id: String { name }
    let name: String
    let state: String?
    let errorCode: String?
    let errorMessage: String?
    let needsAttention: Bool?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case state, name
        case errorCode = "error_code"
        case errorMessage = "error_message"
        case needsAttention = "needs_attention"
        case updatedAt = "updated_at"
    }

    init(name: String, state: String?, errorCode: String?, errorMessage: String?, needsAttention: Bool?, updatedAt: String?) {
        self.name = name
        self.state = state
        self.errorCode = errorCode
        self.errorMessage = errorMessage
        self.needsAttention = needsAttention
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        state = try container.decodeIfPresent(String.self, forKey: .state)
        errorCode = try container.decodeIfPresent(String.self, forKey: .errorCode)
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
        needsAttention = try container.decodeIfPresent(Bool.self, forKey: .needsAttention)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
    }
}

struct HermesReadiness: Codable, Hashable {
    let status: String?
    let checks: [String: HermesReadinessCheck]?

    enum CodingKeys: String, CodingKey {
        case status, checks
    }
}

struct HermesReadinessCheck: Codable, Hashable {
    let status: String?
    let usedPercent: Double?
    let freeBytes: Int?
    let state: String?
    let connectedPlatforms: Int?
    let platforms: Int?
    let activeAPIRuns: Int?

    enum CodingKeys: String, CodingKey {
        case status, state, platforms
        case usedPercent = "used_percent"
        case freeBytes = "free_bytes"
        case connectedPlatforms = "connected_platforms"
        case activeAPIRuns = "active_api_runs"
    }
}

// MARK: - Scheduled Jobs

struct HermesJob: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let prompt: String?
    let scheduleDisplay: String?
    let enabled: Bool?
    let state: String?
    let nextRunAt: String?
    let lastRunAt: String?
    let lastStatus: String?
    let lastError: String?
    let deliver: String?
    let skills: [String]?

    enum CodingKeys: String, CodingKey {
        case id, name, prompt, enabled, state, deliver, skills
        case scheduleDisplay = "schedule_display"
        case nextRunAt = "next_run_at"
        case lastRunAt = "last_run_at"
        case lastStatus = "last_status"
        case lastError = "last_error"
    }
}

struct HermesJobsResponse: Codable {
    let jobs: [HermesJob]
}

struct HermesJobResponse: Codable {
    let job: HermesJob
}

struct HermesJobWrite: Encodable, Hashable {
    var name: String = ""
    var schedule: String = ""
    var prompt: String = ""
    var deliver: String = "local"
    var skills: [String] = []
}

struct HermesArtifactReceipt: Codable, Identifiable, Hashable {
    let artifactId: String
    let sha256: String
    let sizeBytes: Int
    let contentType: String
    let filename: String
    let createdAt: Double
    let expiresAt: Double
    let ttlSeconds: Double
    let oneShot: Bool?
    let downloadPath: String?

    enum CodingKeys: String, CodingKey {
        case artifactId = "artifact_id"
        case sha256
        case sizeBytes = "size_bytes"
        case contentType = "content_type"
        case filename
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case ttlSeconds = "ttl_seconds"
        case oneShot = "one_shot"
        case downloadPath = "download_path"
    }

    var id: String { artifactId }
}

enum HermesJobAction: String {
    case pause
    case resume
    case run
    case delete
}
