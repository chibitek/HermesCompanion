import SwiftUI
import PhotosUI

/// Manages voice timeouts using a flag-based approach.
/// Task.sleep cancellation is unreliable on iOS, so we use a simple
/// dictionary of timeout IDs with a "cancelled" flag. When the timeout
/// fires, it checks the flag before doing anything.
final class VoiceTimeoutManager {
    static let shared = VoiceTimeoutManager()
    private var timeouts: [UUID: Bool] = [:]
    private let lock = NSLock()

    func startTimeout(id: UUID, seconds: TimeInterval, action: @escaping () -> Void) {
        lock.lock()
        timeouts[id] = false
        lock.unlock()

        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let isCancelled = self.timeouts[id] ?? true
            self.lock.unlock()
            if isCancelled { return }
            DispatchQueue.main.async { action() }
        }
    }

    func cancelTimeout(id: UUID) {
        lock.lock()
        timeouts[id] = true
        lock.unlock()
    }
}

/// Main chat view with Liquid Glass design.
/// Uses .glassEffect() throughout for translucent, depth-heavy UI.
struct ChatView: View {
    @ObservedObject var store: AppStore
    @EnvironmentObject var appearance: AppearanceSettings
    @State private var inputText = ""
    @State private var showSessionPicker = false
    @State private var showSettings = false
    @State private var attachments: [AttachmentData] = []
    @State private var showPhotoPicker = false
    @State private var photoPickerItems: [PhotosPickerItem] = []
    @State private var showFilePicker = false
    @StateObject private var voiceConversation = VoiceConversationManager()
    @State private var showVoicePage = false

