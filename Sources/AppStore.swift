import Foundation
import SwiftUI

/// Manages app state: connection config, active session, chat messages, streaming state.
@MainActor
final class AppStore: ObservableObject {
    // MARK: - Published State

    @Published var connectionConfig: ConnectionConfig?
    @Published var capabilities: CapabilitiesResponse?
    @Published var sessions: [HermesSession] = []
    @Published var activeSession: HermesSession?
    @Published var messages: [ChatDisplayMessage] = []
    @Published var isStreaming = false
    @Published var streamingText = ""
    @Published var toolEvents: [ToolEvent] = []
    @Published var skills: [Skill] = []
    @Published var toolsets: [ToolsetInfo] = []
    @Published var availableModels: [String] = []
    @Published var error: AppError?
    @Published var isLoading = false
    @Published var isLoadingConnection = false
    @Published var pendingApproval: PendingApproval?

    // MARK: - Multi-connection

    /// All saved server connections (most-recently-used first).
    @Published var savedConnections: [ConnectionConfig] = []

    // MARK: - Provider / Model / Thinking preferences

    /// Persisted provider slug (e.g. "nous", "openrouter", "ollama-local", "custom").
    /// Synced with macOS Hermes; locally scoped per-connection.
    @Published var preferredProvider: String = "" {
        didSet { savePreference(preferredProvider, key: Self.providerKey) }
    }

    /// Persisted model id. Locally scoped per-connection.
    @Published var preferredModel: String = "" {
        didSet { savePreference(preferredModel, key: Self.modelKey) }
    }

    /// Persisted reasoning effort: "", "low", "medium", "high".
    /// Note: the gateway chat endpoint doesn't honor a per-message reasoning_effort
    /// override today — this is a local preference only, surfaced in the UI and
    /// ready for the server to honor when support lands.
    @Published var preferredThinking: String = "" {
        didSet { savePreference(preferredThinking, key: Self.thinkingKey) }
    }

    private static let providerKey = "preferred_provider"
    private static let modelKey = "preferred_model"
    private static let thinkingKey = "preferred_thinking"

    var effectiveCurrentProvider: String {
        nonEmpty(preferredProvider)
            ?? nonEmpty(capabilities?.currentProvider)
            ?? providerForModel(effectiveCurrentModel)
            ?? ""
    }

    var effectiveCurrentModel: String {
        nonEmpty(preferredModel)
            ?? nonEmpty(capabilities?.currentModel)
            ?? nonEmpty(capabilities?.model)
            ?? ""
    }

    // MARK: - Private

    private(set) var apiClient: HermesAPIClient?
    private var streamTask: Task<Void, Never>?

    // MARK: - Init

    init() {
        // Load all saved connections for the multi-connection picker
        self.savedConnections = KeychainManager.shared.loadAll()

        var initialConfig = KeychainManager.shared.loadActive()
        #if DEBUG
        if initialConfig == nil {
            initialConfig = Self.debugConnectionFromEnvironment()
        }
        #endif

        if let initialConfig {
            let reachableConfig = Self.debugReachableConfig(initialConfig)
            connectionConfig = reachableConfig
            apiClient = HermesAPIClient(config: reachableConfig)
            loadPreferences(for: reachableConfig)
        } else {
            loadPreferences(for: nil)
        }
    }

    // MARK: - Connection

    var isConnected: Bool { connectionConfig != nil && !isLoadingConnection }

    /// Returns the current API client, creating one from saved config if needed
    private func client() throws -> HermesAPIClient {
        if let apiClient { return apiClient }
        guard let config = connectionConfig else {
            throw APIError.connectionRefused
        }
        let c = HermesAPIClient(config: config)
        apiClient = c
        return c
    }

