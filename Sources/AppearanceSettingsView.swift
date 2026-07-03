import SwiftUI

/// Appearance settings: theme, font size, accent color, density.
struct AppearanceSettingsView: View {
    @ObservedObject var appearance: AppearanceSettings

    var body: some View {
        ScrollView {
            VStack(spacing: GlassTheme.spacingM) {

                // MARK: - Color Scheme
                glassCard {
                    VStack(alignment: .leading, spacing: GlassTheme.spacingM) {
        #if DEBUG
                        Text("Theme")
                            .font(.headline)
        #endif
                        Label("Appearance", systemImage: "circle.lefthalf.filled")
                            .font(.headline)

                        Picker("Color Scheme", selection: $appearance.colorScheme) {
                            Text("System").tag("system")
                            Text("Dark").tag("dark")
                            Text("Light").tag("light")
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(GlassTheme.spacingL)
                    .glassEffect(.regular)
                    .clipShape(RoundedRectangle(cornerRadius: GlassTheme.radiusXL, style: .continuous))
                }

                // MARK: - Accent Color
                glassCard {
                    VStack(alignment: .leading, spacing: GlassTheme.spacingM) {
                        Label("Accent Color", systemImage: "paintpalette")
                            .font(.headline)

                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                        ], spacing: GlassTheme.spacingS) {

                            accentSwatch("teal", color: Color(red: 0.176, green: 0.831, blue: 0.749))
                            accentSwatch("blue", color: .blue)
                            accentSwatch("purple", color: .purple)
                            accentSwatch("green", color: .green)
                            accentSwatch("orange", color: Color(red: 0.96, green: 0.62, blue: 0.04))
                            accentSwatch("red", color: Color(red: 0.81, green: 0.27, blue: 0.13))
                        }
                    }
                    .padding(GlassTheme.spacingL)
                    .glassEffect(.regular)
                    .clipShape(RoundedRectangle(cornerRadius: GlassTheme.radiusXL, style: .continuous))
                }

                // MARK: - Font Size
                glassCard {
                    VStack(alignment: .leading, spacing: GlassTheme.spacingM) {
                        Label("Text Size", systemImage: "textformat.size")
                            .font(.headline)

                        // Quick presets
                        Picker("Size", selection: $appearance.fontScale) {
                            Text("S").tag(0.85)
                            Text("M").tag(1.0)
                            Text("L").tag(1.15)
                            Text("XL").tag(1.3)
                        }
                        .pickerStyle(.segmented)

                        // Fine slider
                        HStack {
                            Text("A")
                                .font(.system(size: 11))
                            Slider(value: $appearance.fontScale, in: 0.7...1.6, step: 0.05)
                            Text("A")
                                .font(.system(size: 20))
                        }

                        // Preview
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Preview")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("The quick brown fox jumps over the lazy dog. Hermes Companion uses your preferred text size for all messages and UI elements.")
                                .font(.system(size: 15 * appearance.fontScale))
                                .foregroundStyle(.secondary)
                        }
                        .padding(GlassTheme.spacingM)
                        .glassEffect(.regular.tint(appearance.accent.opacity(0.06)))
                        .clipShape(RoundedRectangle(cornerRadius: GlassTheme.radiusM, style: .continuous))
                    }
                    .padding(GlassTheme.spacingL)
                    .glassEffect(.regular)
                    .clipShape(RoundedRectangle(cornerRadius: GlassTheme.radiusXL, style: .continuous))
                }

                // MARK: - Message Font Override
                glassCard {
                    VStack(alignment: .leading, spacing: GlassTheme.spacingM) {
                        Label("Message Font Size", systemImage: "character.textbox")
                            .font(.headline)

                        HStack {
                            Text("Auto (System)")
                                .font(.subheadline)
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { appearance.messageFontSize > 0 },
                                set: { appearance.messageFontSize = $0 ? 16 : 0 }
                            ))
                        }

                        if appearance.messageFontSize > 0 {
                            HStack {
                                Text("\(Int(appearance.messageFontSize))pt")
                                    .font(.subheadline)
                                    .monospacedDigit()
                                Slider(value: $appearance.messageFontSize, in: 12...24, step: 1)
                            }

                            Text("Overrides Dynamic Type with a fixed size for message bubbles only.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(GlassTheme.spacingL)
                    .glassEffect(.regular)
                    .clipShape(RoundedRectangle(cornerRadius: GlassTheme.radiusXL, style: .continuous))
                }

                // MARK: - Layout
                glassCard {
                    VStack(alignment: .leading, spacing: GlassTheme.spacingM) {
                        Label("Layout", systemImage: "rectangle.compress.vertical")
                            .font(.headline)

                        Toggle("Compact Mode", isOn: $appearance.compactMode)
                        Toggle("Show Timestamps", isOn: $appearance.showTimestamps)
                    }
                    .padding(GlassTheme.spacingL)
                    .glassEffect(.regular)
                    .clipShape(RoundedRectangle(cornerRadius: GlassTheme.radiusXL, style: .continuous))
                }
            }
            .padding(GlassTheme.spacingL)
        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Helpers

    private func glassCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
    }

    private func accentSwatch(_ name: String, color: Color) -> some View {
        Button {
            appearance.accentColor = name
        } label: {
            RoundedRectangle(cornerRadius: GlassTheme.radiusS, style: .continuous)
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