import SwiftUI

/// Settings with Liquid Glass design.
struct SettingsView: View {
    @ObservedObject var store: AppStore
    @EnvironmentObject var appearance: AppearanceSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                appearance.activeTheme.backgroundView
                    .ignoresSafeArea()

                ScrollView {
                    LazyVStack(spacing: GlassTheme.spacingM) {
                        // Connection card
                        if let config = store.connectionConfig {
                            glassCard {
                                VStack(alignment: .leading, spacing: GlassTheme.spacingS) {
                                    Label("Connection", systemImage: "network")
                                        .font(.headline)
                                    settingRow("Label", config.label)
                                    settingRow("URL", config.normalizedBaseURL)
                                    settingRow("API Key", maskedKey(config.apiKey))
                                }
                            }
                        }

                        // Server info
                        if let caps = store.capabilities {
                            glassCard {
                                VStack(alignment: .leading, spacing: GlassTheme.spacingS) {
                                    Label("Server", systemImage: "server.rack")
                                        .font(.headline)
                                    settingRow("Model", caps.model)
                                    settingRow("Auth", caps.auth.type)
                                }
                            }

                            // Features
                            glassCard {
                                VStack(alignment: .leading, spacing: GlassTheme.spacingS) {
                                    Label("Features", systemImage: "sparkles")
                                        .font(.headline)
                                    featureRow("Streaming Chat", caps.features.sessionChatStreaming)
                                    featureRow("Async Runs", caps.features.runSubmission)
                                    featureRow("Run Events SSE", caps.features.runEventsSSE)
                                    featureRow("Tool Approvals", caps.features.runApprovalResponse)
                                    featureRow("Tool Progress", caps.features.toolProgressEvents)
                                    featureRow("Session Forking", caps.features.sessionFork)
                                    featureRow("Skills API", caps.features.skillsAPI)
                                }
                            }
                        }

                        // Skills
                        glassCard {
                            VStack(alignment: .leading, spacing: GlassTheme.spacingS) {
                                HStack {
                                    Label("Skills", systemImage: "books.vertical")
                                        .font(.headline)
                                    Spacer()
                                    Button {
                                        Task { await store.refreshSkills() }
                                    } label: {
                                        Image(systemName: "arrow.clockwise")
                                    }
                                }

                                if store.skills.isEmpty {
                                    Text("No skills loaded")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                } else {
                                    ForEach(store.skills.prefix(25)) { skill in
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(skill.name)
                                                .font(.subheadline)
                                            if let desc = skill.description {
                                                Text(desc)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(2)
                                            }
                                        }
                                        .padding(.vertical, GlassTheme.spacingXS)
                                    }
                                    if store.skills.count > 25 {
                                        Text("... and \(store.skills.count - 25) more")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }

                        // Disconnect
                        Button(role: .destructive) {
                            store.disconnect()
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: "wifi.slash")
                                Text("Disconnect")
                            }
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundStyle(GlassTheme.danger)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, GlassTheme.spacingM)
                            .glassEffect(.regular.tint(GlassTheme.danger.opacity(0.1)))
                            .clipShape(RoundedRectangle(cornerRadius: GlassTheme.radiusM, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, GlassTheme.spacingL)

                        // Appearance
                        NavigationLink {
                            AppearanceSettingsView(appearance: appearance)
                        } label: {
                            HStack {
                                Image(systemName: "paintpalette")
                                    .foregroundStyle(appearance.accent)
                                Text("Appearance")
                                Spacer()
                                Text(appearance.colorScheme.capitalized)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .font(.body)
                            .padding(GlassTheme.spacingM)
                            .glassEffect(.regular)
                            .clipShape(RoundedRectangle(cornerRadius: GlassTheme.radiusM, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, GlassTheme.spacingL)

                        // About
                        glassCard {
                            VStack(alignment: .leading, spacing: GlassTheme.spacingS) {
                                Label("About", systemImage: "info.circle")
                                    .font(.headline)
                                settingRow("Version", appVersion)

                                Link(destination: URL(string: AppConfig.hermesDocsURL)!) {
                                    HStack {
                                        Text("Hermes Docs")
                                        Spacer()
                                        Image(systemName: "arrow.up.right")
                                    }
                                }

                                Link(destination: URL(string: AppConfig.repoURL)!) {
                                    HStack {
                                        Text("GitHub")
                                        Spacer()
                                        Image(systemName: "arrow.up.right")
                                    }
                                }
                            }
                        }
                    }
                    .padding(GlassTheme.spacingL)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                Task { await store.refreshSkills() }
            }
        }
    }

    // MARK: - Helpers

    private func glassCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(GlassTheme.spacingL)
            .glassEffect(.regular)
            .clipShape(RoundedRectangle(cornerRadius: GlassTheme.radiusXL, style: .continuous))
    }

    private func settingRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func featureRow(_ label: String, _ enabled: Bool) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
            Spacer()
            Image(systemName: enabled ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(enabled ? .green : .secondary)
                .font(.subheadline)
        }
    }

    private func maskedKey(_ key: String) -> String {
        String(repeating: "*", count: min(key.count, 20)) + "..."
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}