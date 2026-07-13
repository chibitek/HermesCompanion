import Foundation
import SwiftUI
import AVFoundation
import UserNotifications

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
    /// True while a voice conversation is active — prevents stopSilentAudio
    /// from deactivating the shared AVAudioSession mid-conversation.
    @Published var isVoiceConversationActive = false
    @Published var skills: [Skill] = []
    @Published var toolsets: [ToolsetInfo] = []
    @Published var availableModels: [String] = []
    @Published private(set) var queuedMessages: [String] = []
    @Published var error: AppError?
    @Published var isLoading = false
    @Published var isLoadingConnection = false
    @Published var serverHealthStatus: [String: ServerHealthState] = [:]

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

    /// Recently used models (favorites), persisted per-connection.
    /// Shown in the compact model picker in the chat bar.
    @Published var favoriteModels: [String] = [] {
        didSet { savePreference(favoriteModels.joined(separator: "\n"), key: Self.favModelsKey) }
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
    private static let favModelsKey = "favorite_models"

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
    private let activeSessionPersistence = ActiveSessionPersistence()

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

    // MARK: - Server Health Check

    /// Ping all saved servers concurrently and update serverHealthStatus.
    /// Used by the splash/server-picker screen to show which servers are
    /// reachable before the user taps one.
    func checkAllServerHealth() async {
        let configs = savedConnections
        guard !configs.isEmpty else { return }

        // Mark all as checking
        await MainActor.run {
            for config in configs {
                serverHealthStatus[config.baseURL] = ServerHealthState(
                    id: config.baseURL,
                    label: config.label,
                    baseURL: config.baseURL,
                    status: .checking
                )
            }
        }

        // Ping each server concurrently
        await withTaskGroup(of: (String, ServerHealthState.HealthStatus, Int?, String?).self) { group in
            for config in configs {
                group.addTask {
                    let client = HermesAPIClient(config: config)
                    let start = Date()
                    do {
                        let health = try await client.checkHealth()
                        let latency = Int(Date().timeIntervalSince(start) * 1000)
                        return (config.baseURL, health.status == "ok" ? .online : .offline, latency, health.version)
                    } catch {
                        return (config.baseURL, .offline, nil, nil)
                    }
                }
            }
            for await (baseURL, status, latency, version) in group {
                await MainActor.run {
                    var state = serverHealthStatus[baseURL] ?? ServerHealthState(
                        id: baseURL, label: baseURL, baseURL: baseURL)
                    state.status = status
                    state.latencyMs = latency
                    state.version = version
                    serverHealthStatus[baseURL] = state
                }
            }
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
            // Health check with a 10-second timeout so we don't hang forever
            // when Tailscale is down or the server is unreachable.
            let health = try await withThrowingTaskGroup(of: HealthResponse.self) { group in
                group.addTask { try await client.checkHealth() }
                group.addTask {
                    try await Task.sleep(nanoseconds: 10_000_000_000)
                    throw URLError(.timedOut)
                }
                let result = try await group.next() ?? HealthResponse(status: "timeout", platform: nil, version: nil)
                group.cancelAll()
                return result
            }
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
            self.error = AppError(message: e.errorDescription ?? "Connection failed. Select a server to retry.")
            self.isLoadingConnection = false
        } catch {
            self.error = AppError(message: "Connection failed. Select a server to retry.")
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
            // Sync preferredModel to the gateway's actual current model
            // when no valid user preference is saved.
            let gwModel = self.capabilities?.currentModel ?? self.capabilities?.model ?? ""
            if !gwModel.isEmpty,
               preferredModel.isEmpty || !availableModels.contains(preferredModel) {
                preferredModel = gwModel
            }
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

    func selectPreferredModel(_ model: String, provider: String? = nil) {
        preferredModel = model
        // Resolve provider ONLY from explicit arg or model ID prefix (e.g. "openai/gpt-4").
        // Do NOT fall back to capabilities.currentProvider — that's the gateway's
        // current state, not necessarily where this model lives. Sending a stale
        // provider (e.g. "nous") to switchGatewayModel breaks local Ollama models.
        let resolvedProvider = nonEmpty(provider)
            ?? providerForModel(model)
            ?? ""
        if !resolvedProvider.isEmpty {
            preferredProvider = resolvedProvider
        }
        // Switch the gateway's active model. Only send provider when we know it
        // from the model ID or explicit arg; otherwise let the gateway keep its
        // current provider config.
        let selectedProvider = resolvedProvider.isEmpty ? nil : resolvedProvider
        Task {
            await apiClient?.switchGatewayModel(model, provider: selectedProvider)
        }
    }

    /// Single-favorite toggle: starring a model replaces the previous favorite.
    /// Tapping the star on an already-favorited model unstars it.
    /// Called from Settings. Returns true if now favorited, false if unfavorited.
    @discardableResult
    func toggleFavorite(_ model: String) -> Bool {
        guard !model.isEmpty else { return false }
        if favoriteModels.contains(model) {
            // Already favorited — unstar it
            favoriteModels.removeAll { $0 == model }
            return false
        }
        // Replace any existing favorites with this one
        favoriteModels = [model]
        return true
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
        let savedFavs = savedPreference(Self.favModelsKey, for: config)
        favoriteModels = savedFavs.split(separator: "\n").map(String.init)
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
            await restoreActiveSessionIfAvailable()
        } catch {
            self.error = AppError(message: "Failed to load sessions: \(error.localizedDescription)")
        }
    }

    /// Restores the last chat used on this server after a cold launch. If that
    /// chat no longer exists, clear the stale pointer and let the UI create a
    /// fresh isolated session.
    private func restoreActiveSessionIfAvailable() async {
        guard activeSession == nil,
              let baseURL = connectionConfig?.normalizedBaseURL,
              let savedID = activeSessionPersistence.load(for: baseURL) else { return }

        guard let savedSession = sessions.first(where: { $0.id == savedID }) else {
            activeSessionPersistence.clear(for: baseURL)
            return
        }
        await selectSession(savedSession)
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
        if let baseURL = connectionConfig?.normalizedBaseURL {
            activeSessionPersistence.save(sessionID: session.id, for: baseURL)
        }
        self.messages = []
        self.toolEvents = []
        self.streamingText = ""
        do {
            let history = try await client.getMessages(sessionId: session.id)
            self.messages = history
                .filter { $0.isUser || $0.isAssistant }
                .map { ChatDisplayMessage(from: $0) }
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
            self.messages = history
                .filter { $0.isUser || $0.isAssistant }
                .map { ChatDisplayMessage(from: $0) }
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
                if let baseURL = connectionConfig?.normalizedBaseURL {
                    activeSessionPersistence.clear(for: baseURL)
                }
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

    func queueMessage(_ text: String, displayText: String? = nil) {
        let payload = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !payload.isEmpty else { return }
        queuedMessages.append(payload)
    }

    @discardableResult
    func sendMessage(_ text: String, displayText: String? = nil, images: [Data] = [], attachments: [AttachmentData] = [], skipPostReload: Bool = false) async -> ChatDisplayMessage? {
        let client: HermesAPIClient
        do {
            client = try self.client()
        } catch {
            self.error = AppError(message: "Not connected")
            return nil
        }

        let session = await ensureSession(client: client)
        guard let session else { return nil }

        let existingAssistantCount = messages.filter(\.isAssistant).count

        let userMsg = ChatDisplayMessage(
            id: UUID().uuidString,
            role: "user",
            content: displayText ?? text,
            images: images,
            timestamp: Date()
        )
        messages.append(userMsg)

        isStreaming = true
        streamingText = ""
        toolEvents = []
        beginBackgroundKeepAlive()

        let watchdog = StreamWatchdogManager()
        watchdog.arm(after: 90) { [weak self] in
            guard let self, self.isStreaming else { return }
            self.streamTask?.cancel()
            self.isStreaming = false
            self.streamingText = ""
            self.endBackgroundTask()
            self.error = AppError(message: "The response stream stopped sending updates. Please try again.")
        }

        streamTask?.cancel()

        var assistantMessage: ChatDisplayMessage?
        var receivedCompletion = false

        let task = Task { [weak self] in
            guard let self = self else { return }
            do {
                if images.isEmpty && attachments.isEmpty {
                    let (streamedMsg, streamedCompletion) = try await self.streamMessage(
                        client: client, session: session, text: text, watchdog: watchdog
                    )
                    assistantMessage = streamedMsg
                    if streamedCompletion { receivedCompletion = true }
                    if !self.streamingText.isEmpty {
                        receivedCompletion = true
                        let leftover = Self.stripRawArtifacts(self.streamingText)
                        if !leftover.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            let message = ChatDisplayMessage(
                                id: UUID().uuidString, role: "assistant",
                                content: leftover, timestamp: Date()
                            )
                            self.messages.append(message)
                            assistantMessage = message
                        }
                        self.streamingText = ""
                    }
                } else {
                    assistantMessage = try await self.sendWithAttachments(
                        client: client, session: session, text: text,
                        images: images, attachments: attachments
                    )
                    receivedCompletion = true
                }

                (assistantMessage, receivedCompletion) = try await self.postStreamReload(
                    client: client, session: session, skipPostReload: skipPostReload,
                    assistantMessage: assistantMessage, receivedCompletion: receivedCompletion
                )

                if assistantMessage == nil {
                    assistantMessage = self.messages.last(where: \.isAssistant)
                    FileLogger.shared.log("AppStore: fell back to reloaded assistant message: \(String(describing: assistantMessage?.content.prefix(60)))")
                }

                self.emptyStreamGuard(
                    receivedCompletion: receivedCompletion,
                    existingAssistantCount: existingAssistantCount
                )
            } catch let e as APIError {
                self.error = AppError(message: e.errorDescription ?? "Message failed")
            } catch {
                self.error = AppError(message: "Message failed: \(error.localizedDescription)")
            }
            self.streamingText = ""
            self.isStreaming = false
            self.endBackgroundTask()
            watchdog.cancel()

            if !self.queuedMessages.isEmpty {
                let next = self.queuedMessages.removeFirst()
                Task { await self.sendMessage(next) }
            }

            if let assistantMessage,
               UIApplication.shared.applicationState != .active {
                sendBackgroundNotification(text: assistantMessage.content)
            }
        }
        streamTask = task
        await task.value
        return assistantMessage
    }

    // MARK: - sendMessage Helpers

    private func ensureSession(client: HermesAPIClient) async -> HermesSession? {
        if let active = activeSession { return active }
        do {
            let newSession = try await client.createSession(title: nil)
            self.sessions.insert(newSession, at: 0)
            self.activeSession = newSession
            return newSession
        } catch {
            self.error = AppError(message: "Failed to create session: \(error.localizedDescription)")
            return nil
        }
    }

    private func streamMessage(
        client: HermesAPIClient, session: HermesSession,
        text: String, watchdog: StreamWatchdogManager
    ) async throws -> (ChatDisplayMessage?, Bool) {
        var assistantMessage: ChatDisplayMessage?
        var receivedCompletion = false
        let stream = try await client.streamChat(
            sessionId: session.id, message: text, model: effectiveCurrentModel
        )
        for try await event in stream {
            if Task.isCancelled { return (nil, false) }
            watchdog.recordActivity()
            if event.event == "assistant.completed" || event.event == "run.completed" {
                receivedCompletion = true
            }
            if let completedMessage = await self.handleSSEEvent(event) {
                assistantMessage = completedMessage
            }
        }
        return (assistantMessage, receivedCompletion)
    }

    private func sendWithAttachments(
        client: HermesAPIClient, session: HermesSession, text: String,
        images: [Data], attachments: [AttachmentData]
    ) async throws -> ChatDisplayMessage? {
        let response = try await client.sendChat(
            sessionId: session.id, message: text,
            model: effectiveCurrentModel, images: images, attachments: attachments
        )
        if Task.isCancelled { return nil }
        let content = response.message.content
        guard !content.isEmpty else { return nil }
        let message = ChatDisplayMessage(
            id: UUID().uuidString, role: response.message.role,
            content: content, timestamp: Date()
        )
        messages.append(message)
        return message.isAssistant ? message : nil
    }

    private func postStreamReload(
        client: HermesAPIClient, session: HermesSession, skipPostReload: Bool,
        assistantMessage: ChatDisplayMessage?, receivedCompletion: Bool
    ) async throws -> (ChatDisplayMessage?, Bool) {
        let msg = assistantMessage
        let completion = receivedCompletion

        if !skipPostReload && msg == nil {
            let history = try await client.getMessages(sessionId: session.id)
            self.messages = history
                .filter { $0.isUser || $0.isAssistant }
                .map { ChatDisplayMessage(from: $0) }
            await refreshSessions()
        } else if !skipPostReload {
            await refreshSessions()
        }

        // Voice mode fallback: reload from server if no message and no completion
        if skipPostReload && msg == nil && !completion {
            FileLogger.shared.log("AppStore: voice mode fallback — reloading from server")
            let history = try await client.getMessages(sessionId: session.id)
            self.messages = history
                .filter { $0.isUser || $0.isAssistant }
                .map { ChatDisplayMessage(from: $0) }
            await refreshSessions()
        }

        return (msg, completion)
    }

    private func emptyStreamGuard(receivedCompletion: Bool, existingAssistantCount: Int) {
        guard !receivedCompletion else { return }
        let newAssistantCount = self.messages.filter(\.isAssistant).count
        if newAssistantCount <= existingAssistantCount {
            self.error = AppError(message: "No response received — the server may have closed the connection early. Please try again.")
        }
    }

    func stopStreaming() {
        streamTask?.cancel()
        isStreaming = false
    }

    // MARK: - SSE Event Handler

    private func handleSSEEvent(_ event: SSEEventPayload) async -> ChatDisplayMessage? {
        switch event.event {
        case "run.started", "message.started":
            break

        case "assistant.delta":
            // The gateway reuses assistant.delta for thinking/reasoning text
            // by setting tool_name to "_thinking" or other tool names. That
            // internal reasoning must NOT be appended to streamingText or
            // it leaks raw JSON and agent thoughts into the chat UI.
            if let tname = event.toolName, !tname.isEmpty {
                break
            }
            if let delta = event.delta {
                let cleaned = Self.stripRawArtifacts(delta)
                if !cleaned.isEmpty {
                    streamingText += cleaned
                }
            }
        case "tool.progress":
            // Suppress _thinking reasoning deltas — internal monologue, not user-facing
            let progToolName = event.toolName ?? ""
            if progToolName == "_thinking" || progToolName == "thinking" { break }
            let progDetail = event.preview ?? event.delta ?? ""
            if !progDetail.isEmpty {
                toolEvents.append(ToolEvent(
                    id: UUID().uuidString,
                    type: .progress,
                    toolName: progToolName,
                    detail: progDetail
                ))
            }

        case "tool.started":
            let startToolName = event.toolName ?? "unknown"
            if startToolName == "_thinking" || startToolName == "thinking" { break }
            toolEvents.append(ToolEvent(
                id: UUID().uuidString,
                type: .started,
                toolName: startToolName,
                detail: event.preview ?? ""
            ))

        case "tool.completed":
            let compToolName = event.toolName ?? "unknown"
            if compToolName == "_thinking" || compToolName == "thinking" { break }
            toolEvents.append(ToolEvent(
                id: UUID().uuidString,
                type: .completed,
                toolName: compToolName,
                detail: event.preview ?? ""
            ))

        case "tool.failed":
            let failToolName = event.toolName ?? "unknown"
            if failToolName == "_thinking" || failToolName == "thinking" { break }
            toolEvents.append(ToolEvent(
                id: UUID().uuidString,
                type: .failed,
                toolName: failToolName,
                detail: event.preview ?? "Tool failed"
            ))

        case "assistant.completed":
            let finalContent = Self.stripRawArtifacts(event.content ?? streamingText)

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
            streamingText = ""
            await refreshSessions()

        case "error":
            if let msg = event.message {
                let trimmed = msg.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
                    if let data = trimmed.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let errorMsg = json["message"] as? String ?? json["error"] as? String {
                        self.error = AppError(message: errorMsg)
                    }
                } else if !trimmed.isEmpty {
                    self.error = AppError(message: msg)
                }
            }

        case "done":
            break

        default:
            FileLogger.shared.log("AppStore: unhandled SSE event: \(event.event)")
        }
        return nil
    }

    // MARK: - Raw Artifact Stripping

    /// Strip raw JSON, thinking tags, and tool-call artifacts from text that
    /// should only contain human-readable assistant text.
    static func stripRawArtifacts(_ text: String) -> String {
        var cleaned = text

        // Strip reasoning/thinking blocks:  to  (inclusive)
        while let startTag = cleaned.range(of: ""),
              let endTag = cleaned.range(of: "", range: startTag.upperBound..<cleaned.endIndex) {
            cleaned.removeSubrange(startTag.lowerBound..<endTag.upperBound)
        }
        // Strip any leftover bare  or  tags (unclosed or mismatched)
        cleaned = cleaned.replacingOccurrences(of: "", with: "")
        cleaned = cleaned.replacingOccurrences(of: "", with: "")

        // Strip standalone JSON objects/arrays that aren't human text
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            if let data = trimmed.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // Try to extract human-readable text from common JSON shapes
                if let text = json["content"] as? String ?? json["text"] as? String ?? json["message"] as? String {
                    cleaned = text
                } else {
                    // It's JSON but has no readable text field -- discard it
                    cleaned = ""
                }
            }
        }

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Approval

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
    private var reconnectRetryCount = 0
    private let maxReconnectRetries = 10

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
            // Connection is alive. Reset retry count and refresh sessions.
            reconnectRetryCount = 0
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
                // Server is unreachable. Don't clear connectionConfig — just show
                // an error and keep the saved config so we can retry automatically.
                self.error = AppError(message: "Lost connection to Hermes. Will retry.")
                // Exponential backoff: 3s, 6s, 12s, 24s, 30s, 30s, ... max 10 retries
                reconnectRetryCount += 1
                guard reconnectRetryCount <= maxReconnectRetries else {
                    self.error = AppError(message: "Could not reconnect to Hermes after \(maxReconnectRetries) attempts. Please check your connection.")
                    reconnectRetryCount = 0
                    return
                }
                let delay = min(3.0 * pow(2.0, Double(reconnectRetryCount - 1)), 30.0)
                Task {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    await MainActor.run {
                        // Verify the config hasn't changed since we started retrying.
                        // If the user switched servers, don't let a stale retry hijack the new connection.
                        guard let currentConfig = self.connectionConfig, currentConfig == config else { return }
                        Task { await self.reconnectIfNeeded() }
                    }
                }
            }
        }
    }

    private var backgroundTaskId: UIBackgroundTaskIdentifier?
    private var silentPlayer: AVAudioPlayer?
    private var isBackgroundAudioActive = false

    /// Begins a short background task to keep the network connection alive
    /// during quick app switches (e.g., checking a message in another app).
    /// iOS will eventually kill the task, but this buys ~30 seconds.
    /// Additionally, activates a silent audio loop to leverage the `audio`
    /// background mode, which keeps the app alive indefinitely as long as
    /// the audio session is active.
    func beginBackgroundKeepAlive() {
        endBackgroundTask()
        backgroundTaskId = UIApplication.shared.beginBackgroundTask(expirationHandler: { [weak self] in
            self?.endBackgroundTask()
        })

        // Start a silent audio loop to keep the audio session active in the
        // background. This leverages the `audio` UIBackgroundModes entry to
        // prevent iOS from suspending the app during SSE streaming or TTS
        // playback when the user switches to another app.
        startSilentAudioForBackground()
    }
    
    /// Starts a looping silent audio player to keep the audio session active
    /// in the background. This leverages the `audio` UIBackgroundModes entry
    /// to prevent iOS from suspending the app during SSE streaming.
    private func startSilentAudioForBackground() {
        guard !isBackgroundAudioActive else { return }
        
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            
            // Generate a 0.5-second silent WAV file in memory
            let sampleRate = 44100.0
            let numSamples = Int(sampleRate * 0.5)
            var wavData = Data()
            // WAV header
            let header: [UInt8] = [
                0x52, 0x49, 0x46, 0x46, // "RIFF"
                0x24, 0x00, 0x00, 0x00, // chunk size (36 + data size)
                0x57, 0x41, 0x56, 0x45, // "WAVE"
                0x66, 0x6D, 0x74, 0x20, // "fmt "
                0x10, 0x00, 0x00, 0x00, // subchunk size (16)
                0x01, 0x00,             // audio format (1 = PCM)
                0x01, 0x00,             // num channels (1)
                0x44, 0xAC, 0x00, 0x00, // sample rate (44100)
                0x44, 0xAC, 0x00, 0x00, // byte rate (44100)
                0x01, 0x00,             // block align (1)
                0x08, 0x00,             // bits per sample (8)
                0x64, 0x61, 0x74, 0x61, // "data"
            ]
            wavData.append(contentsOf: header)
            // data size
            let dataSize = numSamples
            let dataSizeBytes = withUnsafeBytes(of: UInt32(dataSize).littleEndian) { Data($0) }
            wavData.append(dataSizeBytes)
            // Silent audio data (all zeros = silence for 8-bit PCM)
            wavData.append(contentsOf: [UInt8](repeating: 128, count: dataSize)) // 128 = silence for unsigned 8-bit
            
            silentPlayer = try AVAudioPlayer(data: wavData)
            silentPlayer?.numberOfLoops = -1 // infinite loop
            silentPlayer?.volume = 0
            silentPlayer?.play()
            isBackgroundAudioActive = true
        } catch {
            // Non-fatal — the background task still runs without it,
            // but iOS may suspend audio sooner.
        }
    }
    
    /// Stops the silent audio player and deactivates the background audio session.
    private func stopSilentAudio() {
        silentPlayer?.stop()
        silentPlayer = nil
        isBackgroundAudioActive = false
        // Don't deactivate the shared session if a voice conversation is active —
        // VoiceConversationManager needs .playAndRecord active.
        guard !isVoiceConversationActive else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Public method to stop silent background audio before voice mode starts.
    /// Called from ChatView/VoiceView before starting a voice conversation
    /// to prevent audio session category conflicts (.playback vs .playAndRecord).
    func stopSilentAudioForVoice() {
        if isBackgroundAudioActive {
            stopSilentAudio()
        }
    }

    func endBackgroundTask() {
        // Don't stop silent audio while streaming — the background audio
        // session is what keeps the SSE stream alive when the app is
        // backgrounded. Only stop it when truly idle.
        if !isStreaming {
            stopSilentAudio()
        }
        if let taskId = backgroundTaskId {
            UIApplication.shared.endBackgroundTask(taskId)
            backgroundTaskId = nil
        }
    }
    
    /// Called when the app returns to the foreground. Ends the background task
    /// but keeps streaming alive — the SSE stream works fine in the foreground
    /// without the silent audio workaround.
    func handleForegroundReturn() {
        if !isStreaming {
            stopSilentAudio()
        }
        endBackgroundTask()
    }
    
    /// Send a local notification when a chat response arrives while the app
    /// is in the background. Lets the user know their message got a reply
    /// even if they switched to another app.
    private func sendBackgroundNotification(text: String) {
        let content = UNMutableNotificationContent()
        content.title = "Hermes"
        content.body = "New response received"
        content.sound = nil  // silent — the app's TTS handles audio
        content.categoryIdentifier = "chat_response"
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
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
        if msg.shouldHide {
            self.role = "hidden"
        } else {
            self.role = msg.role
        }
        self.content = msg.content ?? ""
        self.images = []
        self.timestamp = msg.date ?? Date()
    }

    /// Whether this message should be shown as a chat bubble.
    /// Tool and system messages contain raw output (JSON, file contents,
    /// command results) and should never appear in the chat UI.
    var shouldDisplay: Bool {
        isUser || isAssistant
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

struct AppError: Identifiable {
    let id = UUID()
    let message: String
}

// MARK: - Server Health State

struct ServerHealthState: Identifiable {
    let id: String  // baseURL
    let label: String
    let baseURL: String
    var status: HealthStatus = .unknown
    var latencyMs: Int? = nil
    var version: String? = nil

    enum HealthStatus {
        case online, offline, unknown, checking
    }
}
