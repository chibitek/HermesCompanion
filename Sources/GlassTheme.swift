import SwiftUI

/// Legacy compatibility layer. Components now read from the active
/// HermesTheme via @EnvironmentObject. These statics remain for any
/// code that hasn't been migrated yet and always return the Hermes
/// (default) theme values.
enum GlassTheme {
    static let accent = Color(red: 0.176, green: 0.831, blue: 0.749)
    static let accentSecondary = Color(red: 0.0, green: 0.702, blue: 0.596)
    static let danger = Color(red: 0.811, green: 0.271, blue: 0.125)
    static let warning = Color(red: 0.961, green: 0.620, blue: 0.043)

    static let spacingXS: CGFloat = 4
    static let spacingS: CGFloat = 8
    static let spacingM: CGFloat = 12
    static let spacingL: CGFloat = 16
    static let spacingXL: CGFloat = 24

    static let radiusS: CGFloat = 10
    static let radiusM: CGFloat = 16
    static let radiusL: CGFloat = 22
    static let radiusXL: CGFloat = 28

    static let bubbleMaxWidthRatio: CGFloat = 0.82
}

// MARK: - Theme Environment Key

/// Allows passing the active theme through the SwiftUI environment.
private struct ActiveThemeKey: EnvironmentKey {
    static let defaultValue: any HermesTheme = HermesDefaultTheme()
}

extension EnvironmentValues {
    var activeTheme: any HermesTheme {
        get { self[ActiveThemeKey.self] }
        set { self[ActiveThemeKey.self] = newValue }
    }
}

// MARK: - Glass Message Bubble (theme-aware)

struct GlassBubble: View {
    let content: String
    let isUser: Bool
    var isStreaming: Bool = false
    var fontScale: Double = 1.0
    var fixedFontSize: Double = 0  // 0 = use system Dynamic Type
    var accentColor: Color = GlassTheme.accent
    var compact: Bool = false
    var showTimestamp: Bool = false
    var images: [Data] = []

    @EnvironmentObject private var appearance: AppearanceSettings

    private var theme: any HermesTheme { appearance.activeTheme }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 40) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: theme.spacingXS) {
                // Render attached images
                if !images.isEmpty {
                    LazyVStack(alignment: isUser ? .trailing : .leading, spacing: theme.spacingS) {
                        ForEach(images.indices, id: \.self) { i in
                            if let uiImage = UIImage(data: images[i]) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: 200, maxHeight: 200)
                                    .clipShape(RoundedRectangle(cornerRadius: theme.radiusS, style: .continuous))
                            }
                        }
                    }
                }

                if !content.isEmpty {
                    Text(renderedContent)
                        .font(messageFont)
                        .textSelection(.enabled)
                        .foregroundStyle(isUser ? .white : .primary)
                }

                if showTimestamp {
                    Text(Date(), style: .time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, compact ? 12 : theme.spacingL)
            .padding(.vertical, compact ? 8 : theme.spacingM)
            .frame(maxWidth: screenBoundsWidth * GlassTheme.bubbleMaxWidthRatio,
                   alignment: isUser ? .trailing : .leading)
            .background(bubbleBackground)
            .overlay(alignment: .leading) {
                if !isUser && theme.assistantBubbleBorderWidth > 0 {
                    // Terminal-style left border for assistant bubbles
                    Rectangle()
                        .fill(theme.assistantBubbleBorder)
                        .frame(width: theme.assistantBubbleBorderWidth)
                        .padding(.vertical, 2)
                }
            }
            .accessibilityLabel(isUser ? "Your message: \(content)" : "Hermes response: \(content)")
            .accessibilityHint(isUser ? "" : "Assistant reply")
            .clipShape(RoundedRectangle(cornerRadius: compact ? 14 : theme.bubbleRadius, style: .continuous))
            .if(isUser) { view in
                if theme.usesGlass {
                    view.glassEffect(.regular.tint(accentColor.opacity(0.35)))
                } else {
                    view.overlay(
                        RoundedRectangle(cornerRadius: compact ? 14 : theme.bubbleRadius, style: .continuous)
                            .stroke(accentColor.opacity(0.4), lineWidth: 1)
                    )
                }
            }
            .if(!isUser && theme.usesGlass) { view in
                view.glassEffect(.regular)
            }
            .overlay(alignment: .bottomTrailing) {
                if isStreaming {
                    BlinkingCursor()
                        .padding(.trailing, 10)
                        .padding(.bottom, 6)
                }
            }

            if !isUser { Spacer(minLength: 40) }
        }
    }

    private var messageFont: Font {
        if fixedFontSize > 0 {
            return .system(size: fixedFontSize, design: isUser ? .default : monospacedDesign)
        }
        return isUser ? theme.userMessageFont : theme.assistantMessageFont
    }

    private var renderedContent: AttributedString {
        guard !isUser,
              let attributed = try? AttributedString(
                markdown: content,
                options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
              )
        else {
            return AttributedString(content)
        }
        return attributed
    }

    private var monospacedDesign: Font.Design {
        // Use monospaced design when the theme specifies it
        if theme.assistantMessageFont == .system(.body, design: .monospaced) {
            return .monospaced
        }
        return .default
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        if isUser {
            if theme.usesGlass {
                accentColor.opacity(0.25)
            } else {
                theme.userBubbleBackground
            }
        } else {
            theme.assistantBubbleBackground
        }
    }

    /// Screen width from the current window scene (replaces deprecated UIScreen.main)
    private var screenBoundsWidth: CGFloat {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        return scene?.screen.bounds.width ?? 390
    }
}

