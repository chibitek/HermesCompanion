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
    @Published var error: AppError?
    @Published var isLoading = false
    @Published var pendingApproval: PendingApproval?

    // MARK: - Private

    private var apiClient: HermesAPIClient?
    private var streamTask: Task<Void, Never>?

    // MARK: - Init

    init() {
        connectionConfig = KeychainManager.shared.loadActive()
    }

    // MARK: - Connection

    var isConnected: Bool { connectionConfig != nil }

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

    func connect(config: ConnectionConfig) async -> Bool {
        self.apiClient = HermesAPIClient(config: config)
        do {
            let health = try await apiClient!.checkHealth()
            guard health.status == "ok" else {
                self.error = AppError(message: "Server returned status: \(health.status)")
                return false
            }
            // Save to keychain
            try? KeychainManager.shared.save(config)
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

    // MARK: - Capabilities

    func refreshCapabilities() async {
        guard let client = apiClient else { return }
        do {
            self.capabilities = try await client.getCapabilities()
        } catch {
            // Non-fatal — capabilities are optional
        }
    }

    // MARK: - Sessions

    func refreshSessions() async {
        guard let client = apiClient else { return }
        do {
            self.sessions = try await client.listSessions()
        } catch {
            self.error = AppError(message: "Failed to load sessions: \(error.localizedDescription)")
        }
    }

    func createSession(title: String? = nil) async {
        guard let client = apiClient else { return }
        do {
            let session = try await client.createSession(title: title)
            self.sessions.insert(session, at: 0)
            await selectSession(session)
        } catch {
            self.error = AppError(message: "Failed to create session: \(error.localizedDescription)")
        }
    }

    func selectSession(_ session: HermesSession) async {
        guard let client = apiClient else { return }
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
        guard let client = apiClient else { return }
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

    // MARK: - Skills

    func refreshSkills() async {
        guard let client = apiClient else { return }
        do {
            self.skills = try await client.listSkills()
        } catch {
            // Non-fatal
        }
    }

    // MARK: - Chat (streaming)

    func sendMessage(_ text: String, images: [Data] = []) async {
        guard let client = apiClient else {
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
        let messagePayload: String
        if images.isEmpty {
            messagePayload = text
        } else {
            // For multimodal, we send text with embedded data URLs
            // The Hermes API accepts image_url parts in the content array
            // But the session chat endpoint takes a string message, so we
            // use the chat/completions endpoint for multimodal instead.
            // For now, send text only through session chat.
            // TODO: Use /v1/chat/completions for multimodal when images are present
            messagePayload = text
        }

        // Prepare streaming state
        isStreaming = true
        streamingText = ""
        toolEvents = []
        pendingApproval = nil

        streamTask = Task { [weak self] in
            guard let self = self else { return }
            do {
                let stream = try await client.streamChat(
                    sessionId: session.id,
                    message: messagePayload
                )

                for try await event in stream {
                    if Task.isCancelled { break }
                    await self.handleSSEEvent(event)
                }
            } catch let e as APIError {
                self.error = AppError(message: e.errorDescription ?? "Stream failed")
            } catch {
                self.error = AppError(message: "Stream failed: \(error.localizedDescription)")
            }
            self.isStreaming = false
        }
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
            if let preview = event.preview, !preview.isEmpty {
                toolEvents.append(ToolEvent(
                    id: UUID().uuidString,
                    type: .progress,
                    toolName: event.toolName ?? "thinking",
                    detail: preview
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
        guard let client = apiClient, let approval = pendingApproval else { return }
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