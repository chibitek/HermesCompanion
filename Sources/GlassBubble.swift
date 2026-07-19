import SwiftUI

// MARK: - Glass Message Bubble (theme-aware)

struct GlassBubble: View {
    let content: String
    let isUser: Bool
    var isStreaming: Bool = false
    var fontScale: Double = 1.0
    var fixedFontSize: Double = 0  // 0 = use system Dynamic Type
    var accentColor: Color = .accentColor
    var compact: Bool = false
    var showTimestamp: Bool = false
    var timestamp: Date? = nil
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
                        .foregroundStyle(isUser ? .white : theme.textPrimary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if showTimestamp, let timestamp {
                    Text(timestamp, style: .time)
                        .font(.caption2)
                        .foregroundStyle(theme.textMuted)
                }
            }
            .padding(.horizontal, compact ? 12 : theme.spacingL)
            .padding(.vertical, compact ? 8 : theme.spacingM)
            .frame(maxWidth: screenBoundsWidth * 0.94,
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
            .overlay(bubbleBorder)
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
        // Dynamic Type: use system body font that respects user's text size preference.
        // fontScale still applies as a multiplier via .font() modifier downstream.
        return .system(size: 14 * fontScale, design: isUser ? .default : monospacedDesign)
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
            LinearGradient(
                colors: [theme.accent, theme.accentSecondary],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            theme.bgCard
        }
    }

    @ViewBuilder
    private var bubbleBorder: some View {
        if !isUser {
            RoundedRectangle(cornerRadius: compact ? 14 : theme.bubbleRadius, style: .continuous)
                .stroke(theme.cardBorder, lineWidth: theme.cardBorderWidth)
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
