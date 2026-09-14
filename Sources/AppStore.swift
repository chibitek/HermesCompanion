import Foundation
import SwiftUI
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
    @Published private(set) var workspaceRevision = 0
    @Published private(set) var liveChangesAvailable = false
    @Published private(set) var liveChangesError: String?
    @Published private(set) var lastServerResponseAt: Date?
    @Published private(set) var lastSyncedAt: Date?
    @Published private(set) var syncError: String?
    @Published private(set) var serverLatencyMs: Int?
    @Published private(set) var responseActivity = ""
    @Published private(set) var lastChatActivityAt: Date?
    @Published var isStreaming = false
    @Published var streamingText = ""
    /// Live reasoning text (assistant.delta events tagged tool_name=_thinking).
    /// Shown in a collapsible Thinking panel; cleared with streamingText.
    @Published var streamingThinking = ""
    @Published private(set) var toolEvents: [ToolEvent] = [] {
       didSet { if toolEvents.count > 50 { toolEvents.removeFirst(toolEvents.count - 50) } }
    }
    @Published var skills: [Skill] = []
    @Published private(set) var skillsError: String?
    @Published private(set) var toolsetsError: String?
    @Published var toolsets: [ToolsetInfo] = []
    @Published var availableModels: [String] = []
    @Published var modelInfos: [String: ModelInfo] = [:]
    @Published var modelCatalog: [ModelInfo] = []
    @Published var configuredProviders: [String] = []
    @Published var activeRuntime: SessionRuntime?
    @Published private(set) var gatewayDefaultModel = ""
    @Published private(set) var gatewayDefaultProvider = ""
    @Published private(set) var sessionModelOverride: String?
    @Published private(set) var sessionProviderOverride: String?
    @Published var platformHealth: PlatformHealthResponse?
    @Published var platformJobs: [HermesJob] = []
    @Published var artifactReceipt: HermesArtifactReceipt?
    @Published var isLoadingPlatform = false
    @Published var platformError: String?
    @Published private(set) var queuedMessages: [QueuedMessage] = [] {
        didSet { saveQueue() }
    }
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
    private static let queueKey = "message_queue"

    var effectiveCurrentProvider: String {
        nonEmpty(sessionProviderOverride)
            ?? nonEmpty(activeRuntime?.effectiveProvider)
            ?? nonEmpty(activeSession?.provider)
            ?? nonEmpty(activeSession?.billingProvider)
            ?? modelInfos[effectiveCurrentModel]?.provider
            ?? nonEmpty(capabilities?.currentProvider)
            ?? nonEmpty(gatewayDefaultProvider)
            ?? ""
    }

    var effectiveCurrentModel: String {
        nonEmpty(sessionModelOverride)
            ?? nonEmpty(activeRuntime?.effectiveModel)
            ?? nonEmpty(activeSession?.model)
            ?? nonEmpty(capabilities?.currentModel)
            ?? nonEmpty(capabilities?.model)
            ?? nonEmpty(gatewayDefaultModel)
            ?? ""
    }

    var sessionModelLockAvailable: Bool {
        capabilities?.features.sessionModelLock == true
    }

    // MARK: - Private

    private(set) var apiClient: HermesAPIClient? {
        didSet {
            guard oldValue !== apiClient else { return }
            hasExplicitlyConnected = false
            streamTask?.cancel()
            liveChangesAvailable = false
            liveChangesError = nil
            lastServerResponseAt = nil
            lastSyncedAt = nil
            syncError = nil
            serverLatencyMs = nil
            responseActivity = ""
            lastSessionListSyncAt = nil
            lastSyncedHistory = []
            lastFullHistorySyncAt = nil
            forceHistoryRefresh = false
            lastChatActivityAt = nil
            sessionSelectionID = UUID()
            capabilities = nil
            sessions = []
            activeSession = nil
            messages = []
            skills = []
            skillsError = nil
            toolsetsError = nil
            toolsets = []
            toolEvents = []
            streamingText = ""
            streamingThinking = ""
            isStreaming = false
            platformRefreshID = nil
            platformHealth = nil
            platformJobs = []
            artifactReceipt = nil
            platformError = nil
            isLoadingPlatform = false
            activeRuntime = nil
            sessionModelOverride = nil
            sessionProviderOverride = nil
            gatewayDefaultModel = ""
            gatewayDefaultProvider = ""
            modelInfos = [:]
            modelCatalog = []
            availableModels = []
            configuredProviders = []
        }
    }
    private var platformRefreshID: UUID?
    private var sessionSelectionID = UUID()
    private var modelSelectionID = UUID()
    private var sessionRefreshID = UUID()
    private var streamTask: Task<Void, Never>?
    private var chatTurnID = UUID()
    private var historyRefreshID = UUID()
    private var isSyncing = false
    private var lastSessionListSyncAt: Date?
    private var lastSyncedHistory: [SessionMessage] = []
    private var lastFullHistorySyncAt: Date?
    private var forceHistoryRefresh = false
    private let activeSessionPersistence = ActiveSessionPersistence()

    // MARK: - Init

    init(client: HermesAPIClient) {
        apiClient = client
    }

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
                        return (config.baseURL, health.status == "ok" && health.isHermesAPI ? .online : .offline, latency, health.version)
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

    var isConnected: Bool { hasExplicitlyConnected && connectionConfig != nil && !isLoadingConnection }

    // ponytail: tracks whether the user explicitly connected this session.
    // Prevents auto-connecting from a stale Keychain config on launch.
    private var hasExplicitlyConnected = false

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
        guard !isLoadingConnection, let config = connectionConfig else { return }
        isLoadingConnection = true
        let client = HermesAPIClient(config: config)
        do {
            // Health check with a 10-second timeout so we don't hang forever
            // when Tailscale is down or the server is unreachable.
            let health = try await withTimeout(seconds: 10) {
                try await client.checkHealth()
            }
            guard health.status == "ok", health.isHermesAPI else {
                FileLogger.shared.log("AppStore: autoConnect rejected \(config.baseURL) — \(Self.invalidHealthMessage(health))")
                if await fallbackToReachableServer(excluding: config.baseURL) {
                    self.isLoadingConnection = false
                    return
                }
                self.error = AppError(message: Self.invalidHealthMessage(health))
                self.isLoadingConnection = false
                return
            }
            let capabilities = try await client.getCapabilities()
            self.apiClient = client
            self.capabilities = capabilities
            await refreshSessions()
            self.isLoadingConnection = false
            hasExplicitlyConnected = true
            FileLogger.shared.log("AppStore: automatic connection succeeded")
            await refreshCapabilities()
        } catch let e as APIError {
            FileLogger.shared.log("AppStore: automatic connection failed: \(e.errorDescription ?? "Unknown API error")")
            if await fallbackToReachableServer(excluding: config.baseURL) {
                self.isLoadingConnection = false
                return
            }
            self.error = AppError(message: e.errorDescription ?? "Connection failed. Select a server to retry.")
            self.isLoadingConnection = false
        } catch {
            FileLogger.shared.log("AppStore: automatic connection failed: \(error.localizedDescription)")
            if await fallbackToReachableServer(excluding: config.baseURL) {
                self.isLoadingConnection = false
                return
            }
            self.error = AppError(message: "Could not connect to \(config.label): \(error.localizedDescription). Check the gateway URL and network, then retry.")
            self.isLoadingConnection = false
        }
    }

    func connect(config: ConnectionConfig) async -> Bool {
        isLoadingConnection = true
        defer { isLoadingConnection = false }
        let client = HermesAPIClient(config: config)
        self.apiClient = client
        // An explicit (re)connect supersedes any pending background retry.
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        do {
            let health = try await client.checkHealth()
            guard health.status == "ok", health.isHermesAPI else {
                self.error = AppError(message: Self.invalidHealthMessage(health))
                FileLogger.shared.log("AppStore: connect rejected \(config.baseURL) — \(Self.invalidHealthMessage(health))")
                return false
            }
            let capabilities = try await client.getCapabilities()
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
            self.capabilities = capabilities
            await refreshSessions()
            hasExplicitlyConnected = true
            FileLogger.shared.log("AppStore: manual connection succeeded")
            Task { await refreshCapabilities() }
            return true
        } catch let e as APIError {
            FileLogger.shared.log("AppStore: manual connection failed: \(e.errorDescription ?? "Unknown API error")")
            self.error = AppError(message: e.errorDescription ?? "Connection failed")
            self.apiClient = nil
            return false
        } catch {
            FileLogger.shared.log("AppStore: manual connection failed: \(error.localizedDescription)")
            self.error = AppError(message: "Connection failed: \(error.localizedDescription)")
            self.apiClient = nil
            return false
        }
    }

    private func fallbackToReachableServer(excluding baseURL: String) async -> Bool {
        let candidates = savedConnections.filter {
            $0.baseURL != baseURL
        }
        for candidate in candidates {
            FileLogger.shared.log("AppStore: autoConnect fallback trying \(candidate.baseURL)")
            if await connect(config: candidate) {
                FileLogger.shared.log("AppStore: autoConnect fallback connected \(candidate.baseURL)")
                return true
            }
        }
        FileLogger.shared.log("AppStore: autoConnect fallback found no reachable Hermes API gateway")
        return false
    }

    func disconnect() {
        streamTask?.cancel()
        apiClient = nil
        connectionConfig = nil
        hasExplicitlyConnected = false
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
        streamingThinking = ""
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
            self.error = AppError(message: "Could not remove the saved server from this device: \(error.localizedDescription). The connection has been kept; try again from Settings.")
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
            self.error = AppError(message: "Connect to a Hermes server in Settings before loading models.")
            return
        }
        do {
            let capabilities = try await client.getCapabilities()
            guard apiClient === client else { return }
            self.capabilities = capabilities
        } catch {
            // Non-fatal — capabilities are optional
        }
        // Load the configured-provider catalog first. This is the full list the
        // desktop sees; /v1/models is only a fallback for older gateways.
        guard apiClient === client else { return }
        do {
            let options = try await client.getModelOptions()
            guard apiClient === client else { return }
            var infos: [ModelInfo] = []
            for provider in options.providers {
                infos += provider.models.map {
                    ModelInfo(id: $0, object: "model", ownedBy: provider.name, provider: provider.slug)
                }
            }
            self.configuredProviders = options.providers.map(\.slug)
            self.gatewayDefaultModel = options.model
            self.gatewayDefaultProvider = options.provider ?? ""
            self.modelInfos = Dictionary(infos.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            self.modelCatalog = infos
            let models = infos.map(\.id)
            self.availableModels = modelsIncludingCurrent(models)
        } catch {
            guard apiClient === client else { return }
            do {
                let infos = try await client.getModels()
                guard apiClient === client else { return }
                self.modelInfos = Dictionary(infos.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                self.modelCatalog = infos
                let models = infos.map(\.id)
                self.availableModels = modelsIncludingCurrent(models)
            } catch {
                guard apiClient === client else { return }
                self.availableModels = modelsIncludingCurrent([])
                self.error = AppError(message: "Failed to load models: \(error.localizedDescription)")
            }
        }
    }

    func selectPreferredModel(_ model: String, provider: String? = nil) async {
        let requestID = UUID()
        modelSelectionID = requestID
        let selectionID = sessionSelectionID
        // Resolve provider ONLY from explicit arg or model ID prefix (e.g. "openai/gpt-4").
        // Do NOT fall back to capabilities.currentProvider — that's the gateway's
        // current state, not necessarily where this model lives. Sending a stale
        let resolvedProvider = nonEmpty(provider)
            ?? ProviderUtils.providerOf(model)
            ?? nonEmpty(modelInfos[model]?.provider)
            ?? ""
        guard let sessionId = activeSession?.id else {
            preferredModel = model
            preferredProvider = resolvedProvider
            sessionModelOverride = model
            sessionProviderOverride = resolvedProvider.isEmpty ? nil : resolvedProvider
            return
        }
        // Lock the model on the active Hermes session. This is the server-backed
        // equivalent of opening a chat in the desktop; it never rewrites the
        // gateway's global provider config.
        guard let client = apiClient else {
            error = AppError(message: "Connect to Hermes before changing this session's model.")
            return
        }
        do {
            let runtime = try await client.lockSessionModel(
                sessionId: sessionId, model: model,
                provider: resolvedProvider.isEmpty ? nil : resolvedProvider
            )
            guard apiClient === client, sessionSelectionID == selectionID,
                  activeSession?.id == sessionId, modelSelectionID == requestID,
                  !Task.isCancelled else { return }
            activeRuntime = runtime
            // An acknowledged session lock, not a picker preview, owns the
            // displayed and persisted selection. Preserve server normalization.
            preferredModel = runtime.effectiveModel ?? model
            preferredProvider = runtime.effectiveProvider ?? resolvedProvider
            sessionModelOverride = preferredModel
            sessionProviderOverride = nonEmpty(preferredProvider)
        } catch {
            guard apiClient === client, sessionSelectionID == selectionID,
                  activeSession?.id == sessionId, modelSelectionID == requestID,
                  !Task.isCancelled else { return }
            self.error = AppError(message: "Could not lock this session's model: \(error.localizedDescription)")
        }
    }

    var hasGatewayDefaultModel: Bool {
        !gatewayDefaultModel.isEmpty
    }

    func selectGatewayDefaultModel() async {
        guard hasGatewayDefaultModel else { return }
        await selectPreferredModel(
            gatewayDefaultModel,
            provider: gatewayDefaultProvider.isEmpty ? nil : gatewayDefaultProvider
        )
    }

    /// Multi-favorite toggle: starring adds to favorites, tapping again removes.
    @discardableResult
    func toggleFavorite(_ model: String) -> Bool {
        guard !model.isEmpty else { return false }
        if favoriteModels.contains(model) {
            favoriteModels.removeAll { $0 == model }
            return false
        }
        favoriteModels.append(model)
        return true
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

    nonisolated static func invalidHealthMessage(_ health: HealthResponse) -> String {
        if health.platform == "webhook" {
            return "That URL is the Hermes webhook endpoint. Use the API gateway on port 8642."
        }
        if health.status != "ok" {
            return "Server returned status: \(health.status)"
        }
        return "That URL is not a Hermes API gateway."
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
        // Restore any messages queued while the app was force-quit (H2).
        let defaults = UserDefaults.standard
        let scoped = defaults.data(forKey: preferenceKey(Self.queueKey, for: config))
            ?? defaults.data(forKey: Self.queueKey)
        queuedMessages = scoped.flatMap { try? JSONDecoder().decode([QueuedMessage].self, from: $0) } ?? []
    }

    private func saveQueue() {
        let data = try? JSONEncoder().encode(queuedMessages)
        UserDefaults.standard.set(data, forKey: preferenceKey(Self.queueKey, for: connectionConfig))
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
            self.error = AppError(message: "Connect to a Hermes server in Settings before loading conversation history.")
            return
        }
        let refreshID = UUID()
        sessionRefreshID = refreshID
        do {
            let sessions = try await client.listSessions()
            guard !Task.isCancelled, apiClient === client, sessionRefreshID == refreshID else { return }
            applySessionSnapshot(sessions)
            await reconcileMissingActiveSession(client: client, refreshID: refreshID)
            guard apiClient === client, sessionRefreshID == refreshID else { return }
            await restoreActiveSessionIfAvailable()
        } catch {
            guard !Task.isCancelled, apiClient === client, sessionRefreshID == refreshID else { return }
            self.error = AppError(message: "Failed to load sessions: \(error.localizedDescription)")
            syncError = "Session sync paused: \(error.localizedDescription) Retrying automatically."
            FileLogger.shared.log("AppStore: refreshSessions failed for \(connectionConfig?.baseURL ?? "unknown") — \(error.localizedDescription)")
        }
    }

    private func applySessionSnapshot(_ sessions: [HermesSession]) {
        self.sessions = sessions
        guard !isStreaming, let current = activeSession,
              let updated = sessions.first(where: { $0.id == current.id }) else { return }
        if current.model != updated.model || current.provider != updated.provider ||
            current.billingProvider != updated.billingProvider {
            activeRuntime = nil
            sessionModelOverride = nil
            sessionProviderOverride = nil
        }
        activeSession = updated
    }

    private func reconcileMissingActiveSession(client: HermesAPIClient, refreshID: UUID) async {
        guard apiClient === client, sessionRefreshID == refreshID, !isStreaming,
              let current = activeSession, !sessions.contains(where: { $0.id == current.id }) else { return }
        let selectionID = sessionSelectionID
        do {
            _ = try await client.getSession(sessionId: current.id)
        } catch let failure as APIError where failure.isNotFound {
            guard apiClient === client, sessionRefreshID == refreshID,
                  sessionSelectionID == selectionID, activeSession?.id == current.id,
                  !isStreaming, !Task.isCancelled else { return }
            sessionSelectionID = UUID()
            stopStreaming()
            activeSession = nil
            activeRuntime = nil
            sessionModelOverride = nil
            sessionProviderOverride = nil
            toolEvents = []
            messages = []
            if let baseURL = connectionConfig?.normalizedBaseURL {
                activeSessionPersistence.clear(for: baseURL)
            }
        } catch {
            // A failed probe is not evidence of deletion.
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
            self.error = AppError(message: "Connect to a Hermes server in Settings before creating a conversation.")
            return
        }
        stopStreaming()
        let creationID = UUID()
        sessionSelectionID = creationID
        do {
            let session = try await client.createSession(title: title,
                model: sessionModelLockAvailable ? nonEmpty(sessionModelOverride ?? gatewayDefaultModel) : nil,
                provider: sessionModelLockAvailable ? nonEmpty(sessionProviderOverride ?? gatewayDefaultProvider) : nil)
            guard apiClient === client, sessionSelectionID == creationID else { return }
            sessionRefreshID = UUID()
            self.sessions.insert(session, at: 0)
            await selectSession(session)
        } catch {
            guard apiClient === client, sessionSelectionID == creationID else { return }
            self.error = AppError(message: "Failed to create session: \(error.localizedDescription)")
        }
    }

    func selectSession(_ session: HermesSession) async {
        stopStreaming()
        let selectionID = UUID()
        sessionSelectionID = selectionID
        let client: HermesAPIClient
        do {
            client = try self.client()
        } catch {
            self.error = AppError(message: "Connect to a Hermes server in Settings before opening this conversation.")
            return
        }
        self.activeSession = session
        if let baseURL = connectionConfig?.normalizedBaseURL {
            activeSessionPersistence.save(sessionID: session.id, for: baseURL)
        }
        self.messages = []
        lastSyncedHistory = []
        self.toolEvents = []
        self.streamingText = ""
            self.streamingThinking = ""
        sessionModelOverride = nil
        sessionProviderOverride = nil
        activeRuntime = nil
        do {
            let history = try await client.getMessages(sessionId: session.id)
            guard apiClient === client, sessionSelectionID == selectionID else { return }
            self.lastSyncedHistory = history
            self.lastFullHistorySyncAt = Date()
            self.messages = history
                .filter { $0.isUser || $0.isAssistant }
                .map { ChatDisplayMessage(from: $0) }
        } catch {
            guard apiClient === client, sessionSelectionID == selectionID else { return }
            self.error = AppError(message: "Failed to load messages: \(error.localizedDescription)")
        }
        guard apiClient === client, sessionSelectionID == selectionID else { return }
        // Session model is the server's durable row value. Use it to show a
        // sane current model even when Hermes is older and has no runtime lock.
        if let model = session.model, !model.isEmpty {
            activeRuntime = SessionRuntime(
                provider: session.provider ?? session.billingProvider ?? modelInfos[model]?.provider,
                model: model,
                routeSource: "session",
                requested: nil,
                modelLock: nil
            )
        } else {
            activeRuntime = nil
        }
    }

    /// Runs only while the app is foregrounded. Serial reads prevent overlapping
    /// polls; transcript, selection and turn IDs reject stale in-flight snapshots.
    func runLiveSync() async {
        guard let client = apiClient else { return }
        let changes = Task { await watchWorkspaceChanges(client: client) }
        defer { changes.cancel() }
        while !Task.isCancelled {
            guard apiClient === client else { return }
            await syncNow()
            do { try await Task.sleep(for: .seconds(syncError == nil ? 2 : 5)) }
            catch { return }
        }
    }

    private func watchWorkspaceChanges(client: HermesAPIClient) async {
        while !Task.isCancelled, apiClient === client {
            do {
                let events = try await client.workspaceChanges()
                guard apiClient === client, !Task.isCancelled else { return }
                liveChangesAvailable = true
                liveChangesError = nil
                for try await event in events {
                    guard apiClient === client, !Task.isCancelled else { return }
                    if event.event == "error" {
                        throw APIError.invalidEndpoint(event.message ?? "The workspace change feed failed without a reason. Check the gateway log.")
                    }
                    guard event.event == "workspace.changed" else { continue }
                    workspaceRevision += 1
                    forceHistoryRefresh = true
                    lastSessionListSyncAt = nil
                    await syncNow()
                }
                try Task.checkCancellation()
                throw APIError.invalidEndpoint("The workspace change feed disconnected.")
            } catch {
                guard apiClient === client, !Task.isCancelled else { return }
                liveChangesAvailable = false
                if let failure = error as? APIError, failure.isNotFound {
                    liveChangesError = "Using periodic sync. Install Companion bridge 0.1.7 on this server for live workspace updates."
                    return
                }
                liveChangesError = "Live updates interrupted: \(error.localizedDescription) Periodic sync remains active."
                do { try await Task.sleep(for: .seconds(5)) }
                catch { return }
            }
        }
    }

    func syncNow() async {
        guard !isSyncing, !isLoadingConnection, let client = apiClient else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let start = Date()
            let health = try await client.checkHealth()
            guard apiClient === client, !Task.isCancelled else { return }
            guard health.status == "ok", health.isHermesAPI else {
                throw APIError.invalidEndpoint(Self.invalidHealthMessage(health))
            }
            serverLatencyMs = Int(Date().timeIntervalSince(start) * 1_000)
            lastServerResponseAt = Date()
            // The catalog is much larger than a health response. Refresh it on
            // its own cadence; selected chat changes are fetched every cycle.
            if !isStreaming, lastSessionListSyncAt == nil || Date().timeIntervalSince(lastSessionListSyncAt!) >= 10 {
                let refreshID = UUID()
                sessionRefreshID = refreshID
                let snapshot = try await client.listSessions()
                guard apiClient === client, sessionRefreshID == refreshID, !Task.isCancelled else { return }
                applySessionSnapshot(snapshot)
                await reconcileMissingActiveSession(client: client, refreshID: refreshID)
                guard apiClient === client, sessionRefreshID == refreshID, !Task.isCancelled else { return }
                lastSessionListSyncAt = Date()
            }
            if let active = activeSession, !isStreaming {
                try await refreshActiveSessionMessages(active, client: client)
            }
            guard apiClient === client, !Task.isCancelled else { return }
            syncError = nil
            if !isStreaming, activeSession != nil { lastSyncedAt = Date() }
        } catch {
            guard apiClient === client, !Task.isCancelled else { return }
            syncError = "Sync paused: \(error.localizedDescription) Retrying automatically."
        }
    }

    func refreshActiveSessionMessages(_ session: HermesSession, client: HermesAPIClient) async throws {
        guard apiClient === client, !isStreaming else { return }
        let selection = sessionSelectionID
        let turn = chatTurnID
        let refresh = UUID()
        historyRefreshID = refresh
        let recent = try await client.getLatestMessages(sessionId: session.id)
        guard apiClient === client, sessionSelectionID == selection, chatTurnID == turn,
              historyRefreshID == refresh, !isStreaming, !Task.isCancelled else { return }
        let needsFullRefresh = forceHistoryRefresh || lastFullHistorySyncAt == nil
            || Date().timeIntervalSince(lastFullHistorySyncAt!) >= 60
        guard needsFullRefresh || recent != Array(lastSyncedHistory.suffix(50))
            || messages.isEmpty && !recent.isEmpty else { return }
        let history = try await client.getMessages(sessionId: session.id)
        guard apiClient === client, activeSession?.id == session.id,
              sessionSelectionID == selection, chatTurnID == turn,
              historyRefreshID == refresh, !isStreaming, !Task.isCancelled else { return }
        if needsFullRefresh || history != lastSyncedHistory {
            messages = history.filter { $0.isUser || $0.isAssistant }.map { ChatDisplayMessage(from: $0) }
            lastSyncedHistory = history
        }
        lastFullHistorySyncAt = Date()
        forceHistoryRefresh = false
    }

    func deleteSession(_ session: HermesSession) async {
        let client: HermesAPIClient
        do {
            client = try self.client()
        } catch {
            self.error = AppError(message: "Connect to a Hermes server in Settings before deleting this conversation.")
            return
        }
        do {
            try await client.deleteSession(sessionId: session.id)
            guard apiClient === client else { return }
            sessionRefreshID = UUID()
            self.sessions.removeAll { $0.id == session.id }
            if activeSession?.id == session.id {
                sessionSelectionID = UUID()
                stopStreaming()
                activeSession = nil
                activeRuntime = nil
                sessionModelOverride = nil
                sessionProviderOverride = nil
                toolEvents = []
                messages = []
                if let baseURL = connectionConfig?.normalizedBaseURL {
                    activeSessionPersistence.clear(for: baseURL)
                }
            }
        } catch {
            guard apiClient === client else { return }
            self.error = AppError(message: "Failed to delete session: \(error.localizedDescription)")
        }
    }

    func renameSession(_ session: HermesSession, newTitle: String) async {
        let client: HermesAPIClient
        do {
            client = try self.client()
        } catch {
            self.error = AppError(message: "Connect to a Hermes server in Settings before renaming this conversation.")
            return
        }
        do {
            let updated = try await client.patchSession(sessionId: session.id, title: newTitle)
            guard apiClient === client else { return }
            sessionRefreshID = UUID()
            if let idx = self.sessions.firstIndex(where: { $0.id == session.id }) {
                self.sessions[idx] = updated
            }
            if self.activeSession?.id == session.id {
                self.activeSession = updated
            }
        } catch {
            guard apiClient === client else { return }
            self.error = AppError(message: "Failed to rename session: \(error.localizedDescription)")
        }
    }

    func updateSessionFlags(
        _ session: HermesSession,
        isPinned: Bool? = nil,
        isArchived: Bool? = nil,
        isHidden: Bool? = nil
    ) async {
        let client: HermesAPIClient
        do {
            client = try self.client()
        } catch {
            self.error = AppError(message: "Connect to a Hermes server in Settings before changing this conversation.")
            return
        }
        do {
            let updated = try await client.patchSession(
                sessionId: session.id,
                isPinned: isPinned,
                isArchived: isArchived,
                isHidden: isHidden
            )
            guard apiClient === client else { return }
            sessionRefreshID = UUID()
            replaceSession(updated)
        } catch {
            guard apiClient === client else { return }
            self.error = AppError(message: "Could not update chat: \(error.localizedDescription)")
        }
    }

    private func replaceSession(_ updated: HermesSession) {
        if let index = sessions.firstIndex(where: { $0.id == updated.id }) {
            sessions[index] = updated
        }
        if activeSession?.id == updated.id {
            activeSession = updated
        }
        if updated.isArchived == true && activeSession?.id == updated.id {
            sessionSelectionID = UUID()
            stopStreaming()
            activeSession = nil
            activeRuntime = nil
            sessionModelOverride = nil
            sessionProviderOverride = nil
            toolEvents = []
            messages = []
            if let baseURL = connectionConfig?.normalizedBaseURL {
                activeSessionPersistence.clear(for: baseURL)
            }
        }
    }

    func forkSession(_ session: HermesSession) async {
        let client: HermesAPIClient
        do {
            client = try self.client()
        } catch {
            self.error = AppError(message: "Connect to a Hermes server in Settings before forking this conversation.")
            return
        }
        let selectionID = sessionSelectionID
        do {
            let forked = try await client.forkSession(sessionId: session.id, title: forkTitle(for: session))
            guard apiClient === client, sessionSelectionID == selectionID else { return }
            sessionRefreshID = UUID()
            self.sessions.insert(forked, at: 0)
            await selectSession(forked)
        } catch {
            guard apiClient === client, sessionSelectionID == selectionID else { return }
            self.error = AppError(message: "Failed to fork session: \(error.localizedDescription)")
        }
    }

    private func forkTitle(for session: HermesSession) -> String {
        let base = (session.title.flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled").trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(base) Fork"
    }

    // MARK: - Skills

    func refreshSkills() async {
        guard let client = try? self.client() else { return }
        do {
            let skills = try await client.listSkills()
            guard apiClient === client, !Task.isCancelled else { return }
            self.skills = skills
            skillsError = nil
        } catch {
            guard apiClient === client, !Task.isCancelled else { return }
            skillsError = "Could not load skills: \(error.localizedDescription)"
        }
    }

    func refreshToolsets() async {
        guard let client = try? self.client() else { return }
        do {
            let toolsets = try await client.getToolsets()
            guard apiClient === client, !Task.isCancelled else { return }
            self.toolsets = toolsets
            toolsetsError = nil
        } catch {
            guard apiClient === client, !Task.isCancelled else { return }
            toolsetsError = "Could not load toolsets: \(error.localizedDescription)"
        }
    }

    func refreshPlatform() async {
        let client: HermesAPIClient
        do {
            client = try self.client()
        } catch {
            platformError = "Connect to a Hermes server in Settings before loading platform status."
            return
        }
        isLoadingPlatform = true
        platformError = nil
        let refreshID = UUID()
        platformRefreshID = refreshID
        let sessionsID = UUID()
        sessionRefreshID = sessionsID
        defer {
            if platformRefreshID == refreshID { isLoadingPlatform = false }
        }
        async let health = client.getDetailedHealth()
        async let jobs = client.listJobs()
        async let capabilities = client.getCapabilities()
        async let sessions = client.listSessions()
        async let toolsets = client.getToolsets()
        async let skills = client.listSkills()
        do {
            let value = try await health
            guard apiClient === client, platformRefreshID == refreshID else { return }
            platformHealth = value
        } catch {
            guard apiClient === client, platformRefreshID == refreshID else { return }
            platformError = error.localizedDescription
        }
        do {
            let value = try await jobs
            guard apiClient === client, platformRefreshID == refreshID else { return }
            platformJobs = value
        } catch {
            guard apiClient === client, platformRefreshID == refreshID else { return }
            platformError = [platformError, "Jobs: \(error.localizedDescription)"].compactMap { $0 }.joined(separator: "\n")
        }
        do {
            let value = try await capabilities
            guard apiClient === client, platformRefreshID == refreshID else { return }
            self.capabilities = value
        } catch {
            // Keep the cached capabilities; they remain useful on transient errors.
        }
        do {
            let value = try await sessions
            guard apiClient === client, platformRefreshID == refreshID else { return }
            if sessionRefreshID == sessionsID, !Task.isCancelled {
                applySessionSnapshot(value)
                await reconcileMissingActiveSession(client: client, refreshID: sessionsID)
                if apiClient === client, sessionRefreshID == sessionsID {
                    await restoreActiveSessionIfAvailable()
                }
            }
        } catch {
            guard apiClient === client, platformRefreshID == refreshID else { return }
            platformError = [platformError, "Sessions: \(error.localizedDescription)"].compactMap { $0 }.joined(separator: "\n")
        }
        do {
            let value = try await toolsets
            guard apiClient === client, platformRefreshID == refreshID else { return }
            self.toolsets = value
            toolsetsError = nil
        } catch {
            guard apiClient === client, platformRefreshID == refreshID else { return }
            toolsetsError = "Toolsets: \(error.localizedDescription)"
            platformError = [platformError, toolsetsError].compactMap { $0 }.joined(separator: "\n")
        }
        do {
            let value = try await skills
            guard apiClient === client, platformRefreshID == refreshID else { return }
            self.skills = value
            skillsError = nil
        } catch {
            guard apiClient === client, platformRefreshID == refreshID else { return }
            skillsError = "Skills: \(error.localizedDescription)"
            platformError = [platformError, skillsError].compactMap { $0 }.joined(separator: "\n")
        }
    }

    func controlJob(_ job: HermesJob, action: HermesJobAction) async {
        let client: HermesAPIClient
        do {
            client = try self.client()
        } catch {
            platformError = "Connect to a Hermes server in Settings before controlling this job."
            return
        }
        do {
            switch action {
            case .pause: try await client.pauseJob(jobId: job.id)
            case .resume: try await client.resumeJob(jobId: job.id)
            case .run: try await client.runJob(jobId: job.id)
            case .delete: try await client.deleteJob(jobId: job.id)
            }
            guard apiClient === client else { return }
            await refreshJobsOnly()
        } catch {
            guard apiClient === client else { return }
            platformError = "Job \(action.rawValue) failed: \(error.localizedDescription)"
        }
    }

    func saveJob(_ payload: HermesJobWrite, jobId: String? = nil) async -> Bool {
        let client: HermesAPIClient
        do {
            client = try self.client()
        } catch {
            platformError = "Connect to a Hermes server in Settings before saving this job."
            return false
        }
        platformError = nil
        do {
            if let jobId {
                _ = try await client.updateJob(jobId: jobId, updates: payload)
            } else {
                _ = try await client.createJob(payload)
            }
            guard apiClient === client else { return false }
            await refreshJobsOnly()
            return true
        } catch {
            guard apiClient === client else { return false }
            platformError = "Could not save job: \(error.localizedDescription)"
            return false
        }
    }

    private func refreshJobsOnly() async {
        guard let client = apiClient else { return }
        do {
            let jobs = try await client.listJobs()
            guard apiClient === client else { return }
            platformJobs = jobs
        } catch {
            guard apiClient === client else { return }
            platformError = "Could not refresh jobs: \(error.localizedDescription)"
        }
    }

    func uploadArtifact(data: Data, fileName: String, mimeType: String) async {
        let client: HermesAPIClient
        do {
            client = try self.client()
        } catch {
            platformError = "Connect to a Hermes server in Settings before uploading this file."
            return
        }
        do {
            let receipt = try await client.uploadArtifact(
                data: data, fileName: fileName, mimeType: mimeType
            )
            guard apiClient === client else { return }
            artifactReceipt = receipt
            platformError = nil
        } catch {
            guard apiClient === client else { return }
            platformError = "Artifact upload failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Chat (streaming)

    func queueMessage(_ text: String, displayText: String? = nil) {
        let payload = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !payload.isEmpty else { return }
        queuedMessages.append(QueuedMessage(payload: payload, display: displayText ?? payload))
    }

    @discardableResult
    func sendMessage(_ text: String, displayText: String? = nil, images: [Data] = [], attachments: [AttachmentData] = [], skipPostReload: Bool = false) async -> ChatDisplayMessage? {
        let client: HermesAPIClient
        do {
            client = try self.client()
        } catch {
            self.error = AppError(message: "Connect to a Hermes server in Settings before sending this message.")
            return nil
        }

        let turnID = UUID()
        chatTurnID = turnID
        streamTask?.cancel()
        error = nil
        responseActivity = "Preparing chat on Hermes"
        lastChatActivityAt = nil
        isStreaming = true
        let session = await ensureSession(client: client)
        guard let session, apiClient === client, chatTurnID == turnID else {
            if chatTurnID == turnID { isStreaming = false }
            return nil
        }
        let existingAssistantCount = messages.filter(\.isAssistant).count

        let userMsg = ChatDisplayMessage(
            id: UUID().uuidString,
            role: "user",
            content: displayText ?? text,
            images: images,
            timestamp: Date()
        )
        messages.append(userMsg)

        error = nil
        responseActivity = "Sending to Hermes"
        lastChatActivityAt = nil
        isStreaming = true
        streamingText = ""
        streamingThinking = ""
        toolEvents = []
        beginBackgroundKeepAlive()

        let watchdog = StreamWatchdogManager()
        // 180s initial grace: the server can take 30-60s to process a large
        // system prompt and emit the first SSE event, especially via Tailscale.
        // After that, 60s with no events AND no keepalives means a dead socket
        // (keepalive comments reset the timer via onKeepalive).
        watchdog.arm(after: 60, initialTimeout: 180) { [weak self] in
            guard let self, self.isStreaming, self.chatTurnID == turnID,
                  self.apiClient === client, self.activeSession?.id == session.id else { return }
            self.streamTask?.cancel()
            self.isStreaming = false
            self.streamingText = ""
            self.streamingThinking = ""
            self.endBackgroundTask()
            self.responseActivity = "Response stream stalled"
            self.error = AppError(message: "Hermes stopped sending chat events and keepalives for 60 seconds after activity, or did not respond within 180 seconds. The turn may be incomplete. Check the server and refresh this chat before resending to avoid duplicate work.")
        }

        streamTask?.cancel()

        var assistantMessage: ChatDisplayMessage?
        var receivedCompletion = false

        let task = Task { [weak self] in
            guard let self = self else { return }
            defer { watchdog.cancel() }
            do {
                if images.isEmpty && attachments.isEmpty {
                    let (streamedMsg, streamedCompletion) = try await self.streamMessage(
                        client: client, session: session, text: text, watchdog: watchdog
                    )
                    try Task.checkCancellation()
                    guard self.chatTurnID == turnID, self.apiClient === client,
                          self.activeSession?.id == session.id else { return }
                    assistantMessage = streamedMsg
                    if streamedCompletion { receivedCompletion = true }
                    if !self.streamingText.isEmpty {
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
            self.streamingThinking = ""
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
                try Task.checkCancellation()
                guard self.chatTurnID == turnID, self.apiClient === client,
                      self.activeSession?.id == session.id else { return }

                if assistantMessage == nil {
                    let assistants = self.messages.filter(\.isAssistant)
                    // A reload can recover a missing completion, but an unchanged
                    // transcript must never replay an earlier answer as this turn.
                    if assistants.count > existingAssistantCount {
                        assistantMessage = assistants.last
                    }
                }

                self.emptyStreamGuard(
                    receivedCompletion: receivedCompletion,
                    existingAssistantCount: existingAssistantCount
                )
            } catch is CancellationError {
                // Cancelled on purpose (barge-in, stop tap, new turn superseding
                // this one). Not an error — don't surface "Message failed".
            } catch let e as APIError {
                if !Task.isCancelled, self.chatTurnID == turnID, self.apiClient === client {
                    self.error = AppError(message: e.errorDescription ?? "Message failed")
                }
            } catch {
                if !Task.isCancelled, self.chatTurnID == turnID, self.apiClient === client {
                    self.error = AppError(message: "Message failed: \(error.localizedDescription)")
                }
            }
            guard self.chatTurnID == turnID, self.apiClient === client,
                  self.activeSession?.id == session.id else { return }
            if self.error != nil, !self.streamingText.isEmpty {
                self.messages.append(ChatDisplayMessage(id: UUID().uuidString, role: "assistant",
                    content: Self.stripRawArtifacts(self.streamingText), timestamp: Date()))
            }
            self.streamingText = ""
            self.streamingThinking = ""
            self.isStreaming = false
            self.responseActivity = Task.isCancelled ? "Response canceled" : (self.error == nil ? "Response complete" : "Response needs attention")
            self.lastSessionListSyncAt = nil
            self.endBackgroundTask()

            if !Task.isCancelled, self.error == nil, !self.queuedMessages.isEmpty {
                let next = self.queuedMessages.removeFirst()
                Task {
                    guard self.chatTurnID == turnID, self.apiClient === client,
                          self.activeSession?.id == session.id else { return }
                    await self.sendMessage(next.payload, displayText: next.display)
                }
            }

            if self.error == nil, assistantMessage != nil, !Task.isCancelled,
               UIApplication.shared.applicationState != .active {
                sendBackgroundNotification()
            }
        }
        streamTask = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        guard chatTurnID == turnID, apiClient === client, activeSession?.id == session.id,
              !task.isCancelled, error == nil else { return nil }
        return assistantMessage
    }

    // MARK: - sendMessage Helpers

    private func ensureSession(client: HermesAPIClient) async -> HermesSession? {
        let selectionID = sessionSelectionID
        let turnID = chatTurnID
        if let active = activeSession { return active }
        do {
            let newSession = try await client.createSession(title: nil,
                model: sessionModelLockAvailable ? nonEmpty(sessionModelOverride ?? gatewayDefaultModel) : nil,
                provider: sessionModelLockAvailable ? nonEmpty(sessionProviderOverride ?? gatewayDefaultProvider) : nil)
            guard apiClient === client, sessionSelectionID == selectionID, chatTurnID == turnID else { return nil }
            sessionRefreshID = UUID()
            self.sessions.insert(newSession, at: 0)
            self.activeSession = newSession
            if let baseURL = connectionConfig?.normalizedBaseURL {
                activeSessionPersistence.save(sessionID: newSession.id, for: baseURL)
            }
            return newSession
        } catch {
            guard apiClient === client, sessionSelectionID == selectionID, chatTurnID == turnID else { return nil }
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
        let turn = chatTurnID
        let stream = try await client.streamChat(
            sessionId: session.id, message: text,
            model: sessionModelLockAvailable ? nil : sessionModelOverride,
            onKeepalive: { [weak self] in
                watchdog.recordActivity()
                Task { @MainActor in
                    guard let self, self.apiClient === client, self.activeSession?.id == session.id,
                          self.isStreaming, self.chatTurnID == turn else { return }
                    self.lastServerResponseAt = Date()
                    self.lastChatActivityAt = Date()
                }
            }
        )
        for try await event in stream {
            try Task.checkCancellation()
            guard apiClient === client, activeSession?.id == session.id else { throw CancellationError() }
            watchdog.recordActivity()
            lastServerResponseAt = Date()
            lastChatActivityAt = Date()
            if event.event == "error" {
                throw APIError.invalidEndpoint("Hermes stopped this chat turn: \(event.message ?? "The server emitted an error event without a reason. Check the gateway log for this session.")")
            }
            if event.partial == true || event.interrupted == true {
                error = AppError(message: "Hermes returned an incomplete response (\(event.interrupted == true ? "interrupted" : "partial")). Review the saved conversation and server log before continuing.")
            }
            if event.event == "assistant.completed" || event.event == "run.completed" {
                receivedCompletion = true
            }
            if let completedMessage = await self.handleSSEEvent(event) {
                assistantMessage = completedMessage
            }
        }
        if !receivedCompletion {
            throw APIError.invalidEndpoint("Hermes closed the response stream before confirming completion. Any visible text is partial. Refresh this chat and check the server before resending.")
        }
        return (assistantMessage, receivedCompletion)
    }

    private func sendWithAttachments(
        client: HermesAPIClient, session: HermesSession, text: String,
        images: [Data], attachments: [AttachmentData]
    ) async throws -> ChatDisplayMessage? {
        let response = try await client.sendChat(
            sessionId: session.id, message: text,
            model: sessionModelLockAvailable ? nil : sessionModelOverride,
            images: images, attachments: attachments
        )
        try Task.checkCancellation()
        guard apiClient === client, activeSession?.id == session.id else { throw CancellationError() }
        if let runtime = response.runtime { activeRuntime = runtime }
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
            try Task.checkCancellation()
            guard apiClient === client, activeSession?.id == session.id else { throw CancellationError() }
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
            try Task.checkCancellation()
            guard apiClient === client, activeSession?.id == session.id else { throw CancellationError() }
            self.messages = history
                .filter { $0.isUser || $0.isAssistant }
                .map { ChatDisplayMessage(from: $0) }
            await refreshSessions()
        }

        return (msg, completion)
    }

    private func emptyStreamGuard(receivedCompletion: Bool, existingAssistantCount: Int) {
        guard !receivedCompletion, error == nil else { return }
        let newAssistantCount = self.messages.filter(\.isAssistant).count
        if newAssistantCount <= existingAssistantCount {
            self.error = AppError(message: "No response received — the server may have closed the connection early. Please try again.")
        }
    }

    func stopStreaming() {
        chatTurnID = UUID()
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
        streamingText = ""
        streamingThinking = ""
        queuedMessages.removeAll()
        endBackgroundTask()
    }

    // MARK: - SSE Event Handler

    private func handleSSEEvent(_ event: SSEEventPayload) async -> ChatDisplayMessage? {
        switch event.event {
        case "run.started", "message.started":
            responseActivity = "Hermes accepted the message"

        case "assistant.delta":
            responseActivity = "Hermes is responding"
            // The gateway reuses assistant.delta for thinking/reasoning text
            // by setting tool_name to "_thinking" or other tool names. That
            // internal reasoning must NOT be appended to streamingText or
            // it leaks raw JSON and agent thoughts into the chat UI.
            if let tname = event.toolName, !tname.isEmpty {
                if (tname == "_thinking" || tname == "thinking"), let delta = event.delta {
                    streamingThinking += delta
                }
                break
            }
            if let delta = event.delta {
                let cleaned = Self.stripRawArtifacts(delta)
                if !cleaned.isEmpty {
                    streamingText += cleaned
                }
            }
        case "tool.progress":
            responseActivity = event.toolName == "_thinking" ? "Hermes is thinking" : "Hermes is working"
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
            responseActivity = "Hermes is running \(event.toolName ?? "a tool")"
            let startToolName = event.toolName ?? "unknown"
            if startToolName == "_thinking" || startToolName == "thinking" { break }
            toolEvents.append(ToolEvent(
                id: UUID().uuidString,
                type: .started,
                toolName: startToolName,
                detail: event.preview ?? ""
            ))

        case "tool.completed":
            responseActivity = "Hermes finished \(event.toolName ?? "a tool")"
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
            if let runtime = event.runtime {
                activeRuntime = runtime
            }
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
                streamingThinking = ""
                return message
            }
            streamingText = ""
            streamingThinking = ""

        case "run.completed":
            responseActivity = "Hermes confirmed completion"
            if let runtime = event.runtime {
                activeRuntime = runtime
            }
            streamingText = ""
            streamingThinking = ""

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

        // Strip reasoning/thinking blocks: <think> to </think> (inclusive)
        while let startTag = cleaned.range(of: "<think"),
              let endTag = cleaned.range(of: "</think", range: startTag.upperBound..<cleaned.endIndex) {
            cleaned.removeSubrange(startTag.lowerBound..<endTag.upperBound)
        }
        // Strip any leftover bare <think> or </think> tags (unclosed or mismatched)
        cleaned = cleaned.replacingOccurrences(of: "<think>", with: "")
        cleaned = cleaned.replacingOccurrences(of: "</think>", with: "")

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
    private var reconnectWorkItem: DispatchWorkItem?

    func reconnectIfNeeded() async {
        guard connectionConfig != nil, !isReconnecting, let client = apiClient else { return }
        isReconnecting = true
        defer { isReconnecting = false }
        // URLSession reconnects its transport itself. Replacing the API client
        // erased the current chat and could install an old server after a switch.
        await syncNow()
        guard apiClient === client, syncError == nil, !Task.isCancelled else { return }
        await refreshCapabilities()
    }

    private var backgroundTaskId: UIBackgroundTaskIdentifier?

    /// Begins a short background task to keep the network connection alive
    /// during quick app switches (e.g., checking a message in another app).
    /// iOS controls the available background time. Text networking must not
    /// activate audio or change the user's playback route to extend it.
    func beginBackgroundKeepAlive() {
        endBackgroundTask()
        backgroundTaskId = UIApplication.shared.beginBackgroundTask(expirationHandler: { [weak self] in
            self?.endBackgroundTask()
        })
    }

    func endBackgroundTask() {
        if let taskId = backgroundTaskId {
            UIApplication.shared.endBackgroundTask(taskId)
            backgroundTaskId = nil
        }
    }
    
    /// Called when the app returns to the foreground. Ends the background task
    /// without changing audio or cancelling an active foreground stream.
    func handleForegroundReturn() {
        endBackgroundTask()
    }
    
    /// Send a local notification when a chat response arrives while the app
    /// is in the background. Lets the user know their message got a reply
    /// even if they switched to another app.
    private func sendBackgroundNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Hermes"
        // Generic body on purpose — keep message content off the lock screen.
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

/// A queued chat turn: the API payload plus the text the user actually saw.
/// Persisted per-connection so a force-quit doesn't silently drop accepted input.
struct QueuedMessage: Codable, Equatable {
    let payload: String
    let display: String
}

struct ChatDisplayMessage: Identifiable, Equatable {
    let id: String
    let role: String
    let content: String
    let images: [Data]
    let toolNames: [String]
    let timestamp: Date

    var isUser: Bool { role == "user" }
    var isAssistant: Bool { role == "assistant" }

    init(id: String, role: String, content: String, images: [Data] = [], toolNames: [String] = [], timestamp: Date) {
        self.id = id
        self.role = role
        self.content = content
        self.images = images
        self.toolNames = toolNames
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
        self.toolNames = (msg.toolCalls ?? []).map { call in
            let name = call.function?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return name.isEmpty ? "Tool call (name not reported)" : name
        }
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
