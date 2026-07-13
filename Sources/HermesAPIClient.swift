import Foundation

/// Handles all HTTP communication with the Hermes Agent API server.
///
/// All endpoints use Bearer token auth. The base URL is user-configured
/// (e.g., http://100.x.x.x:8642 via Tailscale, or http://192.168.1.50:8642 via LAN).
///
/// This client is completely generic — no hardcoded URLs or credentials.
final class HermesAPIClient: Sendable {
    private let session: URLSession
    private let config: ConnectionConfig

    /// PUT /model on the model-switch helper (port 8643 on same host).
    /// The explicit provider keeps aggregator model IDs (for example
    /// `anthropic/claude-*` routed by OpenRouter) from being misclassified by
    /// their author prefix.
    func switchGatewayModel(_ modelId: String, provider: String? = nil) async {
        var host = config.normalizedBaseURL
        let usesHTTPS = host.hasPrefix("https://")
        if host.hasPrefix("http://") { host = String(host.dropFirst(7)) }
        if host.hasPrefix("https://") { host = String(host.dropFirst(8)) }
        // Strip any port suffix
        if let colon = host.firstIndex(of: ":") {
            host = String(host[..<colon])
        }
        let scheme = usesHTTPS ? "https" : "http"
        guard let url = URL(string: "\(scheme)://\(host):8643/model") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        var payload = ["model": modelId]
        if let provider, !provider.isEmpty {
            payload["provider"] = provider
        }
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        req.timeoutInterval = 5
        _ = try? await session.data(for: req)
    }

    init(config: ConnectionConfig) {
        self.config = config
        let cfg = URLSessionConfiguration.default
        // Hermes turns can legitimately take several minutes on large contexts
        // or slow providers. Keep the request alive long enough for gateway SSE
        // keepalives and long-running non-streaming fallbacks.
        cfg.timeoutIntervalForRequest = 600
        cfg.timeoutIntervalForResource = 1_800
        cfg.waitsForConnectivity = true
        cfg.networkServiceType = .background
        // Allow the session to continue in the background when the app
        // is suspended (e.g., user switched to another app mid-response).
        // Combined with UIBackgroundModes: audio, this keeps the SSE
        // stream alive and TTS playing.
        cfg.allowsConstrainedNetworkAccess = true
        cfg.allowsExpensiveNetworkAccess = true
        self.session = URLSession(configuration: cfg)
    }

    private var baseURL: String { config.normalizedBaseURL }

    private func authHeaders() -> [String: String] {
        ["Authorization": "Bearer \(config.apiKey)",
         "Content-Type": "application/json"]
    }

    private func makeURL(path: String) throws -> URL {
        let cleanPath = path.hasPrefix("/") ? path : "/\(path)"
        // URL-encode each path segment to handle special characters in IDs
        let encodedPath = cleanPath.split(separator: "/", omittingEmptySubsequences: false)
            .map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
            .joined(separator: "/")
        guard let url = URL(string: baseURL + encodedPath) else {
            throw APIError.invalidURL(baseURL + encodedPath)
        }
        return url
    }

    // MARK: - Health

    /// GET /health — no auth required, used for connection test
    func checkHealth() async throws -> HealthResponse {
        let (data, response) = try await session.data(from: try makeURL(path: "/health"))
        try checkHTTPStatus(response)
        return try JSONDecoder().decode(HealthResponse.self, from: data)
    }

    // MARK: - Capabilities

