import SwiftUI

/// Appearance settings: theme picker, font size, accent color, density.
struct AppearanceSettingsView: View {
    @ObservedObject var appearance: AppearanceSettings

    var body: some View {
        ScrollView {
            VStack(spacing: appearance.activeTheme.spacingM) {

                // MARK: - Theme Picker (Grid)

                VStack(alignment: .leading, spacing: appearance.activeTheme.spacingS) {
                    Label("Theme", systemImage: "paintbrush.fill")
                        .font(.headline)
                        .padding(.horizontal, 4)

                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12),
                    ], spacing: 12) {
                        ForEach(ThemeRegistry.allThemes, id: \.id) { theme in
                            themeCard(theme)
                        }
                    }
                }
                .padding(appearance.activeTheme.spacingL)

                // MARK: - Live Preview

                glassCard {
                    VStack(alignment: .leading, spacing: appearance.activeTheme.spacingS) {
                        Text("Preview")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        GlassBubble(
                            content: "Hey, what can you do?",
                            isUser: true,
                            fontScale: appearance.fontScaleDouble,
                            fixedFontSize: appearance.messageFontSizeDouble,
                            accentColor: appearance.accent,
                            compact: appearance.compactModeBool,
                            showTimestamp: false
                        )

                        GlassBubble(
                            content: "I can send messages, run tools, manage sessions, create cron jobs, and much more. What do you need?",
                            isUser: false,
                            isStreaming: true,
                            fontScale: appearance.fontScaleDouble,
                            fixedFontSize: appearance.messageFontSizeDouble,
                            accentColor: appearance.accent,
                            compact: appearance.compactModeBool
                        )
                    }
                    .padding(appearance.activeTheme.spacingL)
                }

                // MARK: - Color Scheme

