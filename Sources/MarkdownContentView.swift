import SwiftUI

/// Block-level markdown rendering for assistant messages.
/// User messages stay plain text; assistant text blocks get inline markdown
/// via AttributedString, code blocks get a dedicated view.
struct MarkdownContentView: View {
    let content: String
    let isUser: Bool
    let font: Font

    @EnvironmentObject private var appearance: AppearanceSettings

    private var theme: any HermesTheme { appearance.activeTheme }

    var body: some View {
        if isUser {
            inlineText(content)
        } else {
            let blocks = MarkdownBlocks.parse(content)
            if blocks.count == 1, case .text(let t) = blocks[0] {
                // Common path: no block syntax — skip the VStack.
                inlineText(t)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                        blockView(block)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlocks.Block) -> some View {
        switch block {
        case .text(let text):
            inlineText(text)
        case .list(let items, let ordered):
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(ordered ? "\(index + 1)." : "•")
                            .foregroundStyle(theme.textSecondary)
                        inlineText(item)
                    }
                }
            }
        case .code(let language, let code):
            CodeBlockView(language: language, code: code)
        }
    }

    private func inlineText(_ text: String) -> some View {
        Text(attributed(text))
            .font(font)
            .textSelection(.enabled)
            .foregroundStyle(isUser ? .white : theme.textPrimary)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func attributed(_ text: String) -> AttributedString {
        guard !isUser,
              let parsed = try? AttributedString(
                markdown: text,
                options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
              )
        else { return AttributedString(text) }
        return parsed
    }
}

/// Fenced code block: monospaced, tinted background, horizontal scroll, copy button.
struct CodeBlockView: View {
    let language: String?
    let code: String

    @EnvironmentObject private var appearance: AppearanceSettings
    @State private var copied = false

    private var theme: any HermesTheme { appearance.activeTheme }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(language ?? "code")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.textMuted)
                Spacer()
                Button {
                    UIPasteboard.general.string = code
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(copied ? "Copied" : "Copy code")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            Divider().overlay(theme.cardBorder)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(theme.textPrimary)
                    .textSelection(.enabled)
                    .padding(10)
            }
        }
        .background(theme.bgCard.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(theme.cardBorder, lineWidth: theme.cardBorderWidth)
        )
    }
}
