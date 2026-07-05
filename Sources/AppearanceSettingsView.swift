import SwiftUI

/// Appearance settings: theme picker, font size, accent color, density.
struct AppearanceSettingsView: View {
    @ObservedObject var appearance: AppearanceSettings

    var body: some View {
        ScrollView {
            VStack(spacing: appearance.activeTheme.spacingM) {

                // MARK: - Theme Picker

                glassCard {
                    VStack(alignment: .leading, spacing: appearance.activeTheme.spacingM) {
                        Label("Theme", systemImage: "paintbrush.fill")
                            .font(.headline)

                        ForEach(ThemeRegistry.allThemes, id: \.id) { theme in
                            themeRow(theme)
                        }
                    }
                    .padding(appearance.activeTheme.spacingL)
                }

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

    private func themeRow(_ theme: any HermesTheme) -> some View {
        let isSelected = appearance.activeThemeId == theme.id

        return Button {
            appearance.activeThemeId = theme.id
        } label: {
            VStack(alignment: .leading, spacing: appearance.activeTheme.spacingS) {
                HStack(alignment: .center, spacing: appearance.activeTheme.spacingM) {
                    themeSwatches(theme)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(theme.displayName)
                            .font(.system(size: 16, weight: isSelected ? .semibold : .regular))
                            .lineLimit(1)
                        Text(theme.subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(appearance.accent)
                            .font(.title3)
                            .frame(width: 28, height: 28)
                    } else {
                        Color.clear.frame(width: 28, height: 28)
                    }
                }
            }
            .padding(appearance.activeTheme.spacingM)
            .if(appearance.activeTheme.usesGlass) { view in
                view.glassEffect(isSelected ? .regular.tint(appearance.accent.opacity(0.12)) : .regular)
            }
            .if(!appearance.activeTheme.usesGlass) { view in
                view.background(isSelected ? appearance.accent.opacity(0.08) : Color.clear)
                view.overlay(
                    RoundedRectangle(cornerRadius: appearance.activeTheme.radiusL, style: .continuous)
                        .stroke(isSelected ? appearance.accent.opacity(0.3) : Color.clear, lineWidth: 1)
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: appearance.activeTheme.radiusL, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func themeSwatches(_ theme: any HermesTheme) -> some View {
        HStack(spacing: -8) {
            Circle()
                .fill(theme.accent)
                .frame(width: 28, height: 28)
                .overlay(Circle().stroke(.white.opacity(0.2), lineWidth: 2))
            Circle()
                .fill(theme.accentSecondary)
                .frame(width: 28, height: 28)
                .overlay(Circle().stroke(.white.opacity(0.2), lineWidth: 2))
            if !theme.usesGlass {
                Circle()
                    .fill(Color.black)
                    .frame(width: 28, height: 28)
                    .overlay(Circle().stroke(.white.opacity(0.2), lineWidth: 2))
            }
        }
        .frame(width: theme.usesGlass ? 48 : 68, alignment: .leading)
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