    /// Called on app launch when a saved Keychain config exists.
    /// Performs a health check and, if successful, loads capabilities and
    /// sessions so the user goes straight to chat without re-entering credentials.
    func autoConnect() async {
        guard let config = connectionConfig else { return }
        isLoadingConnection = true
        let client = HermesAPIClient(config: config)
        do {
            let health = try await client.checkHealth()
            guard health.status == "ok" else {
                self.error = AppError(message: "Server returned status: \(health.status)")
                self.isLoadingConnection = false
                return
            }
            _ = try await client.getCapabilities()
            self.apiClient = client
            await refreshCapabilities()
            await refreshSessions()
            self.isLoadingConnection = false
        } catch let e as APIError {
            self.error = AppError(message: e.errorDescription ?? "Connection failed")
            self.connectionConfig = nil
            self.isLoadingConnection = false
        } catch {
            self.error = AppError(message: "Connection failed: \(error.localizedDescription)")
            self.connectionConfig = nil
            self.isLoadingConnection = false
        }
    }

    func connect(config: ConnectionConfig) async -> Bool {
        let client = HermesAPIClient(config: config)
        self.apiClient = client
        do {
            let health = try await client.checkHealth()
            guard health.status == "ok" else {
                self.error = AppError(message: "Server returned status: \(health.status)")
                return false
            }
            _ = try await client.getCapabilities()
            // Persist: add/update in the multi-connection list, then mark as active.
            do {
                let updated = try KeychainManager.shared.addOrUpdate(config)
                self.savedConnections = updated
                try KeychainManager.shared.setActive(baseURL: config.baseURL)
            } catch {
                self.error = AppError(message: "Failed to save connection: \(error.localizedDescription)")
            }
            self.connectionConfig = config
            loadPreferences(for: config)
            // Load capabilities
            await refreshCapabilities()
            await refreshSessions()
            return true
        } catch let e as APIError {
            self.error = AppError(message: e.errorDescription ?? "Connection failed")
            return false
        } catch {
            self.error = AppError(message: "Connection failed: \(error.localizedDescription)")
            return false
        }
    }

    func disconnect() {
        streamTask?.cancel()
        apiClient = nil
        connectionConfig = nil
        loadPreferences(for: nil)
        capabilities = nil
        sessions = []
        activeSession = nil
        messages = []
        skills = []
        toolsets = []
        KeychainManager.shared.deleteActive()
    }

    // MARK: - Multi-connection helpers

    /// Switch the active connection to one of the saved servers. Tears down
    /// the current session state and reconnects to the new server.
    func switchToConnection(_ config: ConnectionConfig) async {
        do {
            try KeychainManager.shared.setActive(baseURL: config.baseURL)
        } catch {
            self.error = AppError(message: "Failed to set active: \(error.localizedDescription)")
            return
        }
        // Tear down current state
        streamTask?.cancel()
        apiClient = nil
        capabilities = nil
        sessions = []
        activeSession = nil
        messages = []
        toolEvents = []
        streamingText = ""
        skills = []
        toolsets = []
        pendingApproval = nil

        self.connectionConfig = config
        loadPreferences(for: config)
        self.apiClient = HermesAPIClient(config: config)
        await autoConnect()
    }

    /// Remove a saved connection. If it was active, disconnects.
    func deleteConnection(_ config: ConnectionConfig) async {
        do {
            let updated = try KeychainManager.shared.remove(baseURL: config.baseURL)
            self.savedConnections = updated
        } catch {
            self.error = AppError(message: "Failed to delete: \(error.localizedDescription)")
            return
        }
        if connectionConfig?.baseURL == config.baseURL {
            disconnect()
        }
    }

    // MARK: - Capabilities

    func refreshCapabilities() async {
        let client: HermesAPIClient
        do {
            client = try self.client()
        } catch {
            self.error = AppError(message: "Not connected")
            return
        }
        do {
            self.capabilities = try await client.getCapabilities()
        } catch {
            // Non-fatal — capabilities are optional
        }
        // Load available models
        do {
            let models = try await client.getModels().map { $0.id }
            self.availableModels = modelsIncludingCurrent(models)
        } catch {
            self.availableModels = modelsIncludingCurrent([])
            // Non-fatal
        }
    }

    func selectPreferredModel(_ model: String) {
        preferredModel = model
        if let provider = providerForModel(model) {
            preferredProvider = provider
        }
    }