// MARK: - Blinking Cursor (theme-aware)

struct BlinkingCursor: View {
    @State private var visible = true
    @EnvironmentObject private var appearance: AppearanceSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var theme: any HermesTheme { appearance.activeTheme }

    var body: some View {
        Text(theme.cursorCharacter)
            .font(.caption2)
            .foregroundStyle(theme.cursorColor)
            .opacity(visible ? 1 : 0)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.5).repeatForever(), value: visible)
            .onAppear { if !reduceMotion { visible.toggle() } }
    }
}

// MARK: - Glass Tool Chip (theme-aware)

struct GlassToolChip: View {
    let event: ToolEvent
    @EnvironmentObject private var appearance: AppearanceSettings

    private var theme: any HermesTheme { appearance.activeTheme }

    var body: some View {
        HStack(spacing: theme.spacingXS) {
            Image(systemName: icon)
                .font(.caption)
            Text(event.toolName)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, theme.spacingM)
        .padding(.vertical, theme.spacingS)
        .if(theme.toolChipsUseGlass) { view in
            view.glassEffect(.regular.tint(color.opacity(0.2)))
        }
        .if(!theme.toolChipsUseGlass) { view in
            view
                .background(theme.toolChipBackground)
                .overlay(
                    Capsule()
                        .stroke(theme.toolChipBorder, lineWidth: 1)
                )
        }
        .clipShape(Capsule())
    }

    private var icon: String {
        switch event.type {
        case .progress: return "brain"
        case .started: return "play.circle"
        case .completed: return "checkmark.circle"
        case .failed: return "xmark.circle"
        }
    }

    private var color: Color {
        switch event.type {
        case .progress: return .purple
        case .started: return .blue
        case .completed: return .green
        case .failed: return theme.danger
        }
    }
}

// MARK: - Glass Thinking Indicator (theme-aware)

struct GlassThinkingIndicator: View {
    @State private var animate = false
    @EnvironmentObject private var appearance: AppearanceSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var theme: any HermesTheme { appearance.activeTheme }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(theme.accent.opacity(0.6))
                    .frame(width: 7, height: 7)
                    .scaleEffect(reduceMotion ? 0.8 : (animate ? 1.0 : 0.4))
                    .opacity(reduceMotion ? 0.6 : (animate ? 1.0 : 0.3))
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 0.7)
                            .repeatForever()
                            .delay(Double(i) * 0.25),
                        value: animate
                    )
            }
        }
        .padding(.horizontal, theme.spacingL)
        .padding(.vertical, theme.spacingM)
        .if(theme.usesGlass) { view in
            view.background(Color(.tertiarySystemFill))
        }
        .if(!theme.usesGlass) { view in
            view.background(Color(.tertiarySystemFill))
        }
        .clipShape(RoundedRectangle(cornerRadius: theme.bubbleRadius, style: .continuous))
        .onAppear { if !reduceMotion { animate = true } }
    }
}

// MARK: - Glass Approval Card (theme-aware)

struct GlassApprovalCard: View {
    let approval: PendingApproval
    let onResolve: (String) -> Void
    @EnvironmentObject private var appearance: AppearanceSettings

