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
        didSet { UserDefaults.standard.set(preferredProvider, forKey: Self.providerKey) }
    }

    /// Persisted model id. Locally scoped per-connection.
    @Published var preferredModel: String = "" {
        didSet { UserDefaults.standard.set(preferredModel, forKey: Self.modelKey) }
    }

    /// Persisted reasoning effort: "", "low", "medium", "high".
    /// Note: the gateway chat endpoint doesn't honor a per-message reasoning_effort
    /// override today — this is a local preference only, surfaced in the UI and
    /// ready for the server to honor when support lands.
    @Published var preferredThinking: String = "" {
        didSet { UserDefaults.standard.set(preferredThinking, forKey: Self.thinkingKey) }
    }

    private static let providerKey = "preferred_provider"
    private static let modelKey = "preferred_model"
    private static let thinkingKey = "preferred_thinking"

    // MARK: - Private

    private(set) var apiClient: HermesAPIClient?
    private var streamTask: Task<Void, Never>?

    // MARK: - Init

    init() {
        // Load provider/model/thinking preferences from UserDefaults
        let defaults = UserDefaults.standard
        self.preferredProvider = defaults.string(forKey: Self.providerKey) ?? ""
        self.preferredModel = defaults.string(forKey: Self.modelKey) ?? ""
        self.preferredThinking = defaults.string(forKey: Self.thinkingKey) ?? ""

        // Load all saved connections for the multi-connection picker
        self.savedConnections = KeychainManager.shared.loadAll()

        var initialConfig = KeychainManager.shared.loadActive()
        #if DEBUG
        if initialConfig == nil {
            initialConfig = Self.debugConnectionFromEnvironment()
        }
        #endif

        if let initialConfig {
            connectionConfig = initialConfig
            apiClient = HermesAPIClient(config: initialConfig)
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
        capabilities = nil
        sessions = []
        activeSession = nil
        messages = []
        skills = []
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
        pendingApproval = nil

        self.connectionConfig = config
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
            self.availableModels = try await client.getModels().map { $0.id }
        } catch {
            // Non-fatal
        }
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

    // MARK: - Skills

    func refreshSkills() async {
        guard let client = try? self.client() else { return }
        do {
            self.skills = try await client.listSkills()
        } catch {
            // Non-fatal
        }
    }

    // MARK: - Chat (streaming)

    func sendMessage(_ text: String, images: [Data] = [], attachments: [AttachmentData] = []) async {
        let client: HermesAPIClient
        do {
            client = try self.client()
        } catch {
            self.error = AppError(message: "Not connected")
            return
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
                return
            }
        }

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

        let task = Task { [weak self] in
            guard let self = self else { return }
            do {
                if images.isEmpty && attachments.isEmpty {
                    let stream = try await client.streamChat(sessionId: session.id, message: messagePayload)
                    for try await event in stream {
                        if Task.isCancelled { return }
                        await self.handleSSEEvent(event)
                    }

                    if !streamingText.isEmpty {
                        messages.append(ChatDisplayMessage(
                            id: UUID().uuidString,
                            role: "assistant",
                            content: streamingText,
                            timestamp: Date()
                        ))
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

                    let content = response.message.content
                    if !content.isEmpty {
                        messages.append(ChatDisplayMessage(
                            id: UUID().uuidString,
                            role: response.message.role,
                            content: content,
                            timestamp: Date()
                        ))
                    }
                }
                let history = try await client.getMessages(sessionId: session.id)
                self.messages = history.map { ChatDisplayMessage(from: $0) }
                await refreshSessions()
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

    private func handleSSEEvent(_ event: SSEEventPayload) async {
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
                messages.append(ChatDisplayMessage(
                    id: event.message_id ?? UUID().uuidString,
                    role: "assistant",
                    content: finalContent,
                    timestamp: Date()
                ))
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
        guard let apiKey = env["API_SERVER_KEY"], !apiKey.isEmpty else { return nil }

        let baseURL: String
        if let explicitURL = env["HERMES_BASE_URL"], !explicitURL.isEmpty {
            baseURL = explicitURL
        } else {
            let host = env["API_SERVER_HOST"].flatMap { $0.isEmpty ? nil : $0 } ?? "100.x.x.x"
            let port = env["API_SERVER_PORT"].flatMap { $0.isEmpty ? nil : $0 } ?? "\(AppConfig.defaultPort)"
            let scheme = env["API_SERVER_SCHEME"].flatMap { $0.isEmpty ? nil : $0 } ?? "http"
            baseURL = "\(scheme)://\(host):\(port)"
        }

        return ConnectionConfig(baseURL: baseURL, apiKey: apiKey, label: env["HERMES_LABEL"] ?? "Hermes Debug")
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
            await refreshSessions()
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