    private func providerForModel(_ model: String) -> String? {
        guard let slash = model.firstIndex(of: "/"), slash > model.startIndex else { return nil }
        return String(model[..<slash])
    }

    private func modelsIncludingCurrent(_ models: [String]) -> [String] {
        let current = effectiveCurrentModel
        guard !current.isEmpty, !models.contains(current) else { return models }
        return [current] + models
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    private func savePreference(_ value: String, key: String) {
        UserDefaults.standard.set(value, forKey: preferenceKey(key, for: connectionConfig))
    }

    private func loadPreferences(for config: ConnectionConfig?) {
        preferredProvider = savedPreference(Self.providerKey, for: config)
        preferredModel = savedPreference(Self.modelKey, for: config)
        preferredThinking = savedPreference(Self.thinkingKey, for: config)
    }

    private func savedPreference(_ key: String, for config: ConnectionConfig?) -> String {
        let defaults = UserDefaults.standard
        if let scopedValue = defaults.string(forKey: preferenceKey(key, for: config)) {
            return scopedValue
        }
        return defaults.string(forKey: key) ?? ""
    }

    private func preferenceKey(_ key: String, for config: ConnectionConfig?) -> String {
        guard let config else { return key }
        return "\(key).\(config.normalizedBaseURL)"
    }

    // MARK: - Sessions

    func refreshSessions() async {
        let client: HermesAPIClient
        do {
            client = try self.client()
        } catch {
            self.error = AppError(message: "Not connected")
            return
        }
        do {
            self.sessions = try await client.listSessions()
        } catch {
            self.error = AppError(message: "Failed to load sessions: \(error.localizedDescription)")
        }
    }

    func createSession(title: String? = nil) async {
        let client: HermesAPIClient
        do {
            client = try self.client()
        } catch {
            self.error = AppError(message: "Not connected")
            return
        }
        do {
            let session = try await client.createSession(title: title)
            self.sessions.insert(session, at: 0)
            await selectSession(session)
        } catch {
            self.error = AppError(message: "Failed to create session: \(error.localizedDescription)")
        }
    }

    func selectSession(_ session: HermesSession) async {
        let client: HermesAPIClient
        do {
            client = try self.client()
        } catch {
            self.error = AppError(message: "Not connected")
            return
        }
        self.activeSession = session
        self.messages = []
        self.toolEvents = []
        self.streamingText = ""
        do {
            let history = try await client.getMessages(sessionId: session.id)
            self.messages = history.map { ChatDisplayMessage(from: $0) }
        } catch {
            self.error = AppError(message: "Failed to load messages: \(error.localizedDescription)")
        }
    }

    /// Silently reload the active session's messages without tearing down UI
    /// state. Used by the foreground-reconnect path so replies that arrived
    /// from other platforms (Telegram, Discord, macOS) show up on return.
    /// Unlike `selectSession`, this does NOT blank `messages` first (no
    /// flicker) and does NOT touch `toolEvents` / `streamingText`, which
    /// belong to any in-flight local stream. Fails silently — this is a
    /// background refresh, not a user-initiated action.
    private func refreshActiveSessionMessages(_ session: HermesSession) async {
        guard let client = apiClient, !isStreaming else { return }
        do {
            let history = try await client.getMessages(sessionId: session.id)
            // Re-check: the user may have switched sessions or started a
            // stream while the request was in flight.
            guard activeSession?.id == session.id, !isStreaming else { return }
            self.messages = history.map { ChatDisplayMessage(from: $0) }
        } catch {
            // Silent — background refresh should not surface errors.
        }
    }

    func deleteSession(_ session: HermesSession) async {
        let client: HermesAPIClient
        do {
            client = try self.client()
        } catch {
            self.error = AppError(message: "Not connected")
            return
        }
        do {
            try await client.deleteSession(sessionId: session.id)
            self.sessions.removeAll { $0.id == session.id }
            if activeSession?.id == session.id {
                activeSession = nil
                messages = []
            }
        } catch {
            self.error = AppError(message: "Failed to delete session: \(error.localizedDescription)")
        }
    }

    func renameSession(_ session: HermesSession, newTitle: String) async {
        let client: HermesAPIClient
        do {
            client = try self.client()
        } catch {
            self.error = AppError(message: "Not connected")
            return
        }
        do {
            let updated = try await client.patchSession(sessionId: session.id, title: newTitle)
            if let idx = self.sessions.firstIndex(where: { $0.id == session.id }) {
                self.sessions[idx] = updated
            }
            if self.activeSession?.id == session.id {
                self.activeSession = updated
            }
        } catch {
            self.error = AppError(message: "Failed to rename session: \(error.localizedDescription)")
        }
    }

    func forkSession(_ session: HermesSession) async {
        let client: HermesAPIClient
        do {
            client = try self.client()
        } catch {
            self.error = AppError(message: "Not connected")
            return
        }
        do {
            let forked = try await client.forkSession(sessionId: session.id, title: forkTitle(for: session))
            self.sessions.insert(forked, at: 0)
            await selectSession(forked)
        } catch {
            self.error = AppError(message: "Failed to fork session: \(error.localizedDescription)")
        }
    }

    private func forkTitle(for session: HermesSession) -> String {
        let base = (session.title?.isEmpty == false ? session.title! : "Untitled").trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(base) Fork"
    }

    // MARK: - Skills

    func refreshSkills() async {
        guard let client = try? self.client() else { return }
        do {
            self.skills = try await client.listSkills()
        } catch {
            // Non-fatal
        }
    }

    func refreshToolsets() async {
        guard let client = try? self.client() else { return }
        do {
            self.toolsets = try await client.getToolsets()
        } catch {
            // Non-fatal
        }
    }

    // MARK: - Chat (streaming)

    @discardableResult
    func sendMessage(_ text: String, images: [Data] = [], attachments: [AttachmentData] = []) async -> ChatDisplayMessage? {
        let client: HermesAPIClient
        do {
            client = try self.client()
        } catch {
            self.error = AppError(message: "Not connected")
            return nil
        }

        // Auto-create a session if none is active — the user should be able
        // to just type and send without manually creating a session first.
        let session: HermesSession
        if let active = activeSession {
            session = active
        } else {
            do {
                let newSession = try await client.createSession(title: nil)
                self.sessions.insert(newSession, at: 0)
                self.activeSession = newSession
                session = newSession
            } catch {
                self.error = AppError(message: "Failed to create session: \(error.localizedDescription)")
                return nil
            }
        }

        // Capture current assistant message count and latest timestamp before
        // the send. The empty-stream guard below uses this to tell a successful
        // turn (server has a new assistant row) from a connection that closed
        // early (no new row). Local ChatDisplayMessage.id values are local
        // UUIDs that don't match the server's integer id, so we can't diff by
        // id — count + timestamp is a robust proxy.
        let existingAssistantCount = messages.filter(\.isAssistant).count
        let latestKnownTimestamp = messages.map(\.timestamp).max() ?? .distantPast

        // Build display message (user's text + any images)
        let userMsg = ChatDisplayMessage(
            id: UUID().uuidString,
            role: "user",
            content: text,
            images: images,
            timestamp: Date()
        )
        messages.append(userMsg)

        // Build the message payload for the API
        let messagePayload = text

        // Prepare streaming state
        isStreaming = true
        streamingText = ""
        toolEvents = []
        pendingApproval = nil

        // Cancel any existing stream task before starting a new one
        streamTask?.cancel()

        var assistantMessage: ChatDisplayMessage?
        // Tracks whether the stream delivered a terminal completion event
        // (assistant.completed or run.completed). The empty-stream guard below
        // uses this to tell a legitimate empty reply from a connection that
        // closed early. The JSON (attachment) path sets it on success.
        var receivedCompletion = false
        let task = Task { [weak self] in
            guard let self = self else { return }
            do {
                if images.isEmpty && attachments.isEmpty {
                    let stream = try await client.streamChat(sessionId: session.id, message: messagePayload)
                    for try await event in stream {
                        if Task.isCancelled { return }
                        if event.event == "assistant.completed" || event.event == "run.completed" {
                            receivedCompletion = true
                        }
                        if let completedMessage = await self.handleSSEEvent(event) {
                            assistantMessage = completedMessage
                        }
                    }

                    if !streamingText.isEmpty {
                        let message = ChatDisplayMessage(
                            id: UUID().uuidString,
                            role: "assistant",
                            content: streamingText,
                            timestamp: Date()
                        )
                        messages.append(message)
                        assistantMessage = message
                        streamingText = ""
                    }
                } else {
                    // File and image attachments still use the JSON endpoint because
                    // the current stream endpoint only accepts plain text messages.
                    let response = try await client.sendChat(
                        sessionId: session.id,
                        message: messagePayload,
                        images: images,
                        attachments: attachments
                    )
                    if Task.isCancelled { return }

                    receivedCompletion = true
                    let content = response.message.content
                    if !content.isEmpty {
                        let message = ChatDisplayMessage(
                            id: UUID().uuidString,
                            role: response.message.role,
                            content: content,
                            timestamp: Date()
                        )
                        messages.append(message)
                        if message.isAssistant {
                            assistantMessage = message
                        }
                    }
                }
                let history = try await client.getMessages(sessionId: session.id)
                self.messages = history.map { ChatDisplayMessage(from: $0) }
                await refreshSessions()

                // Empty-stream guard: if no terminal completion event arrived
                // (assistant.completed / run.completed) AND the reloaded server
                // history shows no new assistant message for this turn, the
                // connection almost certainly closed early (transient gateway
                // error or network drop). Surface an error. Placed AFTER the
                // getMessages reload so it never fires on a legitimate empty
                // reply or a tool-heavy turn whose content landed in history.
                // User-initiated cancellation returns earlier via Task.isCancelled,
                // so it never reaches here.
                if !receivedCompletion {
                    let newAssistantCount = self.messages.filter(\.isAssistant).count
                    let newLatestTimestamp = self.messages.map(\.timestamp).max() ?? .distantPast
                    let hasNewAssistant = newAssistantCount > existingAssistantCount ||
                        newLatestTimestamp > latestKnownTimestamp
                    if !hasNewAssistant {
                        self.error = AppError(message: "No response received — the server may have closed the connection early. Please try again.")
                    }
                }
            } catch let e as APIError {
                self.error = AppError(message: e.errorDescription ?? "Message failed")
            } catch {
                self.error = AppError(message: "Message failed: \(error.localizedDescription)")
            }
            self.streamingText = ""
            self.isStreaming = false
        }
        streamTask = task
        await task.value
        return assistantMessage
    }

    func stopStreaming() {
        streamTask?.cancel()
        isStreaming = false
        if !streamingText.isEmpty {
            // Save partial response
            messages.append(ChatDisplayMessage(
                id: UUID().uuidString,
                role: "assistant",
                content: streamingText + " [interrupted]",
                timestamp: Date()
            ))
            streamingText = ""
        }
    }

    // MARK: - SSE Event Handler

    private func handleSSEEvent(_ event: SSEEventPayload) async -> ChatDisplayMessage? {
        switch event.event {
        case "run.started", "message.started":
            // Streaming begins
            break

        case "assistant.delta":
            if let delta = event.delta {
                streamingText += delta
            }

        case "tool.progress":
            // Server sends "delta" for reasoning.available events, "preview" for others
            let detail = event.preview ?? event.delta ?? ""
            if !detail.isEmpty {
                toolEvents.append(ToolEvent(
                    id: UUID().uuidString,
                    type: .progress,
                    toolName: event.toolName ?? "thinking",
                    detail: detail
                ))
            }

        case "tool.started":
            toolEvents.append(ToolEvent(
                id: UUID().uuidString,
                type: .started,
                toolName: event.toolName ?? "unknown",
                detail: event.preview ?? ""
            ))

        case "tool.completed":
            toolEvents.append(ToolEvent(
                id: UUID().uuidString,
                type: .completed,
                toolName: event.toolName ?? "unknown",
                detail: event.preview ?? ""
            ))

        case "tool.failed":
            toolEvents.append(ToolEvent(
                id: UUID().uuidString,
                type: .failed,
                toolName: event.toolName ?? "unknown",
                detail: event.preview ?? "Tool failed"
            ))

        case "assistant.completed":
            // Finalize the streamed text into a message
            let finalContent = event.content ?? streamingText
            if !finalContent.isEmpty {
                let message = ChatDisplayMessage(
                    id: event.message_id ?? UUID().uuidString,
                    role: "assistant",
                    content: finalContent,
                    timestamp: Date()
                )
                messages.append(message)
                streamingText = ""
                return message
            }
            streamingText = ""

        case "run.completed":
            // Stream is done
            streamingText = ""
            // Refresh sessions list to update message counts
            await refreshSessions()

        case "error":
            if let msg = event.message {
                self.error = AppError(message: msg)
            }

        case "done":
            // End of stream
            break

        default:
            break
        }
        return nil
    }

    // MARK: - Approval

    func resolveApproval(choice: String) async {
        guard let approval = pendingApproval else { return }
        let client: HermesAPIClient
        do {
            client = try self.client()
        } catch {
            self.error = AppError(message: "Not connected")
            return
        }
        do {
            try await client.resolveApproval(runId: approval.runId, choice: choice)
            self.pendingApproval = nil
        } catch {
            self.error = AppError(message: "Failed to resolve approval: \(error.localizedDescription)")
        }
    }

    // MARK: - Error Clear

    func clearError() {
        self.error = nil
    }

    #if DEBUG
    private static func debugConnectionFromEnvironment() -> ConnectionConfig? {
        let env = ProcessInfo.processInfo.environment
        let defaults = UserDefaults.standard
        let apiKey = env["API_SERVER_KEY"].flatMap { $0.isEmpty ? nil : $0 }
            ?? defaults.string(forKey: "debug_apiKey").flatMap { $0.isEmpty ? nil : $0 }
        guard let apiKey else { return nil }

        let baseURL: String
        if let explicitURL = env["HERMES_BASE_URL"], !explicitURL.isEmpty {
            baseURL = explicitURL
        } else if let debugBaseURL = defaults.string(forKey: "debug_baseURL"), !debugBaseURL.isEmpty {
            baseURL = debugBaseURL
        } else {
            let host = env["API_SERVER_HOST"].flatMap { ($0.isEmpty || $0 == "0.0.0.0") ? nil : $0 } ?? "100.x.x.x"
            let port = env["API_SERVER_PORT"].flatMap { $0.isEmpty ? nil : $0 } ?? "\(AppConfig.defaultPort)"
            let scheme = env["API_SERVER_SCHEME"].flatMap { $0.isEmpty ? nil : $0 } ?? "http"
            baseURL = "\(scheme)://\(host):\(port)"
        }

        let label = env["HERMES_LABEL"].flatMap { $0.isEmpty ? nil : $0 }
            ?? defaults.string(forKey: "debug_label").flatMap { $0.isEmpty ? nil : $0 }
            ?? "Hermes Debug"
        return debugReachableConfig(ConnectionConfig(baseURL: baseURL, apiKey: apiKey, label: label))
    }

    private static func debugReachableConfig(_ config: ConnectionConfig) -> ConnectionConfig {
        guard let url = URL(string: config.baseURL),
              url.host == "0.0.0.0",
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return config
        }
        let env = ProcessInfo.processInfo.environment
        components.host = env["API_SERVER_HOST"].flatMap { ($0.isEmpty || $0 == "0.0.0.0") ? nil : $0 } ?? "100.x.x.x"
        return ConnectionConfig(baseURL: components.url?.absoluteString ?? config.baseURL, apiKey: config.apiKey, label: config.label)
    }
    #else
    private static func debugReachableConfig(_ config: ConnectionConfig) -> ConnectionConfig {
        config
    }
    #endif

