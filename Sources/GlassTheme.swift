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

    @EnvironmentObject private var appearance: AppearanceSettings

    private var theme: any HermesTheme { appearance.activeTheme }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 40) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: theme.spacingXS) {
                Text(content)
                    .font(messageFont)
                    .textSelection(.enabled)
                    .foregroundStyle(isUser ? .white : .primary)

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

    private var theme: any HermesTheme { appearance.activeTheme }

    var body: some View {
        Text(theme.cursorCharacter)
            .font(.caption2)
            .foregroundStyle(theme.cursorColor)
            .opacity(visible ? 1 : 0)
            .animation(.easeInOut(duration: 0.5).repeatForever(), value: visible)
            .onAppear { visible.toggle() }
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

    private var theme: any HermesTheme { appearance.activeTheme }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(theme.accent.opacity(0.6))
                    .frame(width: 7, height: 7)
                    .scaleEffect(animate ? 1.0 : 0.4)
                    .opacity(animate ? 1.0 : 0.3)
                    .animation(
                        .easeInOut(duration: 0.7)
                            .repeatForever()
                            .delay(Double(i) * 0.25),
                        value: animate
                    )
            }
        }
        .padding(.horizontal, theme.spacingL)
        .padding(.vertical, theme.spacingM)
        .if(theme.usesGlass) { view in
            view.glassEffect(.regular)
        }
        .if(!theme.usesGlass) { view in
            view.background(Color(.tertiarySystemFill))
        }
        .clipShape(RoundedRectangle(cornerRadius: theme.bubbleRadius, style: .continuous))
        .onAppear { animate = true }
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
                .if(theme.usesGlass) { view in
                    view.glassEffect(.regular.tint(theme.warning.opacity(0.08)))
                }
                .if(!theme.usesGlass) { view in
                    view.background(theme.warning.opacity(0.05))
                }
                .clipShape(RoundedRectangle(cornerRadius: theme.radiusS, style: .continuous))

            HStack(spacing: theme.spacingM) {
                GlassButton("Allow Once", tint: .green) { onResolve("once") }
                GlassButton("Allow Session", tint: .blue) { onResolve("session") }
                GlassButton("Deny", tint: theme.danger) { onResolve("deny") }
            }
        }
        .padding(theme.spacingL)
        .if(theme.usesGlass) { view in
            view.glassEffect(.regular.tint(theme.warning.opacity(0.05)))
        }
        .if(!theme.usesGlass) { view in
            view.background(Color(.tertiarySystemFill))
        }
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
                    view.glassEffect(.regular.tint(tint.opacity(0.2)))
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

struct GlassInputBar: View {
    @Binding var text: String
    let isStreaming: Bool
    let onSend: () -> Void
    let onStop: () -> Void
    let onCamera: () -> Void
    let attachments: [AttachmentData]
    let onRemoveAttachment: (Int) -> Void

    @FocusState private var focused: Bool
    @EnvironmentObject private var appearance: AppearanceSettings
    @StateObject private var voiceTranscriber = VoiceTranscriber()
    @State private var showAttachmentMenu = false

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

            // Voice transcription indicator
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
                .if(theme.usesGlass) { view in
                    view.glassEffect(.regular.tint(theme.danger.opacity(0.05)))
                }
                .if(!theme.usesGlass) { view in
                    view.background(theme.danger.opacity(0.05))
                }
            }

            // Main input row
            HStack(spacing: theme.spacingS) {
                // Plus button — attachment menu
                Button {
                    showAttachmentMenu = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(theme.accent.opacity(0.7))
                }
                .buttonStyle(.plain)
                .confirmationDialog("Attach", isPresented: $showAttachmentMenu, titleVisibility: .visible) {
                    Button("Photo Library") { onCamera() }
                    Button("Cancel", role: .cancel) {}
                }

                // Text input
                TextField("Message", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit(onSend)

                // Voice button
                if !voiceTranscriber.isRecording && text.isEmpty && attachments.isEmpty {
                    Button {
                        voiceTranscriber.startTranscription()
                    } label: {
                        Image(systemName: "mic.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                // Send / Stop button
                if isStreaming {
                    Button(action: onStop) {
                        Image(systemName: "stop.fill")
                            .font(.title3)
                            .foregroundStyle(theme.danger)
                    }
                    .buttonStyle(.plain)
                } else if canSend {
                    Button(action: onSend) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle(theme.accent)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                }
            }
            .padding(.horizontal, theme.spacingL)
            .padding(.vertical, theme.spacingM)
            .if(theme.usesGlass) { view in
                view.glassEffect(.regular)
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