    /// GET /v1/capabilities
    func getCapabilities() async throws -> CapabilitiesResponse {
        var req = URLRequest(url: try makeURL(path: "/v1/capabilities"))
        req.httpMethod = "GET"
        authHeaders().forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }
        let (data, response) = try await session.data(for: req)
        try checkHTTPStatus(response)
        return try JSONDecoder().decode(CapabilitiesResponse.self, from: data)
    }

    // MARK: - Sessions

    /// GET /api/sessions
    func listSessions() async throws -> [HermesSession] {
        var req = URLRequest(url: try makeURL(path: "/api/sessions"))
        req.httpMethod = "GET"
        authHeaders().forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }
        let (data, response) = try await session.data(for: req)
        try checkHTTPStatus(response)
        let result = try JSONDecoder().decode(SessionListResponse.self, from: data)
        return result.data
    }

    /// POST /api/sessions
    func createSession(title: String? = nil) async throws -> HermesSession {
        var req = URLRequest(url: try makeURL(path: "/api/sessions"))
        req.httpMethod = "POST"
        authHeaders().forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }

        let body = CreateSessionRequest(title: title)
        req.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: req)
        try checkHTTPStatus(response)
        // Server returns {"object": "hermes.session", "session": {...}}
        let wrapper = try JSONDecoder().decode(CreateSessionResponse.self, from: data)
        return wrapper.session
    }

    /// GET /api/sessions/{id}/messages
    func getMessages(sessionId: String) async throws -> [SessionMessage] {
        var req = URLRequest(url: try makeURL(path: "/api/sessions/\(sessionId)/messages"))
        req.httpMethod = "GET"
        authHeaders().forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }
        let (data, response) = try await session.data(for: req)
        try checkHTTPStatus(response)
        let result = try JSONDecoder().decode(SessionMessagesResponse.self, from: data)
        return result.data
    }

    /// DELETE /api/sessions/{id}
    func deleteSession(sessionId: String) async throws {
        var req = URLRequest(url: try makeURL(path: "/api/sessions/\(sessionId)"))
        req.httpMethod = "DELETE"
        authHeaders().forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }
        let (_, response) = try await session.data(for: req)
        try checkHTTPStatus(response)
    }

    // MARK: - Skills

    /// GET /v1/skills
    func listSkills() async throws -> [Skill] {
        var req = URLRequest(url: try makeURL(path: "/v1/skills"))
        req.httpMethod = "GET"
        authHeaders().forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }
        let (data, response) = try await session.data(for: req)
        try checkHTTPStatus(response)
        let result = try JSONDecoder().decode(SkillsResponse.self, from: data)
        return result.data
    }

    // MARK: - Chat (non-streaming)

    /// POST /api/sessions/{id}/chat
    /// When images or files are provided, sends multimodal content (text + image_url/file parts).
    /// Images should already be JPEG-encoded by the caller.
    /// File attachments are sent as base64 data URLs with appropriate MIME types.
    func sendChat(
        sessionId: String,
        message: String,
        systemMessage: String? = nil,
        model: String? = nil,
        images: [Data] = [],
        attachments: [AttachmentData] = []
    ) async throws -> SessionChatResponse {
        var req = URLRequest(url: try makeURL(path: "/api/sessions/\(sessionId)/chat"))
        req.httpMethod = "POST"
        authHeaders().forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }

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
                let dataUrl = "data:image/jpeg;base64,\(base64)"
                contentParts.append([
                    "type": "image_url",
                    "image_url": ["url": dataUrl]
                ])
            }
            // Attachment-based images and files
            for attachment in attachments {
                let base64 = attachment.data.base64EncodedString()
                if attachment.isImage {
                    // Image attachment
                    let dataUrl = "data:\(attachment.mimeType);base64,\(base64)"
                    contentParts.append([
                        "type": "image_url",
                        "image_url": ["url": dataUrl]
                    ])
                } else if MimeTypeResolver.isTextType(attachment.mimeType) {
                    // Text-based files: try to send as inline text for better LLM comprehension
                    if let textContent = String(data: attachment.data, encoding: .utf8) {
                        let fileLabel = "`\(attachment.fileExtension)\n\(textContent)\n`"
                        contentParts.append([
                            "type": "text",
                            "text": "File: \(attachment.fileName)\n\(fileLabel)"
                        ])
                    } else {
                        // Cannot decode as text, send as base64
                        let dataUrl = "data:\(attachment.mimeType);base64,\(base64)"
                        contentParts.append([
                            "type": "image_url",
                            "image_url": ["url": dataUrl]
                        ])
                    }
                } else {
                    // Binary files: send as base64 data URL
                    let dataUrl = "data:\(attachment.mimeType);base64,\(base64)"
                    contentParts.append([
                        "type": "image_url",
                        "image_url": ["url": dataUrl]
                    ])
                }
            }
            // Build the request with multimodal message field
            var bodyDict: [String: Any] = ["message": contentParts]
            if let sys = systemMessage {
                bodyDict["system_message"] = sys
            }
            if let mdl = model {
                bodyDict["model"] = mdl
            }
            body = try JSONSerialization.data(withJSONObject: bodyDict)
        }
        req.httpBody = body

        let (data, response) = try await session.data(for: req)
        try checkHTTPStatus(response)
        return try JSONDecoder().decode(SessionChatResponse.self, from: data)
    }

    // MARK: - Chat (streaming via SSE)

    /// POST /api/sessions/{id}/chat/stream
    ///
    /// Returns an AsyncSequence of SSE events. Use with `for await event in stream { ... }`.
    ///
    /// Events:
    ///   - run.started, message.started
    ///   - assistant.delta (token-by-token text)
    ///   - tool.progress, tool.started, tool.completed, tool.failed
    ///   - assistant.completed, run.completed
    ///   - error, done
    func streamChat(sessionId: String, message: String, systemMessage: String? = nil, model: String? = nil) async throws -> AsyncThrowingStream<SSEEventPayload, Error> {
        var req = URLRequest(url: try makeURL(path: "/api/sessions/\(sessionId)/chat/stream"))
        req.httpMethod = "POST"
        authHeaders().forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        let body = SessionChatRequest(message: message, systemMessage: systemMessage, model: model)
        req.httpBody = try JSONEncoder().encode(body)

        let (bytes, response) = try await session.bytes(for: req)
        try checkHTTPStatus(response)

        return AsyncThrowingStream { continuation in
            let task = Task {
                var eventBuffer = ""
                var dataBuffer = ""

                // Flush the currently-buffered SSE frame (event: + data:) as one payload.
                func flush() {
                    // A frame with neither an event type nor data is a bare boundary
                    // (e.g. the blank line that follows a `: keepalive` comment). Skip it.
                    guard !eventBuffer.isEmpty || !dataBuffer.isEmpty else { return }
                    defer { eventBuffer = ""; dataBuffer = "" }

                    guard let data = dataBuffer.data(using: .utf8) else { return }
                    var payload = try? JSONDecoder().decode(SSEEventPayload.self, from: data)
                    if payload == nil {
                        // Fallback for done/error frames whose data isn't full JSON.
                        // Only pass the raw buffer as message for error/done events.
                        // For any other event type, do NOT create a fallback payload
                        // with raw data — that would leak raw JSON into the chat UI.
                        if eventBuffer == "error" || eventBuffer == "done" || eventBuffer.isEmpty {
                            payload = SSEEventPayload(
                                event: eventBuffer,
                                sessionId: nil, runId: nil, message_id: nil,
                                delta: nil, content: nil, toolName: nil,
                                preview: nil, args: nil,
                                completed: nil, partial: nil, interrupted: nil,
                                usage: nil, message: dataBuffer
                            )
                        } else {
                            return
                        }
                    } else {
                        // The event type comes from the SSE `event:` line, not the JSON.
                        payload!.event = eventBuffer
                    }
                    if let payload = payload {
                        continuation.yield(payload)
                    }
                }

                do {
                    for try await rawLine in bytes.lines {
                        if Task.isCancelled { break }

                        // Tolerate CRLF line endings — strip a trailing CR so an
                        // otherwise-empty boundary line isn't misread as "\r".
                        let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine

                        if line.isEmpty {
                            // Blank line = end of the current SSE frame.
                            flush()
                            continue
                        }

                        // SSE comment line (keepalive). Ignore — do NOT let it
                        // clobber a partially-built frame.
                        if line.hasPrefix(":") {
                            continue
                        }

                        if line.hasPrefix("event:") {
                            eventBuffer = trimSSEValue(line, field: "event")
                        } else if line.hasPrefix("data:") {
                            let value = trimSSEValue(line, field: "data")
                            // SSE allows multiple data: lines per frame; concatenate with \n.
                            dataBuffer = dataBuffer.isEmpty ? value : dataBuffer + "\n" + value
                        }
                        // id:/retry: and unknown fields are intentionally ignored.
                    }
                    // Flush any frame left unterminated when the stream ends.
                    flush()
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// Extract an SSE field value, tolerating both "field: value" and "field:value".
    private func trimSSEValue(_ line: String, field: String) -> String {
        var value = String(line.dropFirst(field.count + 1)) // drop "field:"
        if value.hasPrefix(" ") { value.removeFirst() }      // drop one optional leading space
        return value
    }

    // MARK: - Models

    /// GET /v1/models — list available models and route aliases.
    /// Pass refresh=true only for a user-triggered refresh; this asks the
    /// gateway to bypass its provider model cache.
    func getModelCatalog(refresh: Bool = false) async throws -> ModelsResponse {
        let baseModelsURL = try makeURL(path: "/v1/models")
        guard var components = URLComponents(url: baseModelsURL, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL(baseModelsURL.absoluteString)
        }
        if refresh {
            components.queryItems = [URLQueryItem(name: "refresh", value: "1")]
        }
        guard let modelsURL = components.url else {
            throw APIError.invalidURL(baseModelsURL.absoluteString)
        }
        var req = URLRequest(url: modelsURL)
        req.httpMethod = "GET"
        authHeaders().forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }
        let (data, response) = try await session.data(for: req)
        try checkHTTPStatus(response)
        return try JSONDecoder().decode(ModelsResponse.self, from: data)
    }

    func getModels(refresh: Bool = false) async throws -> [ModelInfo] {
        try await getModelCatalog(refresh: refresh).data
    }

    // MARK: - Toolsets

    /// GET /v1/toolsets — list toolsets, their tools, and enabled state.
    func getToolsets() async throws -> [ToolsetInfo] {
        var req = URLRequest(url: try makeURL(path: "/v1/toolsets"))
        req.httpMethod = "GET"
        authHeaders().forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }
        let (data, response) = try await session.data(for: req)
        try checkHTTPStatus(response)
        let result = try JSONDecoder().decode(ToolsetsResponse.self, from: data)
        return result.data
    }

    // MARK: - Session Detail

    /// GET /api/sessions/{id} — full session metadata (tokens, cost, lineage).
    func getSession(sessionId: String) async throws -> SessionDetail {
        var req = URLRequest(url: try makeURL(path: "/api/sessions/\(sessionId)"))
        req.httpMethod = "GET"
        authHeaders().forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }
        let (data, response) = try await session.data(for: req)
        try checkHTTPStatus(response)
        let result = try JSONDecoder().decode(GetSessionResponse.self, from: data)
        return result.session
    }

    // MARK: - Session Rename

    /// PATCH /api/sessions/{id} — update session title.
    func patchSession(sessionId: String, title: String?) async throws -> HermesSession {
        var req = URLRequest(url: try makeURL(path: "/api/sessions/\(sessionId)"))
        req.httpMethod = "PATCH"
        authHeaders().forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }

        let body = PatchSessionRequest(title: title)
        req.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: req)
        try checkHTTPStatus(response)
        // Server returns {"object": "hermes.session", "session": {...}}
        // The session payload uses the same keys as HermesSession
        let result = try JSONDecoder().decode(CreateSessionResponse.self, from: data)
        return result.session
    }

    // MARK: - Session Fork

    /// POST /api/sessions/{id}/fork — branch a session, carrying conversation history.
    func forkSession(sessionId: String, title: String? = nil) async throws -> HermesSession {
        var req = URLRequest(url: try makeURL(path: "/api/sessions/\(sessionId)/fork"))
        req.httpMethod = "POST"
        authHeaders().forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }

        let body = ForkSessionRequest(title: title)
        req.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: req)
        try checkHTTPStatus(response)
        let result = try JSONDecoder().decode(ForkSessionResponse.self, from: data)
        return result.session
    }

    // MARK: - Error Handling

    private func checkHTTPStatus(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        switch http.statusCode {
        case 200...299:
            return
        case 401:
            throw APIError.unauthorized
        case 404:
            throw APIError.notFound
        case 429:
            throw APIError.rateLimited
        case 500...599:
            throw APIError.serverError(status: http.statusCode)
        default:
            throw APIError.unknown(status: http.statusCode)
        }
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
        case .sseParseError(let d): return "Failed to parse SSE event: \(d)"
        case .connectionRefused: return "Cannot connect to Hermes. Check your URL and network (Tailscale connected?)"
        }
    }
}