    // MARK: - Background/Foreground Persistence

    /// Called when the app returns to the foreground. Checks if the Hermes
    /// server is still reachable and silently reconnects if the connection
    /// dropped while in the background. Preserves the active session and
    /// messages so the user doesn't lose context.
    private var isReconnecting = false

    func reconnectIfNeeded() async {
        guard connectionConfig != nil, !isReconnecting else { return }
        isReconnecting = true
        defer { isReconnecting = false }

        // Quick health check — if it passes, we're still connected.
        do {
            let client = try self.client()
            let health = try await client.checkHealth()
            guard health.status == "ok" else {
                // Server is up but unhealthy. Mark disconnected.
                self.error = AppError(message: "Server unhealthy: \(health.status)")
                return
            }
            // Connection is alive. Refresh sessions silently in case
            // anything changed while we were in the background.
            await refreshCapabilities()
            await refreshSessions()
            // Also reload the active session's messages so replies that
            // arrived from other platforms (Telegram, Discord, macOS) while
            // we were backgrounded show up on return. Skip while a local
            // stream is in flight so we don't clobber in-progress output.
            if let active = activeSession, !isStreaming {
                await refreshActiveSessionMessages(active)
            }
        } catch {
            // Connection dropped while in background. Reconnect using
            // the saved config so the user doesn't have to re-enter it.
            guard let config = connectionConfig else { return }
            do {
                let newClient = HermesAPIClient(config: config)
                let health = try await newClient.checkHealth()
                guard health.status == "ok" else {
                    self.error = AppError(message: "Server returned: \(health.status)")
                    return
                }
                self.apiClient = newClient
                await refreshCapabilities()
                await refreshSessions()
                // Restore the active session's messages if we had one.
                if let active = activeSession {
                    await selectSession(active)
                }
            } catch {
                // Server is unreachable. Don't clear connectionConfig -- just show
                // an error and keep the saved config so we can retry automatically.
                // Clearing it sends the user back to the setup screen, which is
                // frustrating during quick app switches where Tailscale needs a
                // moment to reconnect.
                self.error = AppError(message: "Lost connection to Hermes. Will retry.")
                // Schedule a retry in 3 seconds
                Task {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    await MainActor.run {
                        if self.connectionConfig != nil {
                            Task { await self.reconnectIfNeeded() }
                        }
                    }
                }
            }
        }
    }

