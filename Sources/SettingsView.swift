import SwiftUI
import AVFoundation

/// Settings with clean, Apple-style Form layout.
///
/// v1.7 layout:
///   - Server: single picker listing all saved connections (auto-connect on switch).
///   - Provider / Model / Thinking: three dropdowns synced from the gateway's
///     /v1/models and macOS Hermes provider list. Persisted in UserDefaults.
///   - No "Current" row — the pickers themselves are the current state.
struct SettingsView: View {
    @ObservedObject var store: AppStore
    @EnvironmentObject var appearance: AppearanceSettings
    @Environment(\.dismiss) private var dismiss

    @State private var availableModels: [ModelInfo] = []
    @State private var isLoadingModels = false
    @State private var showingAddServer = false
    @State private var editingServer: ConnectionConfig?

    // Local working copies of picker selections, so the pickers don't
    // fight the parent's @Published when the user is mid-edit.
    @State private var selectedProvider: String = Self.knownProviders.first ?? ""
    @State private var selectedModel: String = ""
    @State private var selectedThinking: String = ""
    @State private var selectedServerURL: String = ""

    var body: some View {
        NavigationStack {
            Form {
                serverSection
                providerSection
                modelSection
                thinkingSection
                capabilitiesSections
                navigationSections
                disconnectSection
                aboutSection
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
                    await store.refreshCapabilities()
                    await store.refreshSkills()
                    await store.refreshToolsets()
                    primePickers()
                    await loadModels(forProvider: selectedProvider)
                    primePickers()
                }
            }
            .onChange(of: store.connectionConfig?.baseURL) { _, _ in
                Task {
                    await store.refreshCapabilities()
                    primePickers()
                    await loadModels()
                    primePickers()
                }
            }
            .sheet(isPresented: $showingAddServer) {
                ConnectionSetupView(store: store)
            }
        }
    }

    // MARK: - Server picker

    private var serverSection: some View {
        Section("Server") {
            if store.savedConnections.isEmpty {
                Button {
                    showingAddServer = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(appearance.accent)
                        Text("Add Server")
                    }
                }
            } else {
                Picker("Server", selection: $selectedServerURL) {
                    ForEach(store.savedConnections, id: \.baseURL) { config in
                        Text(config.label.isEmpty ? config.baseURL : config.label)
                            .tag(config.baseURL)
                    }
                    Text("Add Server…")
                        .tag("__add__")
                }
                .pickerStyle(.menu)
                .onChange(of: selectedServerURL) { _, newValue in
                    if newValue == "__add__" {
                        selectedServerURL = store.connectionConfig?.baseURL ?? ""
                        showingAddServer = true
                        return
                    }
                    if let target = store.savedConnections.first(where: { $0.baseURL == newValue }),
                       target.baseURL != store.connectionConfig?.baseURL {
                        Task { await store.switchToConnection(target) }
                    }
                }
                
                // Add edit buttons for each server
                ForEach(store.savedConnections, id: \.baseURL) { config in
                    HStack {
                        Text(config.label.isEmpty ? config.baseURL : config.label)
                            .font(.subheadline)
                        Spacer()
                        Button("Edit") {
                            editServer(config)
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                    }
                }

                if let config = store.connectionConfig {
                    HStack {
                        Image(systemName: "network")
                            .foregroundStyle(.secondary)
                        Text(config.normalizedBaseURL)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Button(role: .destructive) {
                        Task { await store.deleteConnection(config) }
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("Remove This Server")
                        }
                    }
                }
            }
        }
        .sheet(item: $editingServer) { config in
            ConnectionSetupView(store: store, initialConfig: config)
        }
    }
    
    private func editServer(_ config: ConnectionConfig) {
        editingServer = config
    }

    // MARK: - Provider picker

    /// Slugs we know about, in display order. Matches the macOS Hermes provider list.
    private static let knownProviders: [String] = [
        "nous", "openrouter", "ollama-local", "opencode", "opencode-zen", "custom"
    ]

    /// Available providers = known list ∪ anything reported by the gateway
    /// (so a new provider slug added server-side shows up automatically).
    private var availableProviders: [String] {
        let fromModels = Set(availableModels.compactMap { $0.ownedBy })
        let reportedProvider = store.capabilities?.currentProvider ?? store.effectiveCurrentProvider
        var combined = Self.knownProviders + Array(fromModels.subtracting(Self.knownProviders)).sorted()
        if !reportedProvider.isEmpty && !combined.contains(reportedProvider) {
            combined.append(reportedProvider)
        }
        if preferredOrEmpty.isEmpty { return combined }
        // Always include the currently selected one even if not in either list
        var withCurrent = combined
        if !withCurrent.contains(preferredOrEmpty) {
            withCurrent.append(preferredOrEmpty)
        }
        return withCurrent
    }

    private var preferredOrEmpty: String { selectedProvider }

    private var providerSection: some View {
        Section {
            Picker("Provider", selection: $selectedProvider) {
                ForEach(availableProviders, id: \.self) { slug in
                    Text(displayName(for: slug))
                        .tag(slug)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: selectedProvider) { _, newValue in
                store.preferredProvider = newValue
                Task {
                    await loadModels(forProvider: newValue, preferExistingSelection: false)
                }
            }
        } header: {
            Text("Provider")
        } footer: {
            Text("Synced with macOS Hermes. The list of providers and their available models comes from the connected server.")
        }
    }

    // MARK: - Model picker

    /// Models filtered to the selected provider, or all if no provider is set.
    private var modelsForSelectedProvider: [ModelInfo] {
        models(for: selectedProvider)
    }

    private var modelSection: some View {
        Section {
            if isLoadingModels {
                HStack {
                    ProgressView()
                    Text("Loading models...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if availableModels.isEmpty {
                Text("No models available — connect to a server to load them.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Active Model", selection: $selectedModel) {
                    if availableModels.isEmpty {
                        Text("No models available")
                            .tag("")
                    } else {
                        ForEach(availableModels) { model in
                            Text(displayName(for: model))
                                .tag(model.id)
                        }
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedModel) { _, newValue in
                    store.preferredModel = newValue
                }
            }
        } header: {
            Text("Model")
        } footer: {
            if !selectedProvider.isEmpty {
                Text("Models are synced from your connected Hermes server.")
            }
        }
    }

    // MARK: - Thinking picker

    private static let thinkingOptions: [(value: String, label: String)] = [
        ("", "Off"),
        ("low", "Low"),
        ("medium", "Medium"),
        ("high", "High"),
    ]

    private var thinkingSection: some View {
        Section {
            Picker("Thinking", selection: $selectedThinking) {
                ForEach(Self.thinkingOptions, id: \.value) { opt in
                    Text(opt.label).tag(opt.value)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: selectedThinking) { _, newValue in
                store.preferredThinking = newValue
            }
        } header: {
            Text("Reasoning")
        } footer: {
            Text("Local preference only — the gateway's chat endpoint doesn't currently honor a per-message reasoning override. Saved so it's ready when server support lands.")
        }
    }

    // MARK: - Server capabilities

    @ViewBuilder
    private var capabilitiesSections: some View {
        if let caps = store.capabilities {
            Section("Server") {
                settingRow("Platform", caps.platform)
                settingRow("Default Model", caps.currentModel?.isEmpty == false ? caps.currentModel! : caps.model)
                if let provider = caps.currentProvider, !provider.isEmpty {
                    settingRow("Current Provider", displayName(for: provider))
                }
                if let model = caps.currentModel, !model.isEmpty {
                    settingRow("Current Model", model)
                }
                settingRow("Auth", caps.auth.type)
            }
            Section("Features") {
                featureRow("Streaming Chat", caps.features.sessionChatStreaming)
                featureRow("Async Runs", caps.features.runSubmission)
                featureRow("Tool Approvals", caps.features.runApprovalResponse)
                featureRow("Session Forking", caps.features.sessionFork)
                featureRow("Skills API", caps.features.skillsAPI)
            }
        }
    }

    // MARK: - Navigation links (Skills, Appearance, Voice)

    private var navigationSections: some View {
        Group {
            Section {
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
                    }
                }
                NavigationLink {
                    ToolsetsListView(store: store)
                } label: {
                    HStack {
                        Image(systemName: "wrench.and.screwdriver")
                            .foregroundStyle(appearance.accent)
                        Text("Toolsets")
                        Spacer()
                        Text("\(store.toolsets.filter(\.enabled).count)/\(store.toolsets.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section {
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
                    }
                }
            }
            Section {
                NavigationLink {
                    VoiceSettingsView()
                } label: {
                    HStack {
                        Image(systemName: "waveform")
                            .foregroundStyle(appearance.accent)
                        Text("Voice")
                        Spacer()
                        Text(voiceName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Disconnect

    private var disconnectSection: some View {
        Section {
            Button(role: .destructive) {
                store.disconnect()
                dismiss()
            } label: {
                HStack {
                    Image(systemName: "wifi.slash")
                    Text("Disconnect")
                }
            }
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section("About") {
            settingRow("Version", appVersion)
            Link(destination: URL(string: AppConfig.hermesDocsURL)!) {
                HStack {
                    Text("Hermes Docs")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Link(destination: URL(string: AppConfig.repoURL)!) {
                HStack {
                    Text("GitHub")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Model Loading

    private func loadModels(forProvider provider: String? = nil, preferExistingSelection: Bool = true) async {
        guard let client = store.apiClient else { return }
        let targetProvider = provider ?? selectedProvider
        isLoadingModels = true
        defer { isLoadingModels = false }

        do {
            availableModels = try await client.getModels()
            addCurrentModelIfNeeded()
            selectCurrentModel(forProvider: targetProvider, preferExistingSelection: preferExistingSelection)
        } catch {
            availableModels = []
            addCurrentModelIfNeeded()
            selectCurrentModel(forProvider: targetProvider, preferExistingSelection: preferExistingSelection)
            // Silently fail — models list is optional
        }
    }

    /// Initialize the local picker state from the store's persisted values,
    /// or fall back to the gateway's defaults if no preference is saved.
    private func primePickers() {
        selectedServerURL = store.connectionConfig?.baseURL ?? ""

        if !store.preferredProvider.isEmpty {
            selectedProvider = store.preferredProvider
        } else if let provider = store.capabilities?.currentProvider, !provider.isEmpty {
            selectedProvider = provider
        } else if let owner = modelForSelection(store.preferredModel)?.ownedBy {
            selectedProvider = owner
        } else if let owner = modelForSelection(store.effectiveCurrentModel)?.ownedBy {
            selectedProvider = owner
        }

        // Fallback: ensure the picker always has a selection
        if selectedProvider.isEmpty {
            selectedProvider = Self.knownProviders.first ?? ""
        }

        if !store.preferredModel.isEmpty && models(for: selectedProvider).contains(where: { $0.id == store.preferredModel }) {
            selectedModel = store.preferredModel
        } else {
            selectCurrentModel(forProvider: selectedProvider, preferExistingSelection: true)
        }

        selectedThinking = store.preferredThinking
    }

    // MARK: - Helpers

    private func settingRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func featureRow(_ label: String, _ enabled: Bool) -> some View {
        HStack {
            Text(label)
            Spacer()
            Image(systemName: enabled ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(enabled ? .green : .secondary)
        }
    }

    private func modelForSelection(_ id: String) -> ModelInfo? {
        availableModels.first(where: { $0.id == id })
    }

    private func models(for provider: String) -> [ModelInfo] {
        if provider.isEmpty { return availableModels }
        return availableModels.filter { model in
            if let owner = model.ownedBy, owner == provider {
                return true
            }
            return providerFromModelID(model.id) == provider
        }
    }

    private func selectCurrentModel(forProvider provider: String, preferExistingSelection: Bool) {
        let providerModels = models(for: provider)

        if preferExistingSelection,
           !selectedModel.isEmpty,
           providerModels.contains(where: { $0.id == selectedModel }) {
            store.preferredModel = selectedModel
            return
        }

        if !store.preferredModel.isEmpty,
           providerModels.contains(where: { $0.id == store.preferredModel }) {
            selectedModel = store.preferredModel
            return
        }

        let serverModel = store.capabilities?.currentModel ?? ""
        if !serverModel.isEmpty,
           providerModels.contains(where: { $0.id == serverModel }) {
            selectedModel = serverModel
            store.preferredModel = serverModel
            return
        }

        if let first = providerModels.first {
            selectedModel = first.id
            store.preferredModel = first.id
        } else {
            selectedModel = ""
            store.preferredModel = ""
        }
    }

    private func addCurrentModelIfNeeded() {
        let model = store.effectiveCurrentModel
        guard !model.isEmpty, !availableModels.contains(where: { $0.id == model }) else { return }
        let owner = store.capabilities?.currentProvider ?? providerFromModelID(model) ?? selectedProvider
        availableModels.insert(ModelInfo(id: model, ownedBy: owner.isEmpty ? nil : owner), at: 0)
    }

    private func providerFromModelID(_ id: String) -> String? {
        guard let slash = id.firstIndex(of: "/"), slash > id.startIndex else { return nil }
        return String(id[..<slash])
    }

    /// Display name for a model. Strips the "provider/" prefix and falls back
    /// to the raw id.
    private func displayName(for model: ModelInfo) -> String {
        let id = model.id
        if let slash = id.firstIndex(of: "/") {
            return String(id[id.index(after: slash)...])
        }
        return id
    }

    /// Display name for a provider slug. Title-cased unless overridden.
    private func displayName(for slug: String) -> String {
        switch slug {
        case "ollama-local": return "Ollama (local)"
        case "opencode-zen": return "OpenCode Zen"
        case "openrouter": return "OpenRouter"
        case "nous": return "Nous"
        case "custom": return "Custom"
        default: return slug.capitalized
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    private var voiceName: String {
        let id = UserDefaults.standard.string(forKey: "voice_identifier") ?? ""
        if !id.isEmpty, let voice = AVSpeechSynthesisVoice(identifier: id) {
            return voice.name
        }
        return "System Default"
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

struct ToolsetsListView: View {
    @ObservedObject var store: AppStore
    @State private var searchText = ""

    private var filteredToolsets: [ToolsetInfo] {
        let sorted = store.toolsets.sorted {
            if $0.enabled != $1.enabled { return $0.enabled && !$1.enabled }
            return $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending
        }
        guard !searchText.isEmpty else { return sorted }
        return sorted.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.label.localizedCaseInsensitiveContains(searchText) ||
            $0.description.localizedCaseInsensitiveContains(searchText) ||
            $0.tools.contains { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var body: some View {
        List {
            if filteredToolsets.isEmpty {
                ContentUnavailableView(
                    "No Toolsets",
                    systemImage: "wrench.and.screwdriver",
                    description: Text("No toolsets are reported by this server.")
                )
            } else {
                ForEach(filteredToolsets) { toolset in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(toolset.label)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Text(toolset.name)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Label(toolset.enabled ? "Enabled" : "Disabled",
                                  systemImage: toolset.enabled ? "checkmark.circle.fill" : "circle")
                                .labelStyle(.iconOnly)
                                .foregroundStyle(toolset.enabled ? .green : .secondary)
                        }

                        Text(toolset.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if !toolset.tools.isEmpty {
                            Text(toolset.tools.joined(separator: ", "))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Toolsets")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search toolsets")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await store.refreshToolsets() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .task {
            await store.refreshToolsets()
        }
    }
}
