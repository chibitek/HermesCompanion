import Foundation

/// Handles all HTTP communication with the Hermes Agent API server.
///
/// All endpoints use Bearer token auth. The base URL is user-configured
/// (e.g., http://localhost:8642 via Tailscale, or http://192.168.1.50:8642 via LAN).
///
/// This client is completely generic — no hardcoded URLs or credentials.
final class HermesAPIClient: Sendable {
    private let session: URLSession
    private let config: ConnectionConfig

    init(config: ConnectionConfig) {
        self.config = config
        let cfg = URLSessionConfiguration.default
        // Hermes turns can legitimately take several minutes on large contexts.
        cfg.timeoutIntervalForRequest = 600
        cfg.timeoutIntervalForResource = 1_800
        cfg.waitsForConnectivity = true
        cfg.networkServiceType = .background
        cfg.allowsConstrainedNetworkAccess = true
        cfg.allowsExpensiveNetworkAccess = true
        self.session = URLSession(configuration: cfg)
    }

    private var baseURL: String { config.normalizedBaseURL }

    private func authHeaders() -> [String: String] {
        ["Authorization": "Bearer \(config.apiKey)",
         "Content-Type": "application/json"]
    }

    private func makeURL(path: String, queryItems: [URLQueryItem]? = nil) throws -> URL {
        let cleanPath = path.hasPrefix("/") ? path : "/\(path)"
        // URL-encode each path segment to handle special characters in IDs
        let encodedPath = cleanPath.split(separator: "/", omittingEmptySubsequences: false)
            .map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
            .joined(separator: "/")
        guard let url = URL(string: baseURL + encodedPath) else {
            throw APIError.invalidURL(baseURL + encodedPath)
        }

        guard let queryItems, !queryItems.isEmpty else { return url }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL(url.absoluteString)
        }
        components.queryItems = queryItems
        guard let urlWithQuery = components.url else {
            throw APIError.invalidURL(url.absoluteString)
        }
        return urlWithQuery
    }

    // ponytail: collapsed 6-line makeRequest+forEach pattern into one helper; every GET endpoint below is now 2 lines.
    private func request(method: String, path: String, queryItems: [URLQueryItem]? = nil) throws -> URLRequest {
        var req = URLRequest(url: try makeURL(path: path, queryItems: queryItems))
        req.httpMethod = method
        authHeaders().forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }
        return req
    }

    private func get<T: Decodable>(path: String, queryItems: [URLQueryItem]? = nil, type: T.Type) async throws -> T {
        let (data, response) = try await session.data(for: try request(method: "GET", path: path, queryItems: queryItems))
        try checkHTTPStatus(response)
        return try JSONDecoder().decode(type, from: data)
    }

    // MARK: - Health

    /// GET /health — no auth required, used for connection test
    func checkHealth() async throws -> HealthResponse {
        let (data, response) = try await session.data(from: try makeURL(path: "/health"))
        try checkHTTPStatus(response)
        return try JSONDecoder().decode(HealthResponse.self, from: data)
    }

    // MARK: - Capabilities

    func getCapabilities() async throws -> CapabilitiesResponse {
        try await get(path: "/v1/capabilities", type: CapabilitiesResponse.self)
    }

    // MARK: - Sessions

    /// GET /api/sessions
    func listSessions(limit: Int = 200) async throws -> [HermesSession] {
        let clampedLimit = max(1, min(limit, 200))
        let res = try await get(
            path: "/api/sessions",
            queryItems: [URLQueryItem(name: "limit", value: String(clampedLimit))],
            type: SessionListResponse.self
        )
        return res.data
    }

    /// POST /api/sessions
    func createSession(title: String? = nil) async throws -> HermesSession {
        var req = try request(method: "POST", path: "/api/sessions")
        req.httpBody = try JSONEncoder().encode(CreateSessionRequest(title: title))
        let (data, response) = try await session.data(for: req)
        try checkHTTPStatus(response)
        // Server returns {"object": "hermes.session", "session": {...}}
        let wrapper = try JSONDecoder().decode(CreateSessionResponse.self, from: data)
        return wrapper.session
    }

    /// GET /api/sessions/{id}/messages
    func getMessages(sessionId: String) async throws -> [SessionMessage] {
        let res = try await get(path: "/api/sessions/\(sessionId)/messages", type: SessionMessagesResponse.self)
        return res.data
    }

    /// DELETE /api/sessions/{id}
    func deleteSession(sessionId: String) async throws {
        let (_, response) = try await session.data(for: try request(method: "DELETE", path: "/api/sessions/\(sessionId)"))
        try checkHTTPStatus(response)
    }

    // MARK: - Skills

    /// GET /v1/skills
    func listSkills() async throws -> [Skill] {
        let res = try await get(path: "/v1/skills", type: SkillsResponse.self)
        return res.data
    }

    // MARK: - Models (/v1/models)

    /// Pass refresh=true only for a user-triggered refresh; this asks the gateway to bypass its provider model cache.
    func getModelCatalog(refresh: Bool = false) async throws -> ModelsResponse {
       guard var components = URLComponents(string: baseURL) else { throw APIError.invalidURL(baseURL) }
       components.path = "/v1/models"
       if refresh { components.queryItems = [URLQueryItem(name: "refresh", value: "1")] }
       var req = try request(method: "GET", path: "")
        req.url = components.url
       let (data, response) = try await session.data(for: req)
       try checkHTTPStatus(response)
       return try JSONDecoder().decode(ModelsResponse.self, from: data)
    }

    func getModels(refresh: Bool = false) async throws -> [ModelInfo] {
        try await getModelCatalog(refresh: refresh).data
    }

    // MARK: - Full Provider Model Catalog (/api/model/options)

    /// The gateway's full configured-provider catalog. This is the authoritative
    /// picker inventory; /v1/models only exposes the virtual agent and aliases.
    func getModelOptions(refresh: Bool = false) async throws -> ModelOptionsResponse {
        let queryItems = refresh ? [URLQueryItem(name: "refresh", value: "1")] : nil
        return try await get(path: "/api/model/options", queryItems: queryItems, type: ModelOptionsResponse.self)
    }

    // MARK: - Per-Session Model Lock

    /// Persist a confirmed model lock on the session itself. Future turns use
    /// this server-side lock rather than a client-global model preference.
    func lockSessionModel(sessionId: String, model: String, provider: String?) async throws -> SessionRuntime {
        var req = try request(method: "POST", path: "/api/sessions/\(sessionId)/model")
        req.httpBody = try JSONEncoder().encode(
            SessionModelLockRequest(model: model, provider: provider, requireModelLock: true)
        )
        let (data, response) = try await session.data(for: req)
        try checkHTTPStatus(response)
        return try JSONDecoder().decode(SessionModelLockResponse.self, from: data).runtime
    }

    // MARK: - Toolsets (/v1/toolsets)

    func getToolsets() async throws -> [ToolsetInfo] {
        let res = try await get(path: "/v1/toolsets", type: ToolsetsResponse.self)
        return res.data
    }

    // MARK: - Session Detail (/api/sessions/{id} GET)

    func getSession(sessionId: String) async throws -> SessionDetail {
        let res = try await get(path: "/api/sessions/\(sessionId)", type: GetSessionResponse.self)
        return res.session
    }

    // MARK: - Chat (non-streaming)

    /// POST /api/sessions/{id}/chat — multimodal content when images/files provided.
    func sendChat(
        sessionId: String,
        message: String,
        systemMessage: String? = nil,
        model: String? = nil,
        images: [Data] = [],
        attachments: [AttachmentData] = []
    ) async throws -> SessionChatResponse {
        var req = try request(method: "POST", path: "/api/sessions/\(sessionId)/chat")

        let hasImages = !images.isEmpty
        let hasFileAttachments = attachments.contains { !$0.isImage }
        let hasImageAttachments = attachments.contains { $0.isImage }

        let body: Data
        if !hasImages && !hasFileAttachments && !hasImageAttachments {
            // Plain text message
            let chatBody = SessionChatRequest(message: message, systemMessage: systemMessage, model: model)
            body = try JSONEncoder().encode(chatBody)
        } else {
            // Multimodal: build content parts array
            var contentParts: [[String: Any]] = []
            if !message.isEmpty {
                contentParts.append(["type": "text", "text": message])
            }
            // Inline images (legacy parameter — pre-converted to JPEG)
            for imageData in images {
                let base64 = imageData.base64EncodedString()
                contentParts.append([
                    "type": "image_url",
                    "image_url": ["url": "data:image/jpeg;base64,\(base64)"]
                ])
            }
            // Attachment-based images and files
            for attachment in attachments {
                let base64 = attachment.data.base64EncodedString()
                if attachment.isImage {
                    contentParts.append([
                        "type": "image_url",
                        "image_url": ["url": "data:\(attachment.mimeType);base64,\(base64)"]
                    ])
                } else if MimeTypeResolver.isTextType(attachment.mimeType) {
                    if let textContent = String(data: attachment.data, encoding: .utf8) {
                        contentParts.append([
                            "type": "text",
                            "text": "File: \(attachment.fileName)\n`\(attachment.fileExtension)\n\(textContent)\n`"
                        ])
                    } else {
                        contentParts.append([
                            "type": "image_url",
                            "image_url": ["url": "data:\(attachment.mimeType);base64,\(base64)"]
                        ])
                    }
                } else {
                    contentParts.append([
                        "type": "image_url",
                        "image_url": ["url": "data:\(attachment.mimeType);base64,\(base64)"]
                    ])
                }
            }
            var bodyDict: [String: Any] = ["message": contentParts]
            if let sys = systemMessage { bodyDict["system_message"] = sys }
            if let mdl = model { bodyDict["model"] = mdl }
            body = try JSONSerialization.data(withJSONObject: bodyDict)
        }
        req.httpBody = body

        let (data, response) = try await session.data(for: req)
        try checkHTTPStatus(response)
        return try JSONDecoder().decode(SessionChatResponse.self, from: data)
    }

    // MARK: - Chat (streaming via SSE)

    /// POST /api/sessions/{id}/chat/stream — returns AsyncSequence of SSE events.
    func streamChat(sessionId: String, message: String, systemMessage: String? = nil, model: String? = nil,
                    onKeepalive: (@Sendable () -> Void)? = nil) async throws -> AsyncThrowingStream<SSEEventPayload, Error> {
        var req = try request(method: "POST", path: "/api/sessions/\(sessionId)/chat/stream")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.httpBody = try JSONEncoder().encode(SessionChatRequest(message: message, systemMessage: systemMessage, model: model))

        let (bytes, response) = try await session.bytes(for: req)
        try checkHTTPStatus(response)

        return AsyncThrowingStream { continuation in
            let task = Task {
                var eventBuffer = ""
                var dataBuffer = ""

                func flush() {
                    guard !eventBuffer.isEmpty || !dataBuffer.isEmpty else { return }
                    defer { eventBuffer = ""; dataBuffer = "" }
                    guard let data = dataBuffer.data(using: .utf8) else { return }
                    var payload = try? JSONDecoder().decode(SSEEventPayload.self, from: data)
                    if payload == nil {
                        // Fallback for done/error frames whose data isn't full JSON.
                        if eventBuffer == "error" || eventBuffer == "done" || eventBuffer.isEmpty {
                            payload = SSEEventPayload(
                                event: eventBuffer, sessionId: nil, runId: nil, message_id: nil,
                                delta: nil, content: nil, toolName: nil, preview: nil, args: nil,
                                completed: nil, partial: nil, interrupted: nil, message: dataBuffer
                            )
                        } else { return }
                    } else { payload!.event = eventBuffer }
                    if let payload = payload { continuation.yield(payload) }
                }

                do {
                    for try await rawLine in bytes.lines {
                        if Task.isCancelled { break }
                        let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine
                        if line.isEmpty { flush(); continue }
                        if line.hasPrefix(":") { onKeepalive?(); continue }
                        if line.hasPrefix("event:") {
                            eventBuffer = trimSSEValue(line, field: "event")
                        } else if line.hasPrefix("data:") {
                            let value = trimSSEValue(line, field: "data")
                            dataBuffer = dataBuffer.isEmpty ? value : dataBuffer + "\n" + value
                        }
                    }
                    flush()
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Extract an SSE field value, tolerating both "field: value" and "field:value".
    private func trimSSEValue(_ line: String, field: String) -> String {
        var value = String(line.dropFirst(field.count + 1)) // drop "field:"
        if value.hasPrefix(" ") { value.removeFirst() }       // drop one optional leading space
        return value
    }

    // MARK: - Session Rename (PATCH /api/sessions/{id})

    func patchSession(
        sessionId: String,
        title: String? = nil,
        isPinned: Bool? = nil,
        isArchived: Bool? = nil,
        isHidden: Bool? = nil
    ) async throws -> HermesSession {
        var req = try request(method: "PATCH", path: "/api/sessions/\(sessionId)")
        req.httpBody = try JSONEncoder().encode(
            PatchSessionRequest(
                title: title, isPinned: isPinned, isArchived: isArchived, isHidden: isHidden
            )
        )
        let (data, response) = try await session.data(for: req)
        try checkHTTPStatus(response)
        let result = try JSONDecoder().decode(CreateSessionResponse.self, from: data)
        return result.session
    }

    // MARK: - Session Fork (POST /api/sessions/{id}/fork)

    func forkSession(sessionId: String, title: String? = nil) async throws -> HermesSession {
        var req = try request(method: "POST", path: "/api/sessions/\(sessionId)/fork")
        req.httpBody = try JSONEncoder().encode(ForkSessionRequest(title: title))
        let (data, response) = try await session.data(for: req)
        try checkHTTPStatus(response)
        let result = try JSONDecoder().decode(ForkSessionResponse.self, from: data)
        return result.session
    }

    // MARK: - Error Handling

    private func checkHTTPStatus(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        switch http.statusCode {
        case 200...299: return
        case 401: throw APIError.unauthorized
        case 404: throw APIError.notFound
        case 429: throw APIError.rateLimited
        case 500...599: throw APIError.serverError(status: http.statusCode)
        default: throw APIError.unknown(status: http.statusCode)
        }
    }
}

// MARK: - Timeout Helper

/// Run an async operation with a hard timeout. Throws URLError.timedOut on expiry.
func withTimeout<T>(seconds: Double, operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask(operation: operation)
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw URLError(.timedOut)
        }
        guard let result = try await group.next() else { throw URLError(.timedOut) }
        group.cancelAll()
        return result
    }
}

// MARK: - API Errors

enum APIError: LocalizedError {
    case invalidResponse
    case invalidURL(String)
    case unauthorized
    case notFound
    case rateLimited
    case serverError(status: Int)
    case unknown(status: Int)
    case invalidEndpoint(String)
    case sseParseError(String)
    case connectionRefused

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid response from server"
        case .invalidURL(let url): return "Invalid URL: \(url)"
        case .unauthorized: return "Invalid API key"
        case .notFound: return "Resource not found"
        case .rateLimited: return "Rate limited — too many requests"
        case .serverError(let s): return "Server error (HTTP \(s))"
        case .unknown(let s): return "Unknown error (HTTP \(s))"
        case .invalidEndpoint(let message): return message
        case .sseParseError(let d): return "Failed to parse SSE event: \(d)"
        case .connectionRefused: return "Cannot connect to Hermes. Check your URL and network (Tailscale connected?)"
        }
    }
}