    private var backgroundTaskId: UIBackgroundTaskIdentifier?

    /// Begins a short background task to keep the network connection alive
    /// during quick app switches (e.g., checking a message in another app).
    /// iOS will eventually kill the task, but this buys ~30 seconds.
    func beginBackgroundKeepAlive() {
        endBackgroundTask()
        backgroundTaskId = UIApplication.shared.beginBackgroundTask(expirationHandler: { [weak self] in
            self?.endBackgroundTask()
        })
    }

    private func endBackgroundTask() {
        if let taskId = backgroundTaskId {
            UIApplication.shared.endBackgroundTask(taskId)
            backgroundTaskId = nil
        }
    }
}

// MARK: - Display Models

struct ChatDisplayMessage: Identifiable, Equatable {
    let id: String
    let role: String
    let content: String
    let images: [Data]
    let timestamp: Date

    var isUser: Bool { role == "user" }
    var isAssistant: Bool { role == "assistant" }

    init(id: String, role: String, content: String, images: [Data] = [], timestamp: Date) {
        self.id = id
        self.role = role
        self.content = content
        self.images = images
        self.timestamp = timestamp
    }

    init(from msg: SessionMessage) {
        self.id = msg.idString
        self.role = msg.role
        self.content = msg.content
        self.images = []
        self.timestamp = msg.date ?? Date()
    }
}

struct ToolEvent: Identifiable, Equatable {
    let id: String
    let type: ToolEventType
    let toolName: String
    let detail: String
}

enum ToolEventType: String, Equatable {
    case progress
    case started
    case completed
    case failed
}

struct PendingApproval: Identifiable, Sendable {
    let id: String
    let runId: String
    let command: String
    let tool: String?
}

struct AppError: Identifiable {
    let id = UUID()
    let message: String
}
