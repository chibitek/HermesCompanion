import SwiftUI
import PhotosUI
import WidgetKit

/// Main chat view with Liquid Glass design.
/// Uses .glassEffect() throughout for translucent, depth-heavy UI.
struct ChatView: View {
    @ObservedObject var store: AppStore
    @EnvironmentObject var appearance: AppearanceSettings
    @Environment(\.scenePhase) private var scenePhase
    @State private var inputText = ""
    @State private var showSessionPicker = false
    @State private var showSettings = false
    @State private var attachments: [AttachmentData] = []
    @State private var showPhotoPicker = false
    @State private var photoPickerItems: [PhotosPickerItem] = []
    @State private var showFilePicker = false
    @State private var showCameraPicker = false
    @StateObject private var voiceConversation = VoiceConversationManager()
    @State private var showVoicePage = false
    @StateObject private var wakePhraseListener = WakePhraseListener()
    @AppStorage("hey_hermes_enabled", store: SharedDefaults.shared) private var heyHermesEnabled = true

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

                    GlassInputBar(
                        text: $inputText,
                        isStreaming: store.isStreaming,
                        onSend: sendMessage,
                        onQueue: queueMessage,
                        onStop: { store.stopStreaming() },
                        onCamera: { showPhotoPicker = true },
                        onFilePick: { showFilePicker = true },
                        onCameraCapture: { showCameraPicker = true },
                        onNewSession: {
                            inputText = ""
                            attachments = []
                            Task { await store.createSession(title: nil) }
                        },
                        attachments: attachments,
                        onRemoveAttachment: removeAttachment,
                        currentModel: store.effectiveCurrentModel,
                        availableModels: store.availableModels,
                        modelInfos: store.modelInfos,
                        favoriteModels: store.favoriteModels,
                        onSelectModel: { model, provider in
                            store.selectPreferredModel(model, provider: provider)
                        },
                        onToggleFavorite: { model in
                            _ = store.toggleFavorite(model)
                        },
                        availableSkills: store.skills,
                        onRefreshSkills: {
                            await store.refreshSkills()
                        },
                        onVoiceConversationTranscription: { transcription in
                            handleVoiceTranscription(transcription)
                        },
                        onOpenVoicePage: {
                            showVoicePage = true
                        },
                        onDictationStateChange: { isRecording in
                            if isRecording {
                                wakePhraseListener.pause()
                            } else if scenePhase == .active, !showVoicePage {
                                wakePhraseListener.resume()
                            }
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
                    onVoiceTranscription: { transcription in
                        handleVoiceTranscription(transcription)
                    },
                    onClose: {
                        showVoicePage = false
                    }
                )
            }
        }
        .onAppear {
            voiceConversation.onStopBackgroundAudio = { [weak store] in
                store?.stopSilentAudioForVoice()
            }
            wakePhraseListener.onWakePhrase = {
                guard !showVoicePage, !voiceConversation.isConversing else { return }
                showVoicePage = true
            }
            if heyHermesEnabled { wakePhraseListener.start() }
            Task { await store.refreshSkills() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openVoiceMode)) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                showVoicePage = true
            }
        }
        .onDisappear {
            wakePhraseListener.stop()
        }
        .onChange(of: heyHermesEnabled) { _, enabled in
            enabled ? wakePhraseListener.start() : wakePhraseListener.stop()
            ControlCenter.shared.reloadControls(ofKind: VoiceActivationControlConstants.kind)
        }
        .onChange(of: showVoicePage) { _, isPresented in
            if isPresented {
                wakePhraseListener.pause(deactivateAudioSession: false)
            } else {
                wakePhraseListener.resume()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                wakePhraseListener.resumeFromBackground()
                if SharedDefaults.shared.bool(forKey: "open_voice_page") {
                    SharedDefaults.shared.set(false, forKey: "open_voice_page")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showVoicePage = true
                    }
                }
            case .background:
                wakePhraseListener.startBackgroundMode()
            case .inactive:
                break
            @unknown default:
                wakePhraseListener.pause()
            }
        }
        .onChange(of: showSettings) { _, presented in
            presented ? wakePhraseListener.pause() : wakePhraseListener.resume()
        }
        .onChange(of: showSessionPicker) { _, presented in
            presented ? wakePhraseListener.pause() : wakePhraseListener.resume()
        }
        .onChange(of: showPhotoPicker) { _, presented in
            presented ? wakePhraseListener.pause() : wakePhraseListener.resume()
        }
        .onChange(of: showFilePicker) { _, presented in
            presented ? wakePhraseListener.pause() : wakePhraseListener.resume()
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
        // Camera picker sheet — take a photo directly
        .sheet(isPresented: $showCameraPicker) {
            CameraPickerView { data in
                let fileName = "camera_\(UUID().uuidString.prefix(8)).jpg"
                attachments.append(AttachmentData(data: data, fileName: fileName, mimeType: "image/jpeg"))
            }
        }
        .onChange(of: showCameraPicker) { _, presented in
            presented ? wakePhraseListener.pause() : wakePhraseListener.resume()
        }
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: appearance.activeTheme.spacingM) {
                    if store.messages.isEmpty && store.streamingText.isEmpty {
                        emptyState
                    }

                    ForEach(store.messages.filter { $0.shouldDisplay }) { msg in
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
                .padding(.horizontal, appearance.activeTheme.spacingL)
                .padding(.vertical, appearance.activeTheme.spacingM)
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
        VStack(spacing: appearance.activeTheme.spacingXL) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
                .frame(width: 88, height: 88)

            VStack(spacing: appearance.activeTheme.spacingS) {
                Text("Start a conversation")
                    .font(.title3)
                    .fontWeight(.medium)
                Text("Send a message to your Hermes agent.\nResponses stream in real time.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: appearance.activeTheme.spacingM) {
                Button {
                    Task { await store.createSession(title: nil) }
                } label: {
                    Label("New Session", systemImage: "plus.circle.fill")
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(appearance.accent)
                        .padding(.horizontal, appearance.activeTheme.spacingL)
                        .padding(.vertical, appearance.activeTheme.spacingM)
                        .background(appearance.accent.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: appearance.activeTheme.radiusM, style: .continuous))
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
        VStack(alignment: .leading, spacing: appearance.activeTheme.spacingXS) {
            Text("Tool Activity")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, appearance.activeTheme.spacingM)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: appearance.activeTheme.spacingS) {
                    ForEach(store.toolEvents.suffix(12)) { evt in
                        GlassToolChip(event: evt)
                    }
                }
                .padding(.horizontal, appearance.activeTheme.spacingM)
            }
        }
        .padding(.vertical, appearance.activeTheme.spacingS)
    }

    // MARK: - Send

    private func sendMessage() {
        let visibleText = inputText.trimmingCharacters(in: .whitespaces)
        let images = attachments.filter { $0.isImage }.map { $0.data }
        let fileAttachments = attachments
        guard !visibleText.isEmpty || !images.isEmpty || !fileAttachments.isEmpty else { return }
        let payload = SkillCommandLogic.messagePayload(for: visibleText)
        inputText = ""
        attachments = []
        Task { await store.sendMessage(payload, displayText: visibleText, images: images, attachments: fileAttachments) }
    }

    private func queueMessage() {
        let visibleText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !visibleText.isEmpty else { return }
        let payload = SkillCommandLogic.messagePayload(for: visibleText)
        inputText = ""
        store.queueMessage(payload, displayText: visibleText)
    }

    @MainActor
    private func handleVoiceTranscription(_ transcription: String) {
        FileLogger.shared.log("ChatView: handleVoiceTranscription called: \(transcription)")
        let priorErrorID = store.error?.id
        voiceConversation.isThinking = true

        Task {
            // Hard timeout: if store.sendMessage doesn't return in 20 seconds,
            // bail out and surface an error so the UI doesn't freeze.
            // StreamWatchdogManager is flag-based (DispatchQueue.asyncAfter)
            // because iOS's Task.sleep doesn't reliably fire when backgrounded.
            let voiceWatchdog = StreamWatchdogManager()
            voiceWatchdog.arm(after: 20) {
                Task { @MainActor in
                    guard self.voiceConversation.isThinking else { return }
                    FileLogger.shared.log("ChatView: voice timeout fired (20s)")
                    self.voiceConversation.failRemoteTurn(message: "Hermes took too long to respond. Please try again.")
                }
            }

            // Monitor streaming text and start speaking as soon as we have
            // enough text for natural speech. This cuts perceived latency dramatically
            // — the user hears the response start while the rest is still streaming.
            let monitorTask = Task { @MainActor in
                var hasStartedSpeaking = false
                while !Task.isCancelled && self.voiceConversation.isThinking {
                    let current = self.store.streamingText
                    if !current.isEmpty && !hasStartedSpeaking {
                        let wordCount = current.split(separator: " ").count
                        let hasSentenceEnd = current.contains(".") || current.contains("!") || current.contains("?")

                        if hasSentenceEnd {
                            if let endIdx = current.firstIndex(where: { ".!?".contains($0) }) {
                                let firstSentence = String(current[...endIdx])
                                if firstSentence.split(separator: " ").count >= 2 {
                                    hasStartedSpeaking = true
                                    FileLogger.shared.log("ChatView: starting early TTS with first sentence: \(firstSentence.prefix(80))")
                                    self.voiceConversation.startEarlySpeaking(text: firstSentence)
                                }
                            }
                        } else if wordCount >= 3 {
                            hasStartedSpeaking = true
                            FileLogger.shared.log("ChatView: starting early TTS with \(wordCount) words: \(current.prefix(80))")
                            self.voiceConversation.startEarlySpeaking(text: current)
                        }
                    }
                    try? await Task.sleep(nanoseconds: 20_000_000) // 20ms poll — faster response
                }
            }

            let voiceMessage = "[voice] \(transcription)"
            let responseMessage = await store.sendMessage(voiceMessage, skipPostReload: true)
            monitorTask.cancel()
            voiceWatchdog.cancel()
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
