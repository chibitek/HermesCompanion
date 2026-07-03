import SwiftUI

/// Liquid Glass design system for Hermes Companion.
///
/// Uses iOS 26 GlassButton, GlassEffectContainer, and material backgrounds
/// to create the translucent, depth-heavy look Apple introduced in iOS 26
/// and is doubling down on for iOS 27.
///
/// All views use .glassEffect() and .background(.glassEffect) for that
/// frosted-glass, light-refracting appearance.
///

// MARK: - Design Tokens

enum GlassTheme {
    // Colors
    static let accent = Color(red: 0.176, green: 0.831, blue: 0.749)  // #2DD4BF teal
    static let accentSecondary = Color(red: 0.0, green: 0.702, blue: 0.596)  // #00B398
    static let danger = Color(red: 0.811, green: 0.271, blue: 0.125)  // #CF4520
    static let warning = Color(red: 0.961, green: 0.620, blue: 0.043)  // #F59E0B

    // Spacing
    static let spacingXS: CGFloat = 4
    static let spacingS: CGFloat = 8
    static let spacingM: CGFloat = 12
    static let spacingL: CGFloat = 16
    static let spacingXL: CGFloat = 24

    // Corner radii
    static let radiusS: CGFloat = 10
    static let radiusM: CGFloat = 16
    static let radiusL: CGFloat = 22
    static let radiusXL: CGFloat = 28

    // Bubble max width ratio
    static let bubbleMaxWidthRatio: CGFloat = 0.82
}

// MARK: - Glass Message Bubble

struct GlassBubble: View {
    let content: String
    let isUser: Bool
    var isStreaming: Bool = false
    var fontScale: Double = 1.0
    var fixedFontSize: Double = 0  // 0 = use system Dynamic Type
    var accentColor: Color = GlassTheme.accent
    var compact: Bool = false
    var showTimestamp: Bool = false

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 40) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: GlassTheme.spacingXS) {
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
            .padding(.horizontal, compact ? 12 : GlassTheme.spacingL)
            .padding(.vertical, compact ? 8 : GlassTheme.spacingM)
            .frame(maxWidth: screenBoundsWidth * GlassTheme.bubbleMaxWidthRatio,
                   alignment: isUser ? .trailing : .leading)
            .background(bubbleBackground)
            .clipShape(RoundedRectangle(cornerRadius: compact ? 14 : GlassTheme.radiusL, style: .continuous))
            .if(isUser) { view in
                view.glassEffect(.regular.tint(accentColor.opacity(0.35)))
            }
            .if(!isUser) { view in
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
            return .system(size: fixedFontSize)
        }
        return .body
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        if isUser {
            GlassTheme.accent.opacity(0.25)
        } else {
            Color.clear  // Glass effect provides the visual
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

// MARK: - Blinking Cursor

struct BlinkingCursor: View {
    @State private var visible = true

    var body: some View {
        Text("▋")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .opacity(visible ? 1 : 0)
            .animation(.easeInOut(duration: 0.5).repeatForever(), value: visible)
            .onAppear { visible.toggle() }
    }
}

// MARK: - Glass Tool Chip

struct GlassToolChip: View {
    let event: ToolEvent

    var body: some View {
        HStack(spacing: GlassTheme.spacingXS) {
            Image(systemName: icon)
                .font(.caption)
            Text(event.toolName)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, GlassTheme.spacingM)
        .padding(.vertical, GlassTheme.spacingS)
        .glassEffect(.regular.tint(color.opacity(0.2)))
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
        case .failed: return GlassTheme.danger
        }
    }
}

// MARK: - Glass Thinking Indicator

struct GlassThinkingIndicator: View {
    @State private var animate = false

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(.secondary)
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
        .padding(.horizontal, GlassTheme.spacingL)
        .padding(.vertical, GlassTheme.spacingM)
        .glassEffect(.regular)
        .clipShape(RoundedRectangle(cornerRadius: GlassTheme.radiusL, style: .continuous))
        .onAppear { animate = true }
    }
}

// MARK: - Glass Approval Card

struct GlassApprovalCard: View {
    let approval: PendingApproval
    let onResolve: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: GlassTheme.spacingM) {
            HStack(spacing: GlassTheme.spacingS) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.title3)
                    .foregroundStyle(GlassTheme.warning)
                Text("Approval Required")
                    .font(.headline)
            }

            Text(approval.command)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .padding(GlassTheme.spacingM)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular.tint(GlassTheme.warning.opacity(0.08)))
                .clipShape(RoundedRectangle(cornerRadius: GlassTheme.radiusS, style: .continuous))

            HStack(spacing: GlassTheme.spacingM) {
                GlassButton("Allow Once", tint: .green) { onResolve("once") }
                GlassButton("Allow Session", tint: .blue) { onResolve("session") }
                GlassButton("Deny", tint: GlassTheme.danger) { onResolve("deny") }
            }
        }
        .padding(GlassTheme.spacingL)
        .glassEffect(.regular.tint(GlassTheme.warning.opacity(0.05)))
        .clipShape(RoundedRectangle(cornerRadius: GlassTheme.radiusXL, style: .continuous))
        .padding(.horizontal, GlassTheme.spacingL)
        .padding(.bottom, GlassTheme.spacingS)
    }
}

// MARK: - Glass Button

struct GlassButton: View {
    let label: String
    let tint: Color
    let action: () -> Void

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
                .padding(.horizontal, GlassTheme.spacingM)
                .padding(.vertical, GlassTheme.spacingS)
                .glassEffect(.regular.tint(tint.opacity(0.2)))
                .clipShape(RoundedRectangle(cornerRadius: GlassTheme.radiusS, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Glass Input Bar

struct GlassInputBar: View {
    @Binding var text: String
    let isStreaming: Bool
    let onSend: () -> Void
    let onStop: () -> Void
    let onCamera: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: GlassTheme.spacingS) {
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
                        .foregroundStyle(GlassTheme.danger)
                }
                .buttonStyle(.plain)
            } else {
                Button(action: onSend) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(canSend ? GlassTheme.accent : .secondary)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
        }
        .padding(.horizontal, GlassTheme.spacingL)
        .padding(.vertical, GlassTheme.spacingM)
        .glassEffect(.regular)
        .clipShape(RoundedRectangle(cornerRadius: GlassTheme.radiusL, style: .continuous))
        .padding(.horizontal, GlassTheme.spacingL)
        .padding(.bottom, GlassTheme.spacingS)
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

// MARK: - Glass Connection Card

struct GlassConnectionCard: View {
    let health: HealthResponse
    let config: ConnectionConfig

    var body: some View {
        VStack(alignment: .leading, spacing: GlassTheme.spacingS) {
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
        .padding(GlassTheme.spacingL)
        .glassEffect(.regular.tint(.green.opacity(0.08)))
        .clipShape(RoundedRectangle(cornerRadius: GlassTheme.radiusL, style: .continuous))
    }
}

// MARK: - View Modifier Extension

extension View {
    /// Apply conditional transform
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}