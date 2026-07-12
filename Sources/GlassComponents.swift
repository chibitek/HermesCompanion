import SwiftUI

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
                .foregroundStyle(color)
            Text(event.toolName)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(color)
        }
        .padding(.horizontal, theme.spacingM)
        .padding(.vertical, theme.spacingS)
        .background(
            Capsule()
                .fill(theme.bgCard)
                .overlay(Capsule().stroke(theme.cardBorder, lineWidth: theme.cardBorderWidth))
        )
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
        case .progress: return theme.accent
        case .started: return theme.accent.opacity(0.7)
        case .completed: return theme.accentSecondary
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
        .background(AnyView(theme.glassCard(cornerRadius: theme.bubbleRadius)))
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
                    .foregroundStyle(theme.textPrimary)
            }

            Text(approval.command)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .foregroundStyle(theme.textBody)
                .padding(theme.spacingM)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.warning.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: theme.radiusS, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: theme.radiusS, style: .continuous)
                        .stroke(theme.warning.opacity(0.2), lineWidth: 1)
                )

            HStack(spacing: theme.spacingM) {
                GlassButton("Allow Once", tint: theme.accent) { onResolve("once") }
                GlassButton("Allow Session", tint: theme.accentSecondary) { onResolve("session") }
                GlassButton("Deny", tint: theme.danger) { onResolve("deny") }
            }
        }
        .padding(theme.spacingL)
        .background(AnyView(theme.glassCard(cornerRadius: theme.radiusXL)))
        .overlay(
            RoundedRectangle(cornerRadius: theme.radiusXL, style: .continuous)
                .stroke(theme.warning.opacity(0.25), lineWidth: 1)
        )
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
                .foregroundStyle(tint)
                .padding(.horizontal, theme.spacingM)
                .padding(.vertical, theme.spacingS)
                .background(
                    RoundedRectangle(cornerRadius: theme.controlRadius, style: .continuous)
                        .fill(theme.bgCard)
                        .overlay(
                            RoundedRectangle(cornerRadius: theme.controlRadius, style: .continuous)
                                .stroke(tint.opacity(0.3), lineWidth: 1)
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: theme.controlRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