    var body: some View {
        NavigationStack {
            ZStack {
                // Theme background
                appearance.activeTheme.backgroundView
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    messageList

                    if store.isStreaming || !store.toolEvents.isEmpty {
                        toolEventsPanel
                    }

                    if let approval = store.pendingApproval {
                        GlassApprovalCard(approval: approval) { choice in
                            Task { await store.resolveApproval(choice: choice) }
                        }
                    }

                    GlassInputBar(
                        text: $inputText,
                        isStreaming: store.isStreaming,
                        onSend: sendMessage,
                        onStop: { store.stopStreaming() },
                        onCamera: { showPhotoPicker = true },
                        onFilePick: { showFilePicker = true },
                        attachments: attachments,
                        onRemoveAttachment: removeAttachment,
                        currentModel: store.effectiveCurrentModel,
                        availableModels: store.availableModels,
                        onSelectModel: { model in
                            store.selectPreferredModel(model)
                        },
                        onVoiceConversationTranscription: { transcription in
                            handleVoiceTranscription(transcription)
                        },
                        onSpeakResponse: { text in
                            voiceConversation.speakResponse(text)
                        },
                        onOpenVoicePage: {
                            showVoicePage = true
                        },
                        voiceConversation: voiceConversation
                    )
                }

                // Full-screen voice conversation page
                // (opened via .fullScreenCover below)
            }
            .navigationTitle(store.activeSession?.title ?? "New Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSessionPicker = true
                    } label: {
                        Image(systemName: "sidebar.left")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSessionPicker) {
                SessionPickerView(store: store)
                    .withActiveTheme(appearance)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(store: store)
                    .withActiveTheme(appearance)
            }
            .alert("Error", isPresented: .init(
                get: { store.error != nil },
                set: { if !$0 { store.clearError() } }
            )) {
                Button("OK") { store.clearError() }
            } message: {
                Text(store.error?.message ?? "")
            }
            .fullScreenCover(isPresented: $showVoicePage) {
                VoiceConversationPage(
                    voiceConversation: voiceConversation,
                    store: store,
                    currentModel: store.effectiveCurrentModel,
                    availableModels: store.availableModels,
                    onSelectModel: { model in
                        store.selectPreferredModel(model)
                    },
                    onVoiceTranscription: { transcription in
                        handleVoiceTranscription(transcription)
                    },
                    onClose: {
                        showVoicePage = false
                    }
                )
            }
        }
        // Keep the voice manager's default mode in sync with connection state.
        // When Hermes is connected, voice mode defaults to remote so the
        // conversation has the same memory as the typed chat.
        .onAppear {
            voiceConversation.isHermesConnected = store.isConnected
            voiceConversation.refreshDefaultMode()
        }
        .onChange(of: store.isConnected) { _, connected in
            voiceConversation.isHermesConnected = connected
            voiceConversation.refreshDefaultMode()
        }
        // Photo picker — triggered by the input bar attachment menu
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $photoPickerItems,
            maxSelectionCount: 10,
            matching: .images
        )
        .onChange(of: photoPickerItems) { _, newItems in
            Task {
                for item in newItems {
                    do {
                        if let data = try await item.loadTransferable(type: Data.self) {
                            // Convert to JPEG to avoid HEIC compatibility issues.
                            // PhotosPicker often returns HEIC on iOS, which many
                            // LLM vision APIs do not support.
                            let jpegData = convertToJPEG(data) ?? data
                            let fileName = "photo_\(UUID().uuidString.prefix(8)).jpg"
                            attachments.append(AttachmentData(data: jpegData, fileName: fileName, mimeType: "image/jpeg"))
                        }
                    } catch {
                        // Ignore individual failures, continue processing others
                    }
                }
                photoPickerItems = []
            }
        }
        // File picker sheet
        .sheet(isPresented: $showFilePicker) {
            FilePickerView { data, fileName, mimeType in
                attachments.append(AttachmentData(data: data, fileName: fileName, mimeType: mimeType))
            }
        }
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: GlassTheme.spacingM) {
                    if store.messages.isEmpty && store.streamingText.isEmpty {
                        emptyState
                    }

                    ForEach(store.messages) { msg in
                        GlassBubble(
                            content: msg.content,
                            isUser: msg.isUser,
                            fontScale: appearance.fontScaleDouble,
                            fixedFontSize: appearance.messageFontSizeDouble,
                            accentColor: appearance.accent,
                            compact: appearance.compactModeBool,
                            showTimestamp: appearance.showTimestampsBool,
                            images: msg.images
                        )
                            .id(msg.id)
                    }

                    if store.isStreaming && !store.streamingText.isEmpty {
                        GlassBubble(
                            content: store.streamingText,
                            isUser: false,
                            isStreaming: true,
                            fontScale: appearance.fontScaleDouble,
                            fixedFontSize: appearance.messageFontSizeDouble,
                            accentColor: appearance.accent,
                            compact: appearance.compactModeBool
                        )
                            .id("streaming")
                    }

                    if store.isStreaming && store.streamingText.isEmpty {
                        GlassThinkingIndicator()
                            .id("thinking")
                    }
                }
                .padding(.horizontal, GlassTheme.spacingL)
                .padding(.vertical, GlassTheme.spacingM)
            }
            .onAppear {
                // Scroll to the most recent message when the view first appears.
                // Use a delay because messages load asynchronously after session selection.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(.none) {
                        proxy.scrollTo(store.messages.last?.id ?? "streaming", anchor: .bottom)
                    }
                }
            }
            .onChange(of: store.messages.count) { oldCount, newCount in
                // Scroll to bottom whenever messages change.
                // When oldCount is 0 and newCount > 0, messages just loaded from a session.
                // When newCount > oldCount, a new message arrived.
                withAnimation(.smooth) {
                    proxy.scrollTo(store.messages.last?.id ?? "streaming", anchor: .bottom)
                }
            }
            .onChange(of: store.activeSession?.id) { _, _ in
                // When switching sessions, messages get cleared then reloaded async.
                // Scroll to bottom after a short delay to let messages populate.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(.none) {
                        proxy.scrollTo(store.messages.last?.id ?? "streaming", anchor: .bottom)
                    }
                }
            }
            .onChange(of: store.streamingText) { _, _ in
                withAnimation(.smooth) {
                    proxy.scrollTo("streaming", anchor: .bottom)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: GlassTheme.spacingXL) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
                .frame(width: 88, height: 88)

            VStack(spacing: GlassTheme.spacingS) {
                Text("Start a conversation")
                    .font(.title3)
                    .fontWeight(.medium)
                Text("Send a message to your Hermes agent.\nResponses stream in real time.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: GlassTheme.spacingM) {
                Button {
                    Task { await store.createSession(title: nil) }
                } label: {
                    Label("New Session", systemImage: "plus.circle.fill")
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(appearance.accent)
                        .padding(.horizontal, GlassTheme.spacingL)
                        .padding(.vertical, GlassTheme.spacingM)
                        .background(appearance.accent.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: GlassTheme.radiusM, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    showSessionPicker = true
                } label: {
                    Label("Browse Sessions", systemImage: "list.bullet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 50)
    }

    // MARK: - Tool Events Panel

    private var toolEventsPanel: some View {
        VStack(alignment: .leading, spacing: GlassTheme.spacingXS) {
            Text("Tool Activity")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, GlassTheme.spacingM)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: GlassTheme.spacingS) {
                    ForEach(store.toolEvents.suffix(12)) { evt in
                        GlassToolChip(event: evt)
                    }
                }
                .padding(.horizontal, GlassTheme.spacingM)
            }
        }
        .padding(.vertical, GlassTheme.spacingS)
    }

    // MARK: - Send

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        let images = attachments.filter { $0.isImage }.map { $0.data }
        let fileAttachments = attachments
        guard !text.isEmpty || !images.isEmpty || !fileAttachments.isEmpty else { return }
        inputText = ""
        attachments = []
        Task { await store.sendMessage(text, images: images, attachments: fileAttachments) }
    }

    @MainActor
    private func handleVoiceTranscription(_ transcription: String) {
        FileLogger.shared.log("ChatView: handleVoiceTranscription called: \(transcription)")
        let priorErrorID = store.error?.id
        voiceConversation.isThinking = true

        Task {
            // Hard timeout: if store.sendMessage doesn't return in 60 seconds,
            // bail out and surface an error so the UI doesn't freeze.
            // Uses a flag instead of Task cancellation because iOS's Task.sleep
            // doesn't reliably throw on cancellation in all cases.
            let voiceTimeoutID = UUID()
            VoiceTimeoutManager.shared.startTimeout(id: voiceTimeoutID, seconds: 60) {
                Task { @MainActor in
                    guard self.voiceConversation.isThinking else { return }
                    FileLogger.shared.log("ChatView: voice timeout fired (60s)")
                    self.voiceConversation.failRemoteTurn(message: "Hermes took too long to respond. Please try again.")
                }
            }

            // Monitor streaming text and start speaking as soon as we have
            // a complete first sentence. This cuts perceived latency dramatically
            // — the user hears the response start while the rest is still streaming.
            let monitorTask = Task { @MainActor in
                var lastSpokenText = ""
                var hasStartedSpeaking = false
                while !Task.isCancelled && self.voiceConversation.isThinking {
                    let current = self.store.streamingText
                    if !current.isEmpty && !hasStartedSpeaking {
                        // Check for a complete sentence (ends with ., !, or ?)
                        if current.contains(".") || current.contains("!") || current.contains("?") {
                            // Find the end of the first sentence
                            if let endIdx = current.firstIndex(where: { ".!?".contains($0) }) {
                                let firstSentence = String(current[...endIdx])
                                if firstSentence.split(separator: " ").count >= 2 {
                                    lastSpokenText = firstSentence
                                    hasStartedSpeaking = true
                                    FileLogger.shared.log("ChatView: starting early TTS with first sentence: \(firstSentence.prefix(80))")
                                    self.voiceConversation.startEarlySpeaking(text: firstSentence)
                                }
                            }
                        }
                    }
                    try? await Task.sleep(nanoseconds: 100_000_000) // 100ms poll
                }
            }

            let voiceMessage = "[voice] \(transcription)"
            let responseMessage = await store.sendMessage(voiceMessage, skipPostReload: true)
            monitorTask.cancel()
            VoiceTimeoutManager.shared.cancelTimeout(id: voiceTimeoutID)
            FileLogger.shared.log("ChatView: store.sendMessage returned \(String(describing: responseMessage?.content.prefix(80)))")

            guard let responseMessage = responseMessage else {
                FileLogger.shared.log("ChatView: no response message")
                if let error = store.error, error.id != priorErrorID {
                    voiceConversation.failRemoteTurn(message: error.message)
                } else {
                    voiceConversation.failRemoteTurn(message: "Hermes did not respond. Please try again.")
                }
                return
            }

            let response = responseMessage.content
            FileLogger.shared.log("ChatView: response content: \(response.prefix(120))")

            if !response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                FileLogger.shared.log("ChatView: calling completeRemoteTurn")
                voiceConversation.completeRemoteTurn(response: response)
            } else if let error = store.error, error.id != priorErrorID {
                FileLogger.shared.log("ChatView: error after empty response: \(error.message)")
                voiceConversation.failRemoteTurn(message: error.message)
            } else {
                FileLogger.shared.log("ChatView: empty response")
                voiceConversation.failRemoteTurn(message: "Hermes returned an empty response.")
            }
        }
    }

    // MARK: - Attachment Helpers

    private func removeAttachment(_ index: Int) {
        attachments.remove(at: index)
    }

    /// Convert image data to JPEG, resizing if needed to keep payload reasonable.
    /// Handles HEIC, PNG, GIF, etc. Returns nil if data cannot be decoded.
    private func convertToJPEG(_ data: Data, quality: CGFloat = 0.8, maxDimension: CGFloat = 1568) -> Data? {
        guard let image = UIImage(data: data) else { return nil }

        // Resize if the image is larger than maxDimension on any side.
        // 1568px is OpenAI's recommended max for vision (keeps base64 under ~1MB).
        let size = image.size
        let scale: CGFloat
        if max(size.width, size.height) > maxDimension {
            scale = maxDimension / max(size.width, size.height)
        } else {
            scale = 1.0
        }

        if scale < 1.0 {
            let newSize = CGSize(width: size.width * scale, height: size.height * scale)
            let renderer = UIGraphicsImageRenderer(size: newSize)
            let resized = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: newSize))
            }
            return resized.jpegData(compressionQuality: quality)
        }

        return image.jpegData(compressionQuality: quality)
    }
}
