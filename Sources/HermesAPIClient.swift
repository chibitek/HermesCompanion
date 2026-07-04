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

    init(config: ConnectionConfig) {
        self.config = config
        let cfg = URLSessionConfiguration.default
        // Hermes turns can legitimately take several minutes on large contexts
        // or slow providers. Keep the request alive long enough for gateway SSE
        // keepalives and long-running non-streaming fallbacks.
        cfg.timeoutIntervalForRequest = 600
        cfg.timeoutIntervalForResource = 1_800
        cfg.waitsForConnectivity = true
        self.session = URLSession(configuration: cfg)
    }

    private var baseURL: String { config.normalizedBaseURL }

    private func authHeaders() -> [String: String] {
        ["Authorization": "Bearer \(config.apiKey)",
         "Content-Type": "application/json"]
    }

    private func makeURL(path: String) -> URL {
        let cleanPath = path.hasPrefix("/") ? path : "/\(path)"
        return URL(string: baseURL + cleanPath)!
    }

    // MARK: - Health

    /// GET /health — no auth required, used for connection test
    func checkHealth() async throws -> HealthResponse {
        let (data, response) = try await session.data(from: makeURL(path: "/health"))
        try checkHTTPStatus(response)
        return try JSONDecoder().decode(HealthResponse.self, from: data)
    }

    // MARK: - Capabilities

    /// GET /v1/capabilities
    func getCapabilities() async throws -> CapabilitiesResponse {
        var req = URLRequest(url: makeURL(path: "/v1/capabilities"))
        req.httpMethod = "GET"
        authHeaders().forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }
        let (data, response) = try await session.data(for: req)
        try checkHTTPStatus(response)
        return try JSONDecoder().decode(CapabilitiesResponse.self, from: data)
    }

    // MARK: - Sessions

    /// GET /api/sessions
    func listSessions() async throws -> [HermesSession] {
        var req = URLRequest(url: makeURL(path: "/api/sessions"))
        req.httpMethod = "GET"
        authHeaders().forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }
        let (data, response) = try await session.data(for: req)
        try checkHTTPStatus(response)
        let result = try JSONDecoder().decode(SessionListResponse.self, from: data)
        return result.data
    }

    /// POST /api/sessions
    func createSession(title: String? = nil) async throws -> HermesSession {
        var req = URLRequest(url: makeURL(path: "/api/sessions"))
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
        var req = URLRequest(url: makeURL(path: "/api/sessions/\(sessionId)/messages"))
        req.httpMethod = "GET"
        authHeaders().forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }
        let (data, response) = try await session.data(for: req)
        try checkHTTPStatus(response)
        let result = try JSONDecoder().decode(SessionMessagesResponse.self, from: data)
        return result.data
    }

    /// DELETE /api/sessions/{id}
    func deleteSession(sessionId: String) async throws {
        var req = URLRequest(url: makeURL(path: "/api/sessions/\(sessionId)"))
        req.httpMethod = "DELETE"
        authHeaders().forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }
        let (_, response) = try await session.data(for: req)
        try checkHTTPStatus(response)
    }

    // MARK: - Skills

    /// GET /v1/skills
    func listSkills() async throws -> [Skill] {
        var req = URLRequest(url: makeURL(path: "/v1/skills"))
        req.httpMethod = "GET"
        authHeaders().forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }
        let (data, response) = try await session.data(for: req)
        try checkHTTPStatus(response)
        let result = try JSONDecoder().decode(SkillsResponse.self, from: data)
        return result.data
    }

    // MARK: - Chat (non-streaming)

    /// POST /api/sessions/{id}/chat
    /// When images are provided, sends multimodal content (text + image_url parts).
    func sendChat(sessionId: String, message: String, systemMessage: String? = nil, images: [Data] = []) async throws -> SessionChatResponse {
        var req = URLRequest(url: makeURL(path: "/api/sessions/\(sessionId)/chat"))
        req.httpMethod = "POST"
        authHeaders().forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }

        let body: Data
        if images.isEmpty {
            // Plain text message
            let chatBody = SessionChatRequest(message: message, systemMessage: systemMessage)
            body = try JSONEncoder().encode(chatBody)
        } else {
            // Multimodal: build content parts array
            var contentParts: [[String: Any]] = []
            if !message.isEmpty {
                contentParts.append(["type": "text", "text": message])
            }
            for imageData in images {
                let base64 = imageData.base64EncodedString()
                // Detect MIME type from data header
                let mimeType = detectMimeType(imageData)
                let dataUrl = "data:\(mimeType);base64,\(base64)"
                contentParts.append([
                    "type": "image_url",
                    "image_url": ["url": dataUrl]
                ])
            }
            // Build the request with multimodal message field
            var bodyDict: [String: Any] = ["message": contentParts]
            if let sys = systemMessage {
                bodyDict["system_message"] = sys
            }
            body = try JSONSerialization.data(withJSONObject: bodyDict)
        }
        req.httpBody = body

        let (data, response) = try await session.data(for: req)
        try checkHTTPStatus(response)
        return try JSONDecoder().decode(SessionChatResponse.self, from: data)
    }

    /// Detect MIME type from image data header bytes.
    private func detectMimeType(_ data: Data) -> String {
        guard data.count >= 2 else { return "image/jpeg" }
        let bytes = [UInt8](data.prefix(12))
        // JPEG: FF D8
        if bytes[0] == 0xFF && bytes[1] == 0xD8 { return "image/jpeg" }
        // PNG: 89 50 4E 47
        if bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47 {
            return "image/png"
        }
        // GIF: 47 49 46
        if bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46 {
            return "image/gif"
        }
        // WebP: 52 49 46 46 ... 57 45 42 50
        if data.count >= 12 && bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 {
            if bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50 {
                return "image/webp"
            }
        }
        // HEIC: starts with EXIF header
        if data.count >= 12 && bytes[4] == 0x66 && bytes[5] == 0x74 && bytes[6] == 0x79 && bytes[7] == 0x70 {
            return "image/heic"
        }
        return "image/jpeg"
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
    func streamChat(sessionId: String, message: String, systemMessage: String? = nil) async throws -> AsyncThrowingStream<SSEEventPayload, Error> {
        var req = URLRequest(url: makeURL(path: "/api/sessions/\(sessionId)/chat/stream"))
        req.httpMethod = "POST"
        authHeaders().forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        let body = SessionChatRequest(message: message, systemMessage: systemMessage)
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
                        payload = SSEEventPayload(
                            event: eventBuffer,
                            sessionId: nil, runId: nil, message_id: nil,
                            delta: nil, content: nil, toolName: nil,
                            preview: nil, args: nil,
                            completed: nil, partial: nil, interrupted: nil,
                            usage: nil, message: dataBuffer
                        )
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

    // MARK: - Runs (async execution)

    /// POST /v1/runs — start an async run, returns run_id immediately
    func startRun(input: String, instructions: String? = nil, sessionId: String? = nil) async throws -> RunResponse {
        var req = URLRequest(url: makeURL(path: "/v1/runs"))
        req.httpMethod = "POST"
        authHeaders().forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }

        let body = RunRequest(input: input, instructions: instructions, sessionId: sessionId)
        req.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: req)
        try checkHTTPStatus(response)
        return try JSONDecoder().decode(RunResponse.self, from: data)
    }

    /// GET /v1/runs/{run_id}/events — SSE stream of run events
    func streamRunEvents(runId: String) async throws -> AsyncThrowingStream<SSEEventPayload, Error> {
        var req = URLRequest(url: makeURL(path: "/v1/runs/\(runId)/events"))
        req.httpMethod = "GET"
        authHeaders().forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        let (bytes, response) = try await session.bytes(for: req)
        try checkHTTPStatus(response)

        return AsyncThrowingStream { continuation in
            let task = Task {
                var eventBuffer = ""
                var dataBuffer = ""

                do {
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }

                        if line.hasPrefix("event: ") {
                            eventBuffer = String(line.dropFirst("event: ".count))
                        } else if line.hasPrefix("data: ") {
                            dataBuffer = String(line.dropFirst("data: ".count))
                        } else if line.isEmpty && !eventBuffer.isEmpty {
                            if let data = dataBuffer.data(using: .utf8) {
                                var payload = try? JSONDecoder().decode(SSEEventPayload.self, from: data)
                                if payload == nil {
                                    payload = SSEEventPayload(
                                        event: eventBuffer,
                                        sessionId: nil, runId: nil, message_id: nil,
                                        delta: nil, content: nil, toolName: nil,
                                        preview: nil, args: nil,
                                        completed: nil, partial: nil, interrupted: nil,
                                        usage: nil, message: dataBuffer
                                    )
                                } else {
                                    payload!.event = eventBuffer
                                }
                                if let payload = payload {
                                    continuation.yield(payload)
                                }
                            }
                            eventBuffer = ""
                            dataBuffer = ""
                        }
                    }
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

    /// POST /v1/runs/{run_id}/approval
    func resolveApproval(runId: String, choice: String, resolveAll: Bool = false) async throws {
        var req = URLRequest(url: makeURL(path: "/v1/runs/\(runId)/approval"))
        req.httpMethod = "POST"
        authHeaders().forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }

        let body = ApprovalResponse(choice: choice, all: resolveAll)
        req.httpBody = try JSONEncoder().encode(body)

        let (_, response) = try await session.data(for: req)
        try checkHTTPStatus(response)
    }

    /// POST /v1/runs/{run_id}/stop
    func stopRun(runId: String) async throws {
        var req = URLRequest(url: makeURL(path: "/v1/runs/\(runId)/stop"))
        req.httpMethod = "POST"
        authHeaders().forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }
        let (_, response) = try await session.data(for: req)
        try checkHTTPStatus(response)
    }

    // MARK: - Models

    /// GET /v1/models — list available models and route aliases.
    func getModels() async throws -> [ModelInfo] {
        var req = URLRequest(url: makeURL(path: "/v1/models"))
        req.httpMethod = "GET"
        authHeaders().forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }
        let (data, response) = try await session.data(for: req)
        try checkHTTPStatus(response)
        let result = try JSONDecoder().decode(ModelsResponse.self, from: data)
        return result.data
    }

    // MARK: - Toolsets

    /// GET /v1/toolsets — list toolsets, their tools, and enabled state.
    func getToolsets() async throws -> [ToolsetInfo] {
        var req = URLRequest(url: makeURL(path: "/v1/toolsets"))
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
        var req = URLRequest(url: makeURL(path: "/api/sessions/\(sessionId)"))
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
        var req = URLRequest(url: makeURL(path: "/api/sessions/\(sessionId)"))
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
        var req = URLRequest(url: makeURL(path: "/api/sessions/\(sessionId)/fork"))
        req.httpMethod = "POST"
        authHeaders().forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }

        let body = ForkSessionRequest(title: title)
        req.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: req)
        try checkHTTPStatus(response)
        let result = try JSONDecoder().decode(ForkSessionResponse.self, from: data)
        return result.session
    }

    // MARK: - Run Status (enriched)

    /// GET /v1/runs/{run_id} — pollable run status with model, timestamps, last event.
    func getRunStatus(runId: String) async throws -> RunStatusResponse {
        var req = URLRequest(url: makeURL(path: "/v1/runs/\(runId)"))
        req.httpMethod = "GET"
        authHeaders().forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }
        let (data, response) = try await session.data(for: req)
        try checkHTTPStatus(response)
        return try JSONDecoder().decode(RunStatusResponse.self, from: data)
    }

    // MARK: - Cron Jobs

    /// GET /api/jobs — list all cron jobs.
    func listCronJobs(includeDisabled: Bool = false) async throws -> [CronJob] {
        var path = "/api/jobs"
        if includeDisabled {
            path += "?include_disabled=true"
        }
        var req = URLRequest(url: makeURL(path: path))
        req.httpMethod = "GET"
        authHeaders().forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }
        let (data, response) = try await session.data(for: req)
        try checkHTTPStatus(response)
        let result = try JSONDecoder().decode(CronJobListResponse.self, from: data)
        return result.jobs
    }

    /// GET /api/jobs/{id} — get a single cron job.
    func getCronJob(jobId: String) async throws -> CronJob {
        var req = URLRequest(url: makeURL(path: "/api/jobs/\(jobId)"))
        req.httpMethod = "GET"
        authHeaders().forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }
        let (data, response) = try await session.data(for: req)
        try checkHTTPStatus(response)
        let result = try JSONDecoder().decode(CronJobResponse.self, from: data)
        return result.job
    }

    /// POST /api/jobs — create a new cron job.
    func createCronJob(
        name: String,
        schedule: String,
        prompt: String,
        deliver: String? = nil,
        skills: [String]? = nil,
        repeat: Int? = nil
    ) async throws -> CronJob {
        var req = URLRequest(url: makeURL(path: "/api/jobs"))
        req.httpMethod = "POST"
        authHeaders().forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }

        let body = CreateCronJobRequest(
            name: name,
            schedule: schedule,
            prompt: prompt,
            deliver: deliver,
            skills: skills,
            repeat: `repeat`
        )
        req.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: req)
        try checkHTTPStatus(response)
        let result = try JSONDecoder().decode(CronJobResponse.self, from: data)
        return result.job
    }

    /// PATCH /api/jobs/{id} — update a cron job. Only non-nil fields are sent.
    func updateCronJob(
        jobId: String,
        name: String? = nil,
        schedule: String? = nil,
        prompt: String? = nil,
        deliver: String? = nil,
        skills: [String]? = nil,
        repeat: Int? = nil,
        enabled: Bool? = nil
    ) async throws -> CronJob {
        var req = URLRequest(url: makeURL(path: "/api/jobs/\(jobId)"))
        req.httpMethod = "PATCH"
        authHeaders().forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }

        let body = UpdateCronJobRequest(
            name: name,
            schedule: schedule,
            prompt: prompt,
            deliver: deliver,
            skills: skills,
            repeat: `repeat`,
            enabled: enabled
        )
        req.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: req)
        try checkHTTPStatus(response)
        let result = try JSONDecoder().decode(CronJobResponse.self, from: data)
        return result.job
    }

    /// DELETE /api/jobs/{id} — delete a cron job.
    func deleteCronJob(jobId: String) async throws {
        var req = URLRequest(url: makeURL(path: "/api/jobs/\(jobId)"))
        req.httpMethod = "DELETE"
        authHeaders().forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }
        let (_, response) = try await session.data(for: req)
        try checkHTTPStatus(response)
    }

    /// POST /api/jobs/{id}/pause — pause a cron job.
    func pauseCronJob(jobId: String) async throws -> CronJob {
        var req = URLRequest(url: makeURL(path: "/api/jobs/\(jobId)/pause"))
        req.httpMethod = "POST"
        authHeaders().forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }
        let (data, response) = try await session.data(for: req)
        try checkHTTPStatus(response)
        let result = try JSONDecoder().decode(CronJobResponse.self, from: data)
        return result.job
    }

    /// POST /api/jobs/{id}/resume — resume a paused cron job.
    func resumeCronJob(jobId: String) async throws -> CronJob {
        var req = URLRequest(url: makeURL(path: "/api/jobs/\(jobId)/resume"))
        req.httpMethod = "POST"
        authHeaders().forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }
        let (data, response) = try await session.data(for: req)
        try checkHTTPStatus(response)
        let result = try JSONDecoder().decode(CronJobResponse.self, from: data)
        return result.job
    }

    /// POST /api/jobs/{id}/run — trigger immediate execution of a cron job.
    func runCronJob(jobId: String) async throws -> CronJob {
        var req = URLRequest(url: makeURL(path: "/api/jobs/\(jobId)/run"))
        req.httpMethod = "POST"
        authHeaders().forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }
        let (data, response) = try await session.data(for: req)
        try checkHTTPStatus(response)
        let result = try JSONDecoder().decode(CronJobResponse.self, from: data)
        return result.job
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