                glassCard {
                    VStack(alignment: .leading, spacing: appearance.activeTheme.spacingM) {
                        Label("Appearance", systemImage: "circle.lefthalf.filled")
                            .font(.headline)

                        Picker("Color Scheme", selection: $appearance.colorScheme) {
                            Text("System").tag("system")
                            Text("Dark").tag("dark")
                            Text("Light").tag("light")
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(appearance.activeTheme.spacingL)
                }

                // MARK: - Accent Color (only for Hermes theme)

                if appearance.activeThemeId == "hermes" {
                    glassCard {
                        VStack(alignment: .leading, spacing: appearance.activeTheme.spacingM) {
                            Label("Accent Color", systemImage: "paintpalette")
                                .font(.headline)

                            LazyVGrid(columns: [
                                GridItem(.flexible()),
                                GridItem(.flexible()),
                                GridItem(.flexible()),
                            ], spacing: appearance.activeTheme.spacingS) {

                                accentSwatch("teal", color: Color(red: 0.176, green: 0.831, blue: 0.749))
                                accentSwatch("blue", color: .blue)
                                accentSwatch("purple", color: .purple)
                                accentSwatch("green", color: .green)
                                accentSwatch("orange", color: Color(red: 0.96, green: 0.62, blue: 0.04))
                                accentSwatch("red", color: Color(red: 0.81, green: 0.27, blue: 0.13))
                            }
                        }
                        .padding(appearance.activeTheme.spacingL)
                    }
                }

                // MARK: - Font Size

                glassCard {
                    VStack(alignment: .leading, spacing: appearance.activeTheme.spacingM) {
                        Label("Text Size", systemImage: "textformat.size")
                            .font(.headline)

                        Picker("Size", selection: $appearance.fontScale) {
                            Text("XS").tag(0.7)
                            Text("S").tag(0.85)
                            Text("M").tag(1.0)
                        }
                        .pickerStyle(.segmented)

                        HStack {
                            Text("A")
                                .font(.system(size: 11))
                            Slider(value: $appearance.fontScale, in: 0.7...1.0, step: 0.05)
                            Text("A")
                                .font(.system(size: 16))
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Preview")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("The quick brown fox jumps over the lazy dog. Hermes Companion uses your preferred text size for all messages and UI elements.")
                                .font(.system(size: 14 * appearance.fontScale))
                                .foregroundStyle(.secondary)
                        }
                        .padding(appearance.activeTheme.spacingM)
                        .if(appearance.activeTheme.usesGlass) { view in
                            view.glassEffect(.regular.tint(appearance.accent.opacity(0.06)))
                        }
                        .clipShape(RoundedRectangle(cornerRadius: appearance.activeTheme.radiusM, style: .continuous))
                    }
                    .padding(appearance.activeTheme.spacingL)
                }

                // MARK: - Message Font Override

                glassCard {
                    VStack(alignment: .leading, spacing: appearance.activeTheme.spacingM) {
                        Label("Message Font Size", systemImage: "character.textbox")
                            .font(.headline)

                        HStack {
                            Text("Use fixed message size")
                                .font(.subheadline)
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { appearance.messageFontSize > 0 },
                                set: { appearance.messageFontSize = $0 ? 11 : 0 }
                            ))
                        }

                        if appearance.messageFontSize > 0 {
                            HStack {
                                Text("\(Int(appearance.messageFontSize))pt")
                                    .font(.subheadline)
                                    .monospacedDigit()
                                Slider(value: $appearance.messageFontSize, in: 10...18, step: 1)
                            }

                            Text("Overrides Dynamic Type with a fixed size for message bubbles only.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(appearance.activeTheme.spacingL)
                }

                // MARK: - Layout

                glassCard {
                    VStack(alignment: .leading, spacing: appearance.activeTheme.spacingM) {
                        Label("Layout", systemImage: "rectangle.compress.vertical")
                            .font(.headline)

                        Toggle("Compact Mode", isOn: $appearance.compactMode)
                        Toggle("Show Timestamps", isOn: $appearance.showTimestamps)
                    }
                    .padding(appearance.activeTheme.spacingL)
                }

                // MARK: - Keyboard

                glassCard {
                    VStack(alignment: .leading, spacing: appearance.activeTheme.spacingM) {
                        Label("Keyboard", systemImage: "keyboard")
                            .font(.headline)

                        Toggle("Return key sends message", isOn: $appearance.returnKeySends)
                        Text("When on, the Return key sends your message. Turn off to insert a new line instead.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(appearance.activeTheme.spacingL)
                }
            }
            .padding(appearance.activeTheme.spacingL)
        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
        .dynamicTypeSize(.xSmall ... .large)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func glassCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        let theme = appearance.activeTheme
        content()
            .padding(theme.spacingL)
            .if(theme.usesGlass) { view in
                view.glassEffect(.regular)
            }
            .if(!theme.usesGlass) { view in
                view.background(Color(.tertiarySystemFill))
            }
            .clipShape(RoundedRectangle(cornerRadius: theme.radiusXL, style: .continuous))
    }

    // MARK: - Theme Card (Grid)

    private func themeCard(_ theme: any HermesTheme) -> some View {
        let isSelected = appearance.activeThemeId == theme.id

        return Button {
            withAnimation(.spring(duration: 0.3)) {
                appearance.activeThemeId = theme.id
            }
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        } label: {
            VStack(spacing: 0) {
                // Visual preview area — shows the theme's actual colors
                ZStack {
                    // Theme background
                    theme.bgBase

                    // Mini chat preview using theme colors
                    VStack(spacing: 6) {
                        // User bubble (right-aligned)
                        HStack {
                            Spacer()
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(theme.userBubbleBackground)
                                .frame(width: 60, height: 14)
                        }
                        .padding(.horizontal, 8)

                        // Assistant bubble (left-aligned)
                        HStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(theme.assistantBubbleBackground)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(theme.assistantBubbleBorder, lineWidth: theme.assistantBubbleBorderWidth)
                                )
                                .frame(width: 80, height: 14)
                            Spacer()
                        }
                        .padding(.horizontal, 8)

                        // Accent dot row
                        HStack(spacing: 4) {
                            Circle()
                                .fill(theme.accent)
                                .frame(width: 8, height: 8)
                            Circle()
                                .fill(theme.accentSecondary)
                                .frame(width: 8, height: 8)
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.bottom, 4)
                    }
                    .padding(.top, 8)
                }
                .frame(height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                // Theme name + description
                VStack(alignment: .leading, spacing: 2) {
                    Text(theme.displayName)
                        .font(.system(size: 14, weight: isSelected ? .bold : .semibold))
                        .foregroundStyle(isSelected ? theme.accent : theme.textPrimary)
                        .lineLimit(1)

                    Text(theme.subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(theme.bgSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? theme.accent.opacity(0.6) : theme.cardBorder, lineWidth: isSelected ? 2 : 1)
            )
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(theme.accent)
                        .font(.system(size: 22))
                        .background(Circle().fill(theme.bgBase).frame(width: 24, height: 24))
                        .padding(6)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: isSelected ? theme.accent.opacity(0.15) : .clear, radius: 8, y: 4)
        }
        .buttonStyle(.plain)
    }

    private func accentSwatch(_ name: String, color: Color) -> some View {
        Button {
            appearance.accentColor = name
        } label: {
            RoundedRectangle(cornerRadius: appearance.activeTheme.radiusS, style: .continuous)
                .fill(color)
                .frame(height: 40)
                .overlay {
                    if appearance.accentColor == name {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.white)
                            .fontWeight(.bold)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}
