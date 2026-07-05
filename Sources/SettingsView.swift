import SwiftUI

/// Settings with Liquid Glass design.
struct SettingsView: View {
    @ObservedObject var store: AppStore
    @EnvironmentObject var appearance: AppearanceSettings
    @Environment(\.dismiss) private var dismiss

    @State private var availableModels: [ModelInfo] = []
    @State private var availableToolsets: [ToolsetInfo] = []
    @State private var selectedModel: String = ""
    @State private var isLoadingModels = false

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

                        // Model & Provider selector
                        glassCard {
                            VStack(alignment: .leading, spacing: GlassTheme.spacingS) {
                                Label("Model", systemImage: "cpu")
                                    .font(.headline)

                                if isLoadingModels {
                                    HStack {
                                        ProgressView()
                                        Text("Loading models...")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                } else if availableModels.isEmpty {
                                    Text("No models available")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Picker("Active Model", selection: $selectedModel) {
                                        ForEach(availableModels) { model in
                                            Text(model.id)
                                                .tag(model.id)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .onChange(of: selectedModel) { _, newValue in
                                        // Store preference
                                        UserDefaults.standard.set(newValue, forKey: "preferred_model")
                                    }

                                    if let model = availableModels.first(where: { $0.id == selectedModel }) {
                                        if let owner = model.ownedBy {
                                            settingRow("Provider", owner)
                                        }
                                        settingRow("Current", store.capabilities?.model ?? "unknown")
                                    }
                                }
                            }
                        }

                        // Server info
                        if let caps = store.capabilities {
                            glassCard {
                                VStack(alignment: .leading, spacing: GlassTheme.spacingS) {
                                    Label("Server", systemImage: "server.rack")
                                        .font(.headline)
                                    settingRow("Platform", caps.platform)
                                    settingRow("Auth", caps.auth.type)

                                    // Features
                                    Divider().padding(.vertical, 4)
                                    featureRow("Streaming Chat", caps.features.sessionChatStreaming)
                                    featureRow("Async Runs", caps.features.runSubmission)
                                    featureRow("Tool Approvals", caps.features.runApprovalResponse)
                                    featureRow("Session Forking", caps.features.sessionFork)
                                    featureRow("Skills API", caps.features.skillsAPI)
                                }
                            }
                        }

                        // Skills - link to dedicated page
                        NavigationLink {
                            SkillsListView(store: store)
                        } label: {
                            HStack {
                                Image(systemName: "books.vertical")
                                    .foregroundStyle(appearance.accent)
                                Text("Skills")
                                Spacer()
                                Text("\(store.skills.count)")
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
                Task {
                    await store.refreshSkills()
                    await loadModels()
                }
            }
        }
    }

    // MARK: - Model Loading

    private func loadModels() async {
        guard let client = store.apiClient else { return }
        isLoadingModels = true
        defer { isLoadingModels = false }

        do {
            availableModels = try await client.getModels()
            // Load saved preference or use current server model
            let saved = UserDefaults.standard.string(forKey: "preferred_model")
            if let saved = saved, availableModels.contains(where: { $0.id == saved }) {
                selectedModel = saved
            } else if let caps = store.capabilities {
                selectedModel = caps.model
            } else if let first = availableModels.first {
                selectedModel = first.id
            }
        } catch {
            // Silently fail -- models list is optional
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

// MARK: - Skills List View

struct SkillsListView: View {
    @ObservedObject var store: AppStore
    @EnvironmentObject var appearance: AppearanceSettings
    @State private var searchText = ""

    private var filteredSkills: [Skill] {
        if searchText.isEmpty {
            return store.skills
        }
        return store.skills.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            ($0.description ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        ZStack {
            appearance.activeTheme.backgroundView
                .ignoresSafeArea()

            List {
                if filteredSkills.isEmpty {
                    ContentUnavailableView(
                        "No Skills",
                        systemImage: "books.vertical",
                        description: Text("No skills are loaded on this server.")
                    )
                } else {
                    ForEach(filteredSkills) { skill in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(skill.name)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            if let desc = skill.description {
                                Text(desc)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Skills")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search skills")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await store.refreshSkills() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
    }
}
