import SwiftUI

// MARK: - Glass Input Bar (theme-aware, with attachments + voice)

struct GlassInputBar: View {
    @Binding var text: String
    let isStreaming: Bool
    let onSend: () -> Void
    let onQueue: () -> Void
    let onStop: () -> Void
    let onCamera: () -> Void
    let onFilePick: () -> Void
    let attachments: [AttachmentData]
    let onRemoveAttachment: (Int) -> Void
    var currentModel: String = ""
    var availableModels: [String] = []
    var favoriteModels: [String] = []
    var onSelectModel: ((String) -> Void)? = nil
    var availableSkills: [Skill] = []
    var onRefreshSkills: (() async -> Void)? = nil

    // Voice conversation callback - called when a transcription is ready in live modes (remote mode)
    var onVoiceConversationTranscription: ((String) -> Void)?
    // Callback to speak a response (set by ChatView when in live conversation mode)
    var onSpeakResponse: ((String) -> Void)?
    // Callback to open the full-screen cyberpunk voice page
    var onOpenVoicePage: (() -> Void)? = nil
    var onDictationStateChange: ((Bool) -> Void)? = nil

    @FocusState private var focused: Bool
    @State private var suppressNextSubmit = false
    @EnvironmentObject private var appearance: AppearanceSettings
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @StateObject private var voiceTranscriber = VoiceTranscriber()
    // External VoiceConversationManager passed from ChatView so overlay state stays in sync
    var voiceConversation: VoiceConversationManager
    @State private var showAttachmentMenu = false
    @State private var highlightedSkillID: String?
    @State private var didRequestSkillsForCurrentMenu = false

    private var theme: any HermesTheme { appearance.activeTheme }

    private var skillSuggestions: [Skill] {
        SkillCommandLogic.suggestions(for: text, skills: availableSkills)
    }