    private var theme: any HermesTheme { appearance.activeTheme }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacingM) {
            HStack(spacing: theme.spacingS) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.title3)
                    .foregroundStyle(theme.warning)
                Text("Approval Required")
                    .font(.headline)
            }

            Text(approval.command)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .padding(theme.spacingM)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.warning.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: theme.radiusS, style: .continuous))

            HStack(spacing: theme.spacingM) {
                GlassButton("Allow Once", tint: .green) { onResolve("once") }
                GlassButton("Allow Session", tint: .blue) { onResolve("session") }
                GlassButton("Deny", tint: theme.danger) { onResolve("deny") }
            }
        }
        .padding(theme.spacingL)
        .background(Color(.tertiarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: theme.radiusXL, style: .continuous))
        .padding(.horizontal, theme.spacingL)
        .padding(.bottom, theme.spacingS)
    }
}

// MARK: - Glass Button (theme-aware)

struct GlassButton: View {
    let label: String
    let tint: Color
    let action: () -> Void
    @EnvironmentObject private var appearance: AppearanceSettings

    private var theme: any HermesTheme { appearance.activeTheme }

    init(_ label: String, tint: Color = .accentColor, action: @escaping () -> Void) {
        self.label = label
        self.tint = tint
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline)
                .fontWeight(.medium)
                .padding(.horizontal, theme.spacingM)
                .padding(.vertical, theme.spacingS)
                .if(theme.usesGlass) { view in
                    view.background(tint.opacity(0.12))
                }
                .if(!theme.usesGlass) { view in
                    view
                        .background(tint.opacity(0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: theme.controlRadius, style: .continuous)
                                .stroke(tint.opacity(0.3), lineWidth: 1)
                        )
                }
                .clipShape(RoundedRectangle(cornerRadius: theme.controlRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Glass Input Bar (theme-aware, with attachments + voice)

/// Voice input mode: voice-to-text (transcribe) or live conversation (TTS)
enum VoiceInputMode: String, CaseIterable {
    case voiceToText = "Voice-to-Text"
    case liveConversation = "Live Conversation"

    var icon: String {
        switch self {
        case .voiceToText: return "waveform"
        case .liveConversation: return "waveform.badge.mic"
        }
    }

    var toggled: VoiceInputMode {
        switch self {
        case .voiceToText: return .liveConversation
        case .liveConversation: return .voiceToText
        }
    }
}

struct GlassInputBar: View {
    @Binding var text: String
    let isStreaming: Bool
    let onSend: () -> Void
    let onStop: () -> Void
    let onCamera: () -> Void
    let onFilePick: () -> Void
    let attachments: [AttachmentData]
    let onRemoveAttachment: (Int) -> Void
    var currentModel: String = ""
    var availableModels: [String] = []
    var onSelectModel: ((String) -> Void)? = nil

    // Voice conversation callback - called when a transcription is ready in live modes (remote mode)
    var onVoiceConversationTranscription: ((String) -> Void)?
    // Callback to speak a response (set by ChatView when in live conversation mode)
    var onSpeakResponse: ((String) -> Void)?
    // Callback to open the full-screen cyberpunk voice page
    var onOpenVoicePage: (() -> Void)? = nil

    @FocusState private var focused: Bool
    @EnvironmentObject private var appearance: AppearanceSettings
    @StateObject private var voiceTranscriber = VoiceTranscriber()
    // External VoiceConversationManager passed from ChatView so overlay state stays in sync
    var voiceConversation: VoiceConversationManager
    @State private var showAttachmentMenu = false
    @State private var voiceMode: VoiceInputMode = .voiceToText
    @State private var showVoiceHint = true
    @State private var showModelPicker = false

    private var theme: any HermesTheme { appearance.activeTheme }

    var body: some View {
        VStack(spacing: 0) {
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
                        .foregroundStyle(.secondary)
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
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, theme.spacingL)
                .padding(.vertical, theme.spacingS)
                .background(theme.danger.opacity(0.06))
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
                            .fill(.secondary)
                            .frame(width: 8, height: 8)
                    }

                    if voiceConversation.isThinking {
                        Text("Thinking...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else if voiceConversation.isSpeaking {
                        Text(voiceConversation.spokenResponse.isEmpty ? "Speaking..." : String(voiceConversation.spokenResponse.prefix(50)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    } else if voiceConversation.isListening {
                        Text(voiceConversation.transcribedText.isEmpty ? "Listening..." : voiceConversation.transcribedText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    } else {
                        Text("Conversation active · \(voiceConversation.conversationMode.rawValue)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
            VStack(alignment: .leading, spacing: 12) {
                TextField("Chat with Hermes", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .submitLabel(.send)
                    .lineLimit(1...4)
                    .font(.system(size: 22, weight: .regular))
                    .onSubmit(onSend)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    Button {
                        showAttachmentMenu = true
                    } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 24, weight: .regular))
                                .foregroundStyle(.primary)
                            .frame(width: 48, height: 48)
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
                        Button {
                            showModelPicker = true
                        } label: {
                            Text(shortModelName(currentModel))
                                .font(.system(size: 15, weight: .medium))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundStyle(.primary)
                                .minimumScaleFactor(0.85)
                                .frame(width: 116, height: 48)
                                .padding(.horizontal, 12)
                                .background(controlBackground)
                                .clipShape(Capsule())
                        }
                        .layoutPriority(1)
                        .buttonStyle(.plain)
                        .confirmationDialog("Select Model", isPresented: $showModelPicker, titleVisibility: .visible) {
                            ForEach(availableModels, id: \.self) { model in
                                Button(model) {
                                    onSelectModel?(model)
                                }
                            }
                            Button("Cancel", role: .cancel) {}
                        }
                    }

                    Spacer(minLength: 0)

                    if !voiceTranscriber.isRecording && !voiceConversation.isConversing {
                        Button {
                            voiceTranscriber.startTranscription()
                        } label: {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 24, weight: .regular))
                                .foregroundStyle(.primary)
                                .frame(width: 48, height: 48)
                                .background(controlBackground)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Voice to text")
                    }

                    Button {
                        if isStreaming {
                            onStop()
                        } else if canSend {
                            onSend()
                        } else if !voiceTranscriber.isRecording {
                            onOpenVoicePage?()
                        }
                    } label: {
                        Image(systemName: trailingActionIcon)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(trailingActionForeground)
                            .frame(width: 48, height: 48)
                            .background(trailingActionBackground)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!isStreaming && !canSend && voiceTranscriber.isRecording)
                    .accessibilityLabel(trailingActionLabel)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 18)
            .if(theme.usesGlass) { view in
                view.background(.thinMaterial)
            }
            .if(!theme.usesGlass) { view in
                view
                    .background(Color(.tertiarySystemFill))
                    .overlay(
                        RoundedRectangle(cornerRadius: theme.bubbleRadius, style: .continuous)
                            .stroke(theme.accent.opacity(0.15), lineWidth: 1)
                    )
            }
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
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespaces).isEmpty || !attachments.isEmpty
    }

    private var controlBackground: Color {
        Color(.tertiarySystemFill)
    }

    private var trailingActionIcon: String {
        if isStreaming { return "stop.fill" }
        if canSend { return "arrow.up" }
        return "waveform"
    }

    private var trailingActionForeground: Color {
        if isStreaming { return theme.danger }
        return .white
    }

    private var trailingActionBackground: Color {
        if isStreaming { return Color(.tertiarySystemFill) }
        if canSend { return theme.accent }
        return .primary
    }

    private var trailingActionLabel: String {
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

    // MARK: - Mic Button (tap = voice-to-text, long-press = 2-way conversation)

    private var micButton: some View {
        VStack(spacing: 2) {
            Button {
                // Tap = voice-to-text (dictation)
                voiceTranscriber.startTranscription()
            } label: {
                Image(systemName: "mic.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .contextMenu {
                ControlGroup {
                    Button {
                        voiceTranscriber.startTranscription()
                    } label: {
                        Label("Voice-to-Text", systemImage: "text.mic.fill")
                    }
                    Button {
                        onOpenVoicePage?()
                    } label: {
                        Label("2-Way Voice", systemImage: "waveform.badge.mic")
                    }
                }
                .controlGroupStyle(.compactMenu)
            }
            .accessibilityLabel("Microphone")
            .accessibilityHint("Tap for voice-to-text. Long-press for 2-way voice conversation.")
            .onLongPressGesture(minimumDuration: 0.5) {
                // Long-press = open full-screen voice conversation page
                onOpenVoicePage?()
            }
        }
        .overlay(alignment: .top) {
            // Hint tooltip that appears briefly
            if showVoiceHint {
                Text("Hold for 2-way voice")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .offset(y: -28)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .task {
                        try? await Task.sleep(for: .seconds(4))
                        withAnimation { showVoiceHint = false }
                    }
            }
        }
    }

    private func startVoiceConversation() {
        // This is now triggered from the full-screen VoiceConversationPage
        // but we keep the method for any external callers
        voiceConversation.startConversation(
            onTranscription: { transcription in
                onVoiceConversationTranscription?(transcription)
            },
            onLocalResponse: { _ in
                // Response is already spoken by the VoiceConversationManager
            }
        )
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
                    .fill(Color(.tertiarySystemFill))
                    .frame(width: 56, height: 56)
                    .overlay(
                        VStack(spacing: 4) {
                            Image(systemName: attachment.fileIcon)
                                .font(.title3)
                                .foregroundStyle(.secondary)
                            Text(attachment.fileExtension.uppercased())
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.secondary)
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

// MARK: - Voice Conversation Overlay (Liquid Glass, full-screen)

/// A beautiful full-screen voice conversation overlay with animated waveform.
/// Shows listening/speaking/thinking states with Liquid Glass aesthetic.
/// Tap anywhere or press the stop button to exit.
struct VoiceConversationOverlay: View {
    @ObservedObject var voiceConversation: VoiceConversationManager
    @EnvironmentObject private var appearance: AppearanceSettings

    private var theme: any HermesTheme { appearance.activeTheme }

    var body: some View {
        ZStack {
            // Semi-transparent backdrop
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    voiceConversation.stopConversation()
                }

            // Main content
            VStack(spacing: 32) {
                Spacer()

                // Mode indicator
                HStack(spacing: 8) {
                    Image(systemName: voiceConversation.conversationMode.icon)
                        .font(.subheadline)
                    Text(voiceConversation.conversationMode.rawValue)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    if voiceConversation.conversationMode == .local && !voiceConversation.localLLM.isAvailable {
                        Text("(unavailable)")
                            .font(.caption)
                            .foregroundStyle(theme.warning)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())

                // State label
                Text(stateLabel)
                    .font(.title3)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)

                // Waveform animation
                waveformView
                    .frame(height: 100)

                // Live transcript / response preview
                VStack(spacing: 8) {
                    if !voiceConversation.transcribedText.isEmpty && voiceConversation.isListening {
                        Text(voiceConversation.transcribedText)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }

                    if !voiceConversation.spokenResponse.isEmpty && voiceConversation.isSpeaking {
                        Text(voiceConversation.spokenResponse)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .lineLimit(4)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                }

                Spacer()

                // Mode toggle + stop button
                VStack(spacing: 16) {
                    // Mode toggle
                    Button {
                        voiceConversation.toggleMode()
                    } label: {
                        HStack(spacing: 6) {
                            ForEach(ConversationMode.allCases, id: \.self) { mode in
                                HStack(spacing: 4) {
                                    Image(systemName: mode.icon)
                                        .font(.caption)
                                    Text(mode.rawValue)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .foregroundStyle(voiceConversation.conversationMode == mode ? .white : .secondary)
                                .background {
                                    if voiceConversation.conversationMode == mode {
                                        Capsule().fill(theme.accent)
                                    }
                                }
                            }
                        }
                        .padding(3)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(voiceConversation.isSpeaking || voiceConversation.isThinking)

                    // Stop button
                    Button {
                        voiceConversation.stopConversation()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(theme.danger)
                                .frame(width: 64, height: 64)
                                .clipShape(Circle())

                            Image(systemName: "stop.fill")
                                .font(.title2)
                                .foregroundStyle(.white)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 60)
            }
        }
        .animation(.smooth, value: voiceConversation.isListening)
        .animation(.smooth, value: voiceConversation.isSpeaking)
        .animation(.smooth, value: voiceConversation.isThinking)
    }

    // MARK: - State Label

    private var stateLabel: String {
        if voiceConversation.isThinking {
            return "Thinking..."
        } else if voiceConversation.isSpeaking {
            return "Speaking..."
        } else if voiceConversation.isListening {
            return "Listening..."
        } else if voiceConversation.isConversing {
            return "Starting..."
        } else {
            return "Tap to stop"
        }
    }

    // MARK: - Waveform

    @ViewBuilder
    private var waveformView: some View {
        let barCount = 7
        HStack(spacing: 6) {
            ForEach(0..<barCount, id: \.self) { i in
                WaveformBar(
                    index: i,
                    total: barCount,
                    isActive: voiceConversation.isListening || voiceConversation.isSpeaking || voiceConversation.isThinking,
                    isListening: voiceConversation.isListening,
                    isSpeaking: voiceConversation.isSpeaking,
                    isThinking: voiceConversation.isThinking,
                    accentColor: theme.accent
                )
            }
        }
    }
}

/// Individual waveform bar with animated amplitude.
struct WaveformBar: View {
    let index: Int
    let total: Int
    let isActive: Bool
    let isListening: Bool
    let isSpeaking: Bool
    let isThinking: Bool
    let accentColor: Color

    @State private var amplitude: CGFloat = 0.3

    var body: some View {
        Capsule()
            .fill(accentColor.gradient)
            .frame(width: 6, height: maxHeight)
            .scaleEffect(y: isActive ? amplitude : 0.15)
            .animation(
                isActive ? animation : .smooth(duration: 0.3),
                value: amplitude
            )
            .onAppear {
                if isActive {
                    animateBar()
                }
            }
            .onChange(of: isActive) { _, active in
                if active {
                    animateBar()
                } else {
                    amplitude = 0.15
                }
            }
    }

    private var maxHeight: CGFloat {
        // Vary base height slightly per bar for organic look
        40 + CGFloat(index % 3) * 15
    }

    private var animation: Animation {
        let duration: Double
        let autoReverse: Bool

        if isSpeaking {
            duration = 0.25 + Double(index % 3) * 0.08
            autoReverse = true
        } else if isThinking {
            duration = 0.6
            autoReverse = true
        } else {
            // Listening — gentle, slower
            duration = 0.8 + Double(index % 4) * 0.12
            autoReverse = true
        }

        return .easeInOut(duration: duration)
            .repeatForever(autoreverses: autoReverse)
    }

    private func animateBar() {
        // Stagger start per bar
        let delay = Double(index) * 0.05
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            amplitude = CGFloat.random(in: 0.5...1.0)
            // Keep animating
            withAnimation(animation) {
                amplitude = CGFloat.random(in: 0.3...1.0)
            }
        }
    }
}

// MARK: - Pulsing Animation Modifier

struct PulsingAnimation: ViewModifier {
    @State private var pulsing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(pulsing ? 1.3 : 0.8)
            .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: pulsing)
            .onAppear { pulsing = true }
    }
}

// MARK: - Speaking Bar Animation (for live conversation TTS)

struct SpeakingBarAnimation: ViewModifier {
    let delay: Double
    @State private var animating = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(y: animating ? 1.0 : 0.3)
            .animation(
                .easeInOut(duration: 0.3)
                    .repeatForever(autoreverses: true)
                    .delay(delay),
                value: animating
            )
            .onAppear { animating = true }
    }
}

// MARK: - Attachment Data Model

struct AttachmentData: Identifiable, Equatable {
    let id = UUID()
    let data: Data
    let fileName: String
    let mimeType: String
    var isImage: Bool { mimeType.hasPrefix("image/") }

    var fileExtension: String {
        (fileName as NSString).pathExtension
    }

    var fileIcon: String {
        let ext = fileExtension.lowercased()
        switch ext {
        case "pdf": return "doc.text.fill"
        case "txt", "md", "log": return "doc.text"
        case "json", "xml", "yaml", "yml": return "curlybraces"
        case "swift", "py", "js", "ts", "go", "rs", "java", "c", "cpp": return "chevron.left.forwardslash.chevron.right"
        case "zip", "tar", "gz", "rar": return "archivebox.fill"
        case "csv", "xls", "xlsx": return "tablecells.fill"
        case "doc", "docx": return "doc.richtext.fill"
        default: return "doc.fill"
        }
    }
}

// MARK: - Glass Connection Card (theme-aware)

struct GlassConnectionCard: View {
    let health: HealthResponse
    let config: ConnectionConfig
    @EnvironmentObject private var appearance: AppearanceSettings

    private var theme: any HermesTheme { appearance.activeTheme }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacingS) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Connected")
                    .font(.headline)
            }
            Text("\(config.label) — Hermes v\(health.version ?? "unknown")")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(theme.spacingL)
        .if(theme.usesGlass) { view in
            view.glassEffect(.regular.tint(.green.opacity(0.08)))
        }
        .if(!theme.usesGlass) { view in
            view.background(Color(.tertiarySystemFill))
        }
        .clipShape(RoundedRectangle(cornerRadius: theme.bubbleRadius, style: .continuous))
    }
}

// MARK: - View Modifier Extension

extension View {
    /// Apply conditional transform
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, @ViewBuilder transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
