import Foundation

private final class AttachmentRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// Handles all HTTP communication with the Hermes Agent API server.
///
/// All endpoints use Bearer token auth. The base URL is user-configured
/// (e.g., http://localhost:8642 via Tailscale, or http://192.168.1.50:8642 via LAN).
///
/// This client is completely generic — no hardcoded URLs or credentials.
final class HermesAPIClient: Sendable {
    private let session: URLSession
    private let config: ConnectionConfig

    init(config: ConnectionConfig, session: URLSession? = nil) {
        self.config = config
        if let session {
            self.session = session
            return
        }
        let cfg = URLSessionConfiguration.default
        // Hermes turns can legitimately take several minutes on large contexts.
        cfg.timeoutIntervalForRequest = 600
        cfg.timeoutIntervalForResource = 1_800
        cfg.waitsForConnectivity = true
        cfg.networkServiceType = .responsiveData
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
        var req = URLRequest(url: try makeURL(path: path, queryItems: queryItems), cachePolicy: .reloadIgnoringLocalCacheData)
        req.httpMethod = method
        authHeaders().forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }
        return req
    }

    private func get<T: Decodable>(path: String, queryItems: [URLQueryItem]? = nil, type: T.Type) async throws -> T {
        let request = try request(method: "GET", path: path, queryItems: queryItems)
        let (data, response) = try await withTimeout(seconds: 20) { [session] in
            try await session.data(for: request)
        }
        try checkHTTPStatus(response, data: data)
        return try decode(type, data: data, response: response)
    }

    private func sendEmpty(method: String, path: String) async throws {
        let (data, response) = try await session.data(for: try request(method: method, path: path))
        try checkHTTPStatus(response, data: data)
    }

    // MARK: - Server workspace

    func workspaceProjects() async throws -> WorkspaceProjects {
        try await get(path: "/api/companion/projects", type: WorkspaceProjects.self)
    }

    func workspaceProject(profile: String, id: String) async throws -> ServerProjectDetail {
        try await get(path: "/api/companion/project", queryItems: [
            URLQueryItem(name: "profile", value: profile),
            URLQueryItem(name: "project_id", value: id)
        ], type: ServerProjectDetail.self)
    }

    func workspaceBots() async throws -> WorkspaceBots {
        try await get(path: "/api/companion/bots", type: WorkspaceBots.self)
    }

    func projectHistory(profile: String, projectID: String, sessionID: String, offset: Int) async throws -> BotHistory {
        let result = try await get(path: "/api/companion/project-history", queryItems: [
            URLQueryItem(name: "profile", value: profile),
            URLQueryItem(name: "project_id", value: projectID),
            URLQueryItem(name: "session_id", value: sessionID),
            URLQueryItem(name: "offset", value: String(offset))
        ], type: ProjectSessionHistory.self)
        guard result.matches(profile: profile, projectID: projectID, sessionID: sessionID, offset: offset) else {
            throw APIError.invalidResponse
        }
        return result.history
    }

    func botHistory(profile: String, offset: Int) async throws -> BotHistory {
        let result = try await get(path: "/api/companion/bot-history", queryItems: [
            URLQueryItem(name: "profile", value: profile),
            URLQueryItem(name: "offset", value: String(offset))
        ], type: BotHistory.self)
        guard result.profile == profile, result.pagination.offset == offset else {
            throw APIError.invalidResponse
        }
        return result
    }

    func workspaceBoards() async throws -> WorkspaceBoards {
        try await get(path: "/api/companion/boards", type: WorkspaceBoards.self)
    }

    func workspaceBoard(slug: String) async throws -> ServerBoardDetail {
        try await get(path: "/api/companion/board", queryItems: [
            URLQueryItem(name: "board", value: slug)
        ], type: ServerBoardDetail.self)
    }

    func workspaceTask(board: String, id: String) async throws -> ServerTaskDetail {
        let result = try await get(path: "/api/companion/task", queryItems: [
            URLQueryItem(name: "board", value: board),
            URLQueryItem(name: "task_id", value: id)
        ], type: ServerTaskDetail.self)
        guard result.matches(board: board, taskID: id) else { throw APIError.invalidResponse }
        return result
    }

    func managedProjects(profile: String) async throws -> ManagedProjects {
        let result = try await get(path: "/api/companion/project-records", queryItems: [URLQueryItem(name: "profile", value: profile)], type: ManagedProjects.self)
        guard result.profile == profile else {
            throw APIError.invalidEndpoint("GET /api/companion/project-records returned a different profile. Refresh the selected profile before editing projects.")
        }
        return result
    }

    func managedProject(profile: String, id: String) async throws -> ManagedProject {
        let result = try await get(path: "/api/companion/project-record", queryItems: [URLQueryItem(name: "profile", value: profile), URLQueryItem(name: "project_id", value: id)], type: ManagedProjectReceipt.self)
        return try checkedProject(result, profile: profile, id: id, path: "project-record")
    }

    func saveProject(profile: String, id: String?, payload: ProjectWrite) async throws -> ManagedProject {
        let path = id == nil ? "projects-create" : "project-record"
        let result: ManagedProjectReceipt = try await writeProject(method: id == nil ? "POST" : "PATCH", path: path, profile: profile, id: id, body: payload)
        return try checkedProject(result, profile: profile, id: id, path: path)
    }

    enum ProjectFolderAction { case add, remove, primary }

    func changeProjectFolder(profile: String, id: String, action: ProjectFolderAction, payload: ProjectFolderWrite) async throws -> ManagedProject {
        let path = action == .primary ? "project-primary" : "project-folder"
        let result: ManagedProjectReceipt = try await writeProject(method: action == .remove ? "DELETE" : "POST", path: path, profile: profile, id: id, body: payload)
        return try checkedProject(result, profile: profile, id: id, path: path)
    }

    func archiveProject(profile: String, id: String, restore: Bool) async throws {
        let result: ManagedProjects = try await writeProject(method: "POST", path: "project-archive", profile: profile, id: id, body: ["restore": restore])
        guard result.profile == profile, result.projects.first(where: { $0.id == id })?.archived == !restore else {
            throw APIError.invalidEndpoint("POST /api/companion/project-archive did not confirm the requested archive state. Refresh this profile's project list.")
        }
    }

    func deleteProject(profile: String, id: String) async throws {
        let result: ManagedProjects = try await writeProject(method: "DELETE", path: "project-record", profile: profile, id: id, body: [String: String]())
        guard result.profile == profile, !result.projects.contains(where: { $0.id == id }) else {
            throw APIError.invalidEndpoint("DELETE /api/companion/project-record did not confirm removal from this profile. Refresh its project list before retrying.")
        }
    }

    func activateProject(profile: String, id: String?) async throws {
        let result: ManagedProjects = try await writeProject(method: "POST", path: "project-active", profile: profile, id: id, body: [String: String]())
        guard result.profile == profile, result.active_id == id else {
            throw APIError.invalidEndpoint("POST /api/companion/project-active did not confirm the requested active project. Refresh this profile's project list.")
        }
    }

    private func checkedProject(_ result: ManagedProjectReceipt, profile: String, id: String?, path: String) throws -> ManagedProject {
        guard result.profile == profile, !result.project.id.isEmpty, id == nil || result.project.id == id else {
            throw APIError.invalidEndpoint("/api/companion/\(path) returned a different profile/project or missing ID. Refresh the selected profile before retrying.")
        }
        return result.project
    }

    private func writeProject<Body: Encodable, Result: Decodable>(method: String, path: String,
        profile: String, id: String?, body: Body) async throws -> Result {
        var query = [URLQueryItem(name: "profile", value: profile)]
        if let id { query.append(URLQueryItem(name: "project_id", value: id)) }
        var req = try request(method: method, path: "/api/companion/" + path, queryItems: query)
        req.httpBody = try JSONEncoder().encode(body)
        req.timeoutInterval = 20
        let outgoing = req
        let (data, response) = try await withTimeout(seconds: 20) { [session] in
            try await session.data(for: outgoing)
        }
        try checkHTTPStatus(response, data: data)
        return try decode(Result.self, data: data, response: response)
    }

    func submitRun(_ payload: DurableRunRequest, idempotencyKey: String) async throws -> DurableRunAccepted {
        let result: DurableRunAccepted = try await runPost(path: "/v1/runs", body: payload, idempotencyKey: idempotencyKey)
        _ = try checkedRunID(result.run_id)
        return result
    }

    func runStatus(id: String) async throws -> DurableRunStatus {
        let id = try checkedRunID(id)
        let result = try await get(path: "/v1/runs/" + id, type: DurableRunStatus.self)
        guard result.run_id == id else {
            throw APIError.invalidEndpoint("GET /v1/runs/\(id) returned another run. The displayed controls cannot be used until the gateway returns the requested run.")
        }
        return result
    }

    func runEvents(id: String, after sequence: Int? = nil) async throws -> AsyncThrowingStream<SSEEventPayload, Error> {
        var req = try request(method: "GET", path: "/v1/runs/" + checkedRunID(id) + "/events")
        if let sequence {
            guard sequence >= 0 else { throw APIError.invalidEndpoint("A run event cursor cannot be negative.") }
            req.setValue(String(sequence), forHTTPHeaderField: "Last-Event-ID")
        }
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        return try await eventStream(request: req, onKeepalive: nil)
    }

    func steerRun(id: String, text: String) async throws {
        let result: DurableRunControlReceipt = try await runPost(path: "/v1/runs/" + checkedRunID(id) + "/steer", body: ["input": text])
        guard result.run_id == id, result.accepted == true else {
            throw APIError.invalidEndpoint("POST /v1/runs/\(id)/steer did not confirm acceptance. Refresh run status before sending the guidance again.")
        }
    }

    func approveRun(id: String, requestID: String, choice: String) async throws {
        guard !requestID.isEmpty, ["once", "session", "always", "deny"].contains(choice) else {
            throw APIError.invalidEndpoint("Approval requires an exact request ID and a supported choice from the current run status.")
        }
        let result: DurableRunControlReceipt = try await runPost(path: "/v1/runs/" + checkedRunID(id) + "/approval", body: ["request_id": requestID, "choice": choice])
        guard result.run_id == id, result.request_id == requestID, result.choice == choice, result.resolved == 1 else {
            throw APIError.invalidEndpoint("POST /v1/runs/\(id)/approval did not confirm exactly this approval request. Refresh status before making another decision.")
        }
    }

    func stopRun(id: String) async throws {
        let result: DurableRunControlReceipt = try await runPost(path: "/v1/runs/" + checkedRunID(id) + "/stop", body: [String: String]())
        guard result.run_id == id, ["stopping", "completed", "failed", "cancelled", "interrupted"].contains(result.status ?? "") else {
            throw APIError.invalidEndpoint("POST /v1/runs/\(id)/stop did not confirm a stopping or terminal state. Check status before retrying; closing the view does not stop server work.")
        }
    }

    private func checkedRunID(_ id: String) throws -> String {
        guard id.hasPrefix("run_"), id.count > 4, id.count <= 256,
              id.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-" ).contains($0) }) else {
            throw APIError.invalidEndpoint("Invalid Hermes run ID. Copy the run_ identifier returned by this gateway; URLs and path separators are not accepted.")
        }
        return id
    }

    private func runPost<Body: Encodable, Result: Decodable>(path: String, body: Body, idempotencyKey: String? = nil) async throws -> Result {
        var req = try request(method: "POST", path: path)
        req.httpBody = try JSONEncoder().encode(body)
        if let idempotencyKey { req.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key") }
        req.timeoutInterval = 20
        let outgoing = req
        let (data, response) = try await withTimeout(seconds: 20) { [session] in try await session.data(for: outgoing) }
        try checkHTTPStatus(response, data: data)
        return try decode(Result.self, data: data, response: response)
    }

    func workspaceCapabilities() async throws -> WorkspaceCapabilities {
        try await get(path: "/api/companion/capabilities", type: WorkspaceCapabilities.self)
    }

    func createWorkspaceTask(board: String, payload: ServerTaskWrite) async throws -> ServerTaskWriteReceipt {
        let receipt: ServerTaskWriteReceipt = try await writeWorkspace(method: "POST", path: "/api/companion/tasks",
            board: board, taskID: nil, body: payload)
        guard receipt.board == board, !receipt.task.id.isEmpty else {
            throw APIError.invalidEndpoint("POST /api/companion/tasks returned an unrelated board or missing task ID. Refresh the board before retrying creation.")
        }
        return receipt
    }

    func updateWorkspaceTask(board: String, taskID: String, payload: ServerTaskWrite) async throws -> ServerTaskWriteReceipt {
        let receipt: ServerTaskWriteReceipt = try await writeWorkspace(method: "PATCH", path: "/api/companion/task",
            board: board, taskID: taskID, body: payload)
        guard receipt.board == board, receipt.task.id == taskID else {
            throw APIError.invalidEndpoint("PATCH /api/companion/task returned a different board or task. The save is unconfirmed; refresh the requested task before retrying.")
        }
        return receipt
    }

    func commentWorkspaceTask(board: String, taskID: String, body: String) async throws {
        let receipt: ServerTaskCommentReceipt = try await writeWorkspace(method: "POST", path: "/api/companion/task-comment",
            board: board, taskID: taskID, body: ["body": body])
        guard receipt.board == board, receipt.task_id == taskID, receipt.ok else {
            throw APIError.invalidEndpoint("POST /api/companion/task-comment did not confirm this task and board. Check the comments before retrying to avoid a duplicate.")
        }
    }

    private func writeWorkspace<Body: Encodable, Result: Decodable>(method: String, path: String,
        board: String, taskID: String?, body: Body) async throws -> Result {
        var query = [URLQueryItem(name: "board", value: board)]
        if let taskID { query.append(URLQueryItem(name: "task_id", value: taskID)) }
        var req = try request(method: method, path: path, queryItems: query)
        req.httpBody = try JSONEncoder().encode(body)
        req.timeoutInterval = 20
        let outgoing = req
        let (data, response) = try await withTimeout(seconds: 20) { [session] in
            try await session.data(for: outgoing)
        }
        try checkHTTPStatus(response, data: data)
        return try decode(Result.self, data: data, response: response)
    }

    // MARK: - Health

    func downloadTaskAttachment(board: String, taskID: String, attachment: ServerTaskAttachment) async throws -> URL {
        guard attachment.task_id == taskID, attachment.size >= 0 else { throw APIError.invalidResponse }
        let req = try request(method: "GET", path: "/api/companion/task-attachment", queryItems: [
            URLQueryItem(name: "board", value: board),
            URLQueryItem(name: "task_id", value: taskID),
            URLQueryItem(name: "attachment_id", value: String(attachment.id))
        ])
        let (temporary, response) = try await session.download(for: req, delegate: AttachmentRedirectPolicy())
        defer { try? FileManager.default.removeItem(at: temporary) }
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let handle = try FileHandle(forReadingFrom: temporary)
            defer { try? handle.close() }
            try checkHTTPStatus(response, data: try handle.read(upToCount: 16_384) ?? Data())
        } else {
            try checkHTTPStatus(response, data: Data())
        }
        try Task.checkCancellation()
        let size = try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize
        guard size == attachment.size else { throw APIError.invalidResponse }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("hermes-attachment-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        do {
            let file = directory.appendingPathComponent(attachment.safeFilename)
            try FileManager.default.moveItem(at: temporary, to: file)
            return file
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    /// GET /health — no auth required, used for connection test
    func checkHealth() async throws -> HealthResponse {
        let url = try makeURL(path: "/health")
        let (data, response) = try await withTimeout(seconds: 5) { [session] in
            try await session.data(from: url)
        }
        try checkHTTPStatus(response, data: data)
        return try decode(HealthResponse.self, data: data, response: response)
    }

    // MARK: - Capabilities

    func getCapabilities() async throws -> CapabilitiesResponse {
        try await get(path: "/v1/capabilities", type: CapabilitiesResponse.self)
    }

    func getDetailedHealth() async throws -> PlatformHealthResponse {
        try await get(path: "/health/detailed", type: PlatformHealthResponse.self)
    }

    // MARK: - Scheduled Jobs

    func listJobs(includeDisabled: Bool = true) async throws -> [HermesJob] {
        let res = try await get(
            path: "/api/jobs",
            queryItems: [URLQueryItem(name: "include_disabled", value: includeDisabled ? "true" : "false")],
            type: HermesJobsResponse.self
        )
        return res.jobs
    }

    func createJob(_ payload: HermesJobWrite) async throws -> HermesJob {
        var req = try request(method: "POST", path: "/api/jobs")
        req.httpBody = try JSONEncoder().encode(payload)
        let (data, response) = try await session.data(for: req)
        try checkHTTPStatus(response, data: data)
        return try decode(HermesJobResponse.self, data: data, response: response).job
    }

    func updateJob(jobId: String, updates: HermesJobWrite) async throws -> HermesJob {
        var req = try request(method: "PATCH", path: "/api/jobs/\(jobId)")
        req.httpBody = try JSONEncoder().encode(updates)
        let (data, response) = try await session.data(for: req)
        try checkHTTPStatus(response, data: data)
        return try decode(HermesJobResponse.self, data: data, response: response).job
    }

    func pauseJob(jobId: String) async throws {
        try await sendEmpty(method: "POST", path: "/api/jobs/\(jobId)/pause")
    }

    func resumeJob(jobId: String) async throws {
        try await sendEmpty(method: "POST", path: "/api/jobs/\(jobId)/resume")
    }

    func runJob(jobId: String) async throws {
        try await sendEmpty(method: "POST", path: "/api/jobs/\(jobId)/run")
    }

    func deleteJob(jobId: String) async throws {
        try await sendEmpty(method: "DELETE", path: "/api/jobs/\(jobId)")
    }

    func uploadArtifact(
        data: Data,
        fileName: String,
        mimeType: String
    ) async throws -> HermesArtifactReceipt {
        var req = try request(method: "POST", path: "/v1/artifacts/upload")
        req.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        req.setValue(fileName, forHTTPHeaderField: "X-Artifact-Filename")
        req.httpBody = data

        let (resp, response) = try await session.data(for: req)
        try checkHTTPStatus(response, data: resp)
        return try decode(HermesArtifactReceipt.self, data: resp, response: response)
    }

    // MARK: - Sessions

    /// GET /api/sessions
    func listSessions() async throws -> [HermesSession] {
        var allSessions: [HermesSession] = []
        var seenIDs = Set<String>()
        let pageSize = 100
        var offset = 0

        while true {
            try Task.checkCancellation()
            let res = try await get(
                path: "/api/sessions",
                queryItems: [
                    URLQueryItem(name: "limit", value: String(pageSize)),
                    URLQueryItem(name: "offset", value: String(offset)),
                    URLQueryItem(name: "archived", value: "include"),
                    URLQueryItem(name: "order", value: "recent"),
                    URLQueryItem(name: "include_hidden", value: "true")
                ],
                type: SessionListResponse.self
            )
            let fresh = res.data.filter { seenIDs.insert($0.id).inserted }
            allSessions.append(contentsOf: fresh)

            if let hasMore = res.hasMore {
                guard res.offset == nil || res.offset == offset else { throw APIError.invalidResponse }
                if !hasMore { break }
                guard !fresh.isEmpty else { throw APIError.invalidResponse }
                // Hermes appends pinned rows beyond its recency window. They
                // must not advance the server's offset or hide unseen sessions.
                offset += res.limit ?? pageSize
                continue
            }
            offset += res.data.count
            if let total = res.total, allSessions.count >= total { break }
            if res.data.isEmpty {
                guard res.total == nil else { throw APIError.invalidResponse }
                break
            }
            guard !fresh.isEmpty else { throw APIError.invalidResponse }
            if res.total == nil && res.data.count < pageSize { break }
        }

        return allSessions
    }

    /// POST /api/sessions
    func createSession(title: String? = nil, model: String? = nil, provider: String? = nil) async throws -> HermesSession {
        var req = try request(method: "POST", path: "/api/sessions")
        req.httpBody = try JSONEncoder().encode(CreateSessionRequest(title: title, model: model, provider: provider, requireModelLock: model == nil ? nil : true))
        let (data, response) = try await session.data(for: req)
        try checkHTTPStatus(response, data: data)
        // Server returns {"object": "hermes.session", "session": {...}}
        let wrapper = try decode(CreateSessionResponse.self, data: data, response: response)
        return wrapper.session
    }

    /// GET /api/sessions/{id}/messages
    func getMessages(sessionId: String) async throws -> [SessionMessage] {
        var messages: [SessionMessage] = []
        var ids = Set<Int>()
        var offset = 0
        while true {
            try Task.checkCancellation()
            let res = try await get(path: "/api/sessions/\(sessionId)/messages", queryItems: [
                URLQueryItem(name: "limit", value: "500"),
                URLQueryItem(name: "offset", value: String(offset)),
                URLQueryItem(name: "order", value: "oldest")
            ], type: SessionMessagesResponse.self)
            if let page = res.pagination {
                guard page.offset == offset, page.returned == res.data.count else { throw APIError.invalidResponse }
            }
            guard res.data.allSatisfy({ ids.insert($0.id).inserted }) else { throw APIError.invalidResponse }
            messages.append(contentsOf: res.data)
            if res.data.count < 500 { return messages }
            offset += res.data.count
        }
    }

    func getLatestMessages(sessionId: String) async throws -> [SessionMessage] {
        let page = try await get(path: "/api/sessions/\(sessionId)/messages", queryItems: [
            URLQueryItem(name: "limit", value: "50"),
            URLQueryItem(name: "offset", value: "0"),
            URLQueryItem(name: "order", value: "latest")
        ], type: SessionMessagesResponse.self)
        return page.data
    }

    /// DELETE /api/sessions/{id}
    func deleteSession(sessionId: String) async throws {
        let (data, response) = try await session.data(for: try request(method: "DELETE", path: "/api/sessions/\(sessionId)"))
        try checkHTTPStatus(response, data: data)
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
       try checkHTTPStatus(response, data: data)
       return try decode(ModelsResponse.self, data: data, response: response)
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
        try checkHTTPStatus(response, data: data)
        return try decode(SessionModelLockResponse.self, data: data, response: response).runtime
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
            for imageData in images where !attachments.contains(where: { $0.isImage && $0.data == imageData }) {
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
                        throw APIError.invalidEndpoint("Cannot send \(attachment.fileName): this text file is not UTF-8. Save it as UTF-8 and attach it again.")
                    }
                } else {
                    throw APIError.invalidEndpoint("Cannot send \(attachment.fileName) (\(attachment.mimeType)): this Hermes chat endpoint accepts images and UTF-8 text, but not binary documents. Export the document as text or images before attaching it.")
                }
            }
            var bodyDict: [String: Any] = ["message": contentParts]
            if let sys = systemMessage { bodyDict["system_message"] = sys }
            if let mdl = model { bodyDict["model"] = mdl }
            body = try JSONSerialization.data(withJSONObject: bodyDict)
        }
        req.httpBody = body

        let (data, response) = try await session.data(for: req)
        try checkHTTPStatus(response, data: data)
        return try decode(SessionChatResponse.self, data: data, response: response)
    }

    // MARK: - Chat (streaming via SSE)

    /// POST /api/sessions/{id}/chat/stream — returns AsyncSequence of SSE events.
    func streamChat(sessionId: String, message: String, systemMessage: String? = nil, model: String? = nil,
                    onKeepalive: (@Sendable () -> Void)? = nil) async throws -> AsyncThrowingStream<SSEEventPayload, Error> {
        var req = try request(method: "POST", path: "/api/sessions/\(sessionId)/chat/stream")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.httpBody = try JSONEncoder().encode(SessionChatRequest(message: message, systemMessage: systemMessage, model: model))

        return try await eventStream(request: req, onKeepalive: onKeepalive)
    }

    func workspaceChanges(onKeepalive: (@Sendable () -> Void)? = nil) async throws -> AsyncThrowingStream<SSEEventPayload, Error> {
        var req = try request(method: "GET", path: "/api/companion/changes")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        return try await eventStream(request: req, onKeepalive: onKeepalive)
    }

    private func eventStream(request req: URLRequest, onKeepalive: (@Sendable () -> Void)?) async throws -> AsyncThrowingStream<SSEEventPayload, Error> {
        let (bytes, response) = try await session.bytes(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            var body = Data()
            for try await byte in bytes {
                body.append(byte)
                if body.count >= 16_384 { break }
            }
            try checkHTTPStatus(response, data: body)
        }
        guard (response as? HTTPURLResponse)?.mimeType == "text/event-stream" else {
            throw APIError.invalidEndpoint("Chat stream returned a non-SSE response. Check that this URL points to the Hermes API gateway and that its proxy permits event streaming.")
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                var parser = SSEParser()
                var lines = SSELineDecoder()
                do {
                    for try await byte in bytes {
                        try Task.checkCancellation()
                        guard let line = try lines.consume(byte) else { continue }
                        if line.hasPrefix(":") { onKeepalive?() }
                        if let event = try parser.consume(line) { continuation.yield(event) }
                    }
                    if let event = try parser.consume(lines.finish()) { continuation.yield(event) }
                    if let event = try parser.finish() { continuation.yield(event) }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
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
        try checkHTTPStatus(response, data: data)
        let result = try decode(CreateSessionResponse.self, data: data, response: response)
        return result.session
    }

    // MARK: - Session Fork (POST /api/sessions/{id}/fork)

    func forkSession(sessionId: String, title: String? = nil) async throws -> HermesSession {
        var req = try request(method: "POST", path: "/api/sessions/\(sessionId)/fork")
        req.httpBody = try JSONEncoder().encode(ForkSessionRequest(title: title))
        let (data, response) = try await session.data(for: req)
        try checkHTTPStatus(response, data: data)
        let result = try decode(ForkSessionResponse.self, data: data, response: response)
        return result.session
    }

    // MARK: - Error Handling

    private func decode<T: Decodable>(_ type: T.Type, data: Data, response: URLResponse) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) }
        catch {
            let field: String
            switch error {
            case DecodingError.keyNotFound(let key, let context):
                field = (context.codingPath + [key]).map(\.stringValue).joined(separator: ".")
            case DecodingError.typeMismatch(_, let context), DecodingError.valueNotFound(_, let context),
                 DecodingError.dataCorrupted(let context):
                field = context.codingPath.map(\.stringValue).joined(separator: ".")
            default: field = "response"
            }
            throw APIError.invalidEndpoint("\(response.url?.path ?? "Hermes API") returned an incompatible response at \(field.isEmpty ? "the JSON root" : field). Refresh and check the gateway/Companion versions.")
        }
    }

    private func checkHTTPStatus(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard !(200...299).contains(http.statusCode) else { return }
        throw APIError.http(HTTPFailure(response: http, data: data, secret: config.apiKey))
    }

}

// MARK: - Timeout Helper

/// Run an async operation with a hard timeout. Throws URLError.timedOut on expiry.
func withTimeout<T>(seconds: Double, operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        defer { group.cancelAll() }
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
    case http(HTTPFailure)
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

    var isNotFound: Bool {
        if case .notFound = self { return true }
        if case .http(let failure) = self { return failure.status == 404 }
        return false
    }

    var errorDescription: String? {
        switch self {
        case .http(let failure): return failure.errorDescription
        case .invalidResponse: return "Hermes returned data that does not match the requested resource or pagination. Refresh the view; if it repeats, verify the gateway and Companion bridge versions."
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