    private var showsSkillSuggestions: Bool {
        SkillCommandLogic.shouldShowSuggestions(for: text)
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsSkillSuggestions {
                skillSuggestionMenu
            }

            // Attachment thumbnail strip
            if !attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: theme.spacingS) {
                        ForEach(attachments.indices, id: \.self) { index in
                            attachmentThumbnail(index)
                        }
                    }
                    .padding(.horizontal, theme.spacingL)
                    .padding(.top, theme.spacingS)
                }
            }

            // Voice transcription indicator (voice-to-text mode)
            if voiceTranscriber.isRecording {
                HStack(spacing: theme.spacingS) {
                    // Pulsing red dot
                    Circle()
                        .fill(theme.danger)
                        .frame(width: 8, height: 8)
                        .opacity(0.8)
                        .modifier(PulsingAnimation())

                    Text(voiceTranscriber.transcribedText.isEmpty ? "Listening..." : voiceTranscriber.transcribedText)
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer()

                    Button {
                        // Insert transcribed text and stop
                        if !voiceTranscriber.transcribedText.isEmpty {
                            if text.isEmpty {
                                text = voiceTranscriber.transcribedText
                            } else {
                                text += " " + voiceTranscriber.transcribedText
                            }
                        }
                        voiceTranscriber.stopTranscription()
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(theme.accent)
                    }
                    .buttonStyle(.plain)

                    Button {
                        voiceTranscriber.stopTranscription()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, theme.spacingL)
                .padding(.vertical, theme.spacingS)
                .background(theme.danger.opacity(0.08))
            }

            // Live conversation indicator (compact bar — shown when overlay is visible)
            if voiceConversation.isConversing {
                HStack(spacing: theme.spacingS) {
                    // Pulsing indicator
                    if voiceConversation.isListening {
                        Circle()
                            .fill(theme.accent)
                            .frame(width: 8, height: 8)
                            .modifier(PulsingAnimation())
                    } else if voiceConversation.isSpeaking {
                        // Animated waveform when speaking
                        HStack(spacing: 3) {
                            ForEach(0..<4, id: \.self) { i in
                                Capsule()
                                    .fill(theme.accent)
                                    .frame(width: 3, height: 14)
                                    .modifier(SpeakingBarAnimation(delay: Double(i) * 0.15))
                            }
                        }
                    } else if voiceConversation.isThinking {
                        // Thinking indicator
                        HStack(spacing: 4) {
                            ForEach(0..<3, id: \.self) { i in
                                Circle()
                                    .fill(theme.accent.opacity(0.6))
                                    .frame(width: 5, height: 5)
                                    .modifier(PulsingAnimation())
                            }
                        }
                    } else {
                        Circle()
                            .fill(theme.textMuted)
                            .frame(width: 8, height: 8)
                    }

                    if voiceConversation.isThinking {
                        Text("Thinking...")
                            .font(.caption)
                            .foregroundStyle(theme.textSecondary)
                            .lineLimit(1)
                    } else if voiceConversation.isSpeaking {
                        Text(voiceConversation.spokenResponse.isEmpty ? "Speaking..." : String(voiceConversation.spokenResponse.prefix(50)))
                            .font(.caption)
                            .foregroundStyle(theme.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    } else if voiceConversation.isListening {
                        Text(voiceConversation.transcribedText.isEmpty ? "Listening..." : voiceConversation.transcribedText)
                            .font(.caption)
                            .foregroundStyle(theme.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    } else {
                        Text("Conversation active")
                            .font(.caption)
                            .foregroundStyle(theme.textSecondary)
                    }

                    Spacer()

                    Button {
                        voiceConversation.stopConversation()
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.title3)
                            .foregroundStyle(theme.danger)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, theme.spacingL)
                .padding(.vertical, theme.spacingS)
                .background(theme.accent.opacity(0.08))
            }

            // Claude-style two-line composer: text on top, controls/status below.
            VStack(alignment: .leading, spacing: 10) {
                TextField("Chat with Hermes", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .submitLabel(appearance.returnKeySends ? .send : .return)
                    .lineLimit(1...4)
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(theme.textPrimary)
                    .tint(theme.accent)
                    .onChange(of: text) { _, newValue in
                        // When return-sends is enabled, strip any newlines the user may have
                        // pasted or the keyboard inserted so Return stays a send action.
                        if appearance.returnKeySends && newValue.contains("\n") {
                            text = newValue.replacingOccurrences(of: "\n", with: " ")
                        }

                        if SkillCommandLogic.shouldShowSuggestions(for: newValue) {
                            highlightedSkillID = skillSuggestions.first?.id
                            if availableSkills.isEmpty && !didRequestSkillsForCurrentMenu {
                                didRequestSkillsForCurrentMenu = true
                                Task { await onRefreshSkills?() }
                            }
                        } else {
                            highlightedSkillID = nil
                            didRequestSkillsForCurrentMenu = false
                        }
                    }
                    .onSubmit {
                        guard !suppressNextSubmit else {
                            suppressNextSubmit = false
                            return
                        }
                        if appearance.returnKeySends {
                            if isStreaming { onQueue() } else { onSend() }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    Button {
                        showAttachmentMenu = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 21, weight: .regular))
                            .foregroundStyle(theme.textPrimary)
                            .frame(width: 44, height: 44)
                            .background(controlBackground)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .confirmationDialog("Attach", isPresented: $showAttachmentMenu, titleVisibility: .visible) {
                        Button("Photo Library") { onCamera() }
                        Button("Files") { onFilePick() }
                        Button("Cancel", role: .cancel) {}
                    }

                    if !currentModel.isEmpty {
                        Menu {
                            // Group favorites by provider
                            let favs = favoriteModels.filter { availableModels.contains($0) || $0 == currentModel }
                            let favProviders = Array(Set(favs.compactMap { providerOf($0) })).sorted()

                            if !favs.isEmpty {
                                ForEach(favProviders, id: \.self) { prov in
                                    Menu(prov) {
                                        let provFavs = favs.filter { providerOf($0) == prov }
                                        ForEach(provFavs, id: \.self) { model in
                                            Button {
                                                let generator = UIImpactFeedbackGenerator(style: .light)
                                                generator.impactOccurred()
                                                onSelectModel?(model)
                                            } label: {
                                                if model == currentModel {
                                                    Label(shortModelName(model), systemImage: "checkmark")
                                                } else {
                                                    Text(shortModelName(model))
                                                }
                                            }
                                        }
                                    }
                                }
                                Divider()
                            }

                            // "All Models" submenu grouped by provider
                            let allProviders = Array(Set(availableModels.compactMap { providerOf($0) })).sorted()
                            Menu("All Models") {
                                ForEach(allProviders, id: \.self) { prov in
                                    Menu(prov) {
                                        let provModels = availableModels.filter { providerOf($0) == prov }
                                        ForEach(provModels, id: \.self) { model in
                                            Button {
                                                let generator = UIImpactFeedbackGenerator(style: .light)
                                                generator.impactOccurred()
                                                onSelectModel?(model)
                                            } label: {
                                                if model == currentModel {
                                                    Label(shortModelName(model), systemImage: "checkmark")
                                                } else {
                                                    Text(shortModelName(model))
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                if let prov = providerOf(currentModel), !prov.isEmpty {
                                    Text(prov.capitalized)
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(theme.accent)
                                }
                                Text(shortModelName(currentModel))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(theme.textPrimary)
                            }
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .minimumScaleFactor(0.85)
                            .frame(height: 28)
                            .padding(.horizontal, 8)
                            .background(modelPillBackground)
                            .clipShape(Capsule())
                        }
                        .layoutPriority(1)
                        .buttonStyle(.plain)
                    }

                    Spacer(minLength: 0)

                    if !voiceTranscriber.isRecording && !voiceConversation.isConversing {
                        Button {
                            voiceTranscriber.startTranscription()
                        } label: {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 21, weight: .regular))
                                .foregroundStyle(theme.textPrimary)
                                .frame(width: 44, height: 44)
                                .background(controlBackground)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Voice to text")
                    }

                    Button {
                        switch ComposerSubmissionLogic.action(isStreaming: isStreaming, canSend: canSend) {
                        case .send:
                            onSend()
                        case .queue:
                            onQueue()
                        case .stop:
                            onStop()
                        case .voice:
                            if !voiceTranscriber.isRecording { onOpenVoicePage?() }
                        }
                    } label: {
                        Image(systemName: trailingActionIcon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(trailingActionForeground)
                            .frame(width: 44, height: 44)
                            .background(trailingActionBackground)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!isStreaming && !canSend && voiceTranscriber.isRecording)
                    .accessibilityLabel(trailingActionLabel)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 14)
            .onChange(of: focused) { _, isFocused in
                if isFocused {
                    suppressNextSubmit = true
                }
            }
            .background(AnyView(theme.glassCard(cornerRadius: theme.bubbleRadius)))
            .clipShape(RoundedRectangle(cornerRadius: theme.bubbleRadius, style: .continuous))
            .padding(.horizontal, theme.spacingL)
            .padding(.bottom, theme.spacingS)
        }
        .onAppear {
            Task { await voiceTranscriber.requestAuthorization() }
            Task { await voiceConversation.requestAuthorization() }
        }
        .onChange(of: voiceTranscriber.transcribedText) { _, newValue in
            if voiceTranscriber.isRecording && !newValue.isEmpty {
                text = newValue
            }
        }
        .onChange(of: voiceTranscriber.isRecording) { _, isRecording in
            onDictationStateChange?(isRecording)
        }
    }

    private var skillSuggestionMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(theme.accent)
                Text("Skills")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                Text("\(skillSuggestions.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(theme.textMuted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider().overlay(theme.cardBorder)

            if availableSkills.isEmpty {
                HStack(spacing: 10) {
                    ProgressView().tint(theme.accent)
                    Text("Loading available skills...")
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            } else if skillSuggestions.isEmpty {
                Text("No matching skills")
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 4) {
                        ForEach(skillSuggestions) { skill in
                            Button {
                                let generator = UIImpactFeedbackGenerator(style: .light)
                                generator.impactOccurred()
                                text = SkillCommandLogic.textBySelecting(skill, currentText: text)
                                highlightedSkillID = skill.id
                                focused = true
                            } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "book.closed.fill")
                                        .font(.caption)
                                        .foregroundStyle(theme.accent)
                                        .frame(width: 22, height: 22)
                                        .background(theme.accent.opacity(0.12))
                                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(skill.name)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(theme.textPrimary)
                                            .lineLimit(1)
                                        if let description = skill.description, !description.isEmpty {
                                            Text(description)
                                                .font(.caption)
                                                .foregroundStyle(theme.textSecondary)
                                                .lineLimit(2)
                                        }
                                    }

                                    Spacer(minLength: 4)

                                    if let category = skill.category, !category.isEmpty {
                                        Text(category)
                                            .font(.caption2)
                                            .foregroundStyle(theme.textMuted)
                                            .lineLimit(1)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(highlightedSkillID == skill.id ? theme.accent.opacity(0.12) : Color.clear)
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Use \(skill.name) skill")
                        }
                    }
                    .padding(6)
                }
                .frame(height: verticalSizeClass == .compact ? 220 : 420)
            }
        }
        .background(AnyView(theme.glassCard(cornerRadius: 16)))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, theme.spacingL)
        .padding(.bottom, 6)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.easeOut(duration: 0.16), value: showsSkillSuggestions)
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespaces).isEmpty || !attachments.isEmpty
    }

    private var controlBackground: some View {
        Circle()
            .fill(theme.bgCard)
            .overlay(Circle().stroke(theme.cardBorder, lineWidth: theme.cardBorderWidth))
    }

    private var modelPillBackground: some View {
        Capsule()
            .fill(theme.bgCard)
            .overlay(Capsule().stroke(theme.cardBorder, lineWidth: theme.cardBorderWidth))
    }

    private var trailingActionIcon: String {
        if isStreaming && canSend { return "arrow.up" }
        if isStreaming { return "stop.fill" }
        if canSend { return "arrow.up" }
        // Use a more distinctive icon for voice conversation mode
        return "waveform.badge.mic"
    }

    private var trailingActionForeground: Color {
        if isStreaming && canSend { return .white }
        if isStreaming { return theme.danger }
        if canSend { return .white }
        // For voice conversation mode, use accent color instead of white for better visibility
        return theme.accent
    }

    private var trailingActionBackground: some View {
        let shape = Circle()
        if isStreaming && canSend {
            return AnyView(shape.fill(theme.accent))
        }
        if isStreaming {
            return AnyView(
                shape
                    .fill(theme.danger.opacity(0.12))
                    .overlay(shape.stroke(theme.danger, lineWidth: 1))
            )
        }
        if canSend {
            return AnyView(shape.fill(theme.accent))
        }
        return AnyView(
            shape
                .fill(theme.accent.opacity(0.12))
                .overlay(shape.stroke(theme.accent.opacity(0.3), lineWidth: 1))
        )
    }

    private var trailingActionLabel: String {
        if isStreaming && canSend { return "Queue message" }
        if isStreaming { return "Stop" }
        if canSend { return "Send message" }
        return "Open voice conversation"
    }

    private func shortModelName(_ model: String) -> String {
        // Shorten common model names for the pill
        if model.contains("/") {
            return model.split(separator: "/").last.map { String($0) } ?? model
        }
        return model
    }

    private func providerOf(_ model: String) -> String? {
        guard let slash = model.firstIndex(of: "/"), slash > model.startIndex else { return nil }
        return String(model[..<slash])
    }

    private func attachmentThumbnail(_ index: Int) -> some View {
        let attachment = attachments[index]
        return ZStack(alignment: .topTrailing) {
            // Thumbnail
            if let image = UIImage(data: attachment.data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: theme.radiusS, style: .continuous))
            } else {
                // File icon for non-image attachments
                RoundedRectangle(cornerRadius: theme.radiusS, style: .continuous)
                    .fill(theme.bgCard)
                    .frame(width: 56, height: 56)
                    .overlay(
                        VStack(spacing: 4) {
                            Image(systemName: attachment.fileIcon)
                                .font(.title3)
                                .foregroundStyle(theme.textSecondary)
                            Text(attachment.fileExtension.uppercased())
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(theme.textSecondary)
                        }
                    )
            }

            // Remove button
            Button {
                onRemoveAttachment(index)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .background(Circle().fill(.black.opacity(0.5)))
            }
            .buttonStyle(.plain)
            .offset(x: 6, y: -6)
        }
    }
}
