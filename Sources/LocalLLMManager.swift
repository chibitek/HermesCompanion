import Foundation
import SwiftUI
import FoundationModels

/// Manager for on-device LLM via Apple Foundation Models framework (iOS 26+).
///
/// Uses `LanguageModelSession` from the FoundationModels framework to generate
/// responses entirely on-device without calling the Hermes gateway.
/// Falls back gracefully when the framework or model is unavailable.
@MainActor
final class LocalLLMManager: ObservableObject {

    // MARK: - Published State

    @Published var isAvailable = false
    @Published var isGenerating = false
    @Published var availabilityReason: String = ""

    // MARK: - Session (iOS 26+)

    /// The underlying LanguageModelSession. Stored as `Any?` so the file
    /// compiles on pre-iOS-26 SDKs without conditional imports.
    private var session: Any?

    /// Conversation transcript for display / debugging.
    private(set) var conversationHistory: [ChatMessage] = []

    private let systemInstructions = """
    You are Hermes, a helpful, concise voice assistant. \
    Respond naturally and conversationally. Keep responses brief (1-3 sentences) \
    unless the user asks for detail. You are running on-device with Apple \
    Foundation Models. Be friendly, direct, and helpful.
    """

    // MARK: - Chat Message (local)

    struct ChatMessage: Identifiable, Equatable {
        let id = UUID()
        let role: Role
        let content: String
        let timestamp: Date

        enum Role { case user, assistant }
    }

    // MARK: - Init

    init() {
        initializeSession()
    }

    // MARK: - Session Setup

    private func initializeSession() {
        guard #available(iOS 26.0, *) else {
            isAvailable = false
            availabilityReason = "Requires iOS 26 or later"
            return
        }

        checkAvailabilityAndCreateSession()
    }

    @available(iOS 26.0, *)
    private func checkAvailabilityAndCreateSession() {
        let model = SystemLanguageModel.default

        switch model.availability {
        case .available:
            // LanguageModelSession init is not throwing on iOS 26
            session = LanguageModelSession(
                model: model,
                instructions: systemInstructions
            )
            isAvailable = true
            availabilityReason = ""

        case .unavailable(let reason):
            isAvailable = false
            switch reason {
            case .deviceNotEligible:
                availabilityReason = "Device not eligible for Apple Intelligence"
            case .appleIntelligenceNotEnabled:
                availabilityReason = "Apple Intelligence is not enabled"
            case .modelNotReady:
                availabilityReason = "Model is downloading. Please wait."
            @unknown default:
                availabilityReason = "Model unavailable"
            }
        }
    }

    /// Re-check availability (e.g. after user enables Apple Intelligence)
    func refreshAvailability() {
        initializeSession()
    }

    // MARK: - Generate Response

    /// Generate a response from a user prompt using the on-device model.
    /// Maintains conversation context automatically via the session transcript.
    func generateResponse(to userPrompt: String) async -> String {
        guard isAvailable else {
            return "[Local model unavailable: \(availabilityReason)]"
        }

        guard #available(iOS 26.0, *), let session else {
            return "[Local model not initialized]"
        }

        isGenerating = true
        defer { isGenerating = false }

        // Record user message
        conversationHistory.append(ChatMessage(
            role: .user, content: userPrompt, timestamp: Date()
        ))

        do {
            let typedSession = session as! LanguageModelSession
            let response = try await typedSession.respond(to: userPrompt)
            let content = response.content

            // Record assistant response
            conversationHistory.append(ChatMessage(
                role: .assistant, content: content, timestamp: Date()
            ))

            // Prune history if it gets too large (keep last 20 messages)
            if conversationHistory.count > 20 {
                conversationHistory.removeFirst(conversationHistory.count - 20)
            }

            return content
        } catch {
            // On any error, try resetting the session for the next turn
            if #available(iOS 26.0, *) {
                let model = SystemLanguageModel.default
                if model.availability == .available {
                    self.session = LanguageModelSession(
                        model: model,
                        instructions: systemInstructions
                    )
                }
            }

            return "Sorry, I had trouble generating a response. Please try again."
        }
    }

    /// Reset conversation context (start fresh session)
    func resetConversation() {
        conversationHistory.removeAll()
        initializeSession()
    }
}
