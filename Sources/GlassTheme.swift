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

// MARK: - Glass Input Bar (theme-aware)

struct GlassInputBar: View {
    @Binding var text: String
    let isStreaming: Bool
    let onSend: () -> Void
    let onStop: () -> Void
    let onCamera: () -> Void

    @FocusState private var focused: Bool
    @EnvironmentObject private var appearance: AppearanceSettings

    private var theme: any HermesTheme { appearance.activeTheme }

    var body: some View {
        HStack(spacing: theme.spacingS) {
            Button(action: onCamera) {
                Image(systemName: "camera")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(true)

            TextField("Message", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .focused($focused)
                .submitLabel(.send)
                .onSubmit(onSend)

            if isStreaming {
                Button(action: onStop) {
                    Image(systemName: "stop.fill")
                        .font(.title3)
                        .foregroundStyle(theme.danger)
                }
                .buttonStyle(.plain)
            } else {
                Button(action: onSend) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(canSend ? theme.accent : .secondary)
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

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespaces).isEmpty
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