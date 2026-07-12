import SwiftUI
import AVFoundation

/// Settings redesigned per the handoff spec.
///
/// Dark background, grouped glass-card sections for Server, Provider, Model,
/// Reasoning, Capabilities, Appearance/Voice, Disconnect and About.
struct SettingsView: View {
    @ObservedObject var store: AppStore
    @EnvironmentObject var appearance: AppearanceSettings
    @Environment(\.dismiss) private var dismiss

    @State private var availableModels: [ModelInfo] = []
    @State private var configuredProviders: [ProviderInfo] = []
    @State private var isLoadingModels = false
    @State private var showingAddServer = false
    @State private var editingServer: ConnectionConfig?

    // Local working copies of picker selections, so the pickers don't
    // fight the parent's @Published when the user is mid-edit.
    @State private var selectedProvider: String = ""
    @State private var selectedModel: String = ""
    @State private var selectedThinking: String = ""
    @State private var selectedServerURL: String = ""
    @State private var modelSearch: String = ""
    @State private var modelRefreshMessage: String?
    @State private var modelRefreshFailed = false

    private var theme: any HermesTheme { appearance.activeTheme }

    var body: some View {
        NavigationStack {
            ZStack {
                theme.backgroundView
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: theme.spacingM) {
                        serverCard
                        providerCard
                        modelCard
                        reasoningCard
                        capabilitiesCard
                        toolsCard
                        appearanceCard
                        voiceCard
                        disconnectCard
                        aboutCard
                    }
                    .padding(.horizontal, theme.spacingM)
                    .padding(.vertical, theme.spacingM)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(theme.accent)
                }
            }
            .onAppear {
                Task {
                    await store.refreshCapabilities()
                    await store.refreshSkills()
                    await store.refreshToolsets()
                    primePickers()
                    await loadModels(forProvider: selectedProvider)
                    // Re-prime only if the model list didn't contain the saved
                    // preference (loadModels may have selected a fallback).
                    if !store.preferredModel.isEmpty,
                       selectedModel != store.preferredModel,
                       models(for: selectedProvider).contains(where: { $0.id == store.preferredModel }) {
                        selectedModel = store.preferredModel
                    }
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
            .onChange(of: selectedProvider) { oldValue, newValue in
                guard oldValue != newValue else { return }
                store.preferredProvider = newValue
                Task {
                    await loadModels(forProvider: newValue, preferExistingSelection: false)
                }
            }
            .sheet(isPresented: $showingAddServer) {
                ConnectionSetupView(store: store)
            }
            .sheet(item: $editingServer) { config in
                ConnectionSetupView(store: store, initialConfig: config)
            }
        }
    }

    // MARK: - Glass card wrapper

    @ViewBuilder
    private func glassCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            AnyView(theme.glassCard(cornerRadius: theme.cardRadius))
            content()
                .padding(theme.spacingL)
        }
    }

    private func cardHeader(_ title: String, icon: String? = nil) -> some View {
        HStack(spacing: theme.spacingS) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.accent)
            }
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.textSecondary)
            Spacer()
        }
    }

    // MARK: - Server card

    private var serverCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: theme.spacingM) {
                cardHeader("Server", icon: "network")

                if store.savedConnections.isEmpty {
                    Button {
                        showingAddServer = true
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(theme.accent)
                            Text("Add Server")
                                .foregroundStyle(theme.textPrimary)
                            Spacer()
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
                    .tint(theme.textPrimary)
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

                    ForEach(store.savedConnections, id: \.baseURL) { config in
                        HStack {
                            Text(config.label.isEmpty ? config.baseURL : config.label)
                                .font(.subheadline)
                                .foregroundStyle(theme.textPrimary)
                            Spacer()
                            Button("Edit") {
                                editServer(config)
                            }
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(theme.accent)
                            .buttonStyle(.plain)
                        }
                    }

                    if let config = store.connectionConfig {
                        Divider()
                            .background(theme.cardBorder)

                        HStack(spacing: theme.spacingS) {
                            Image(systemName: "link")
                                .font(.caption)
                                .foregroundStyle(theme.textMuted)
                            Text(config.normalizedBaseURL)
                                .font(.caption)
                                .foregroundStyle(theme.textSecondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button("Edit") {
                                editServer(config)
                            }
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(theme.accent)
                            .buttonStyle(.plain)
                        }

                        Button(role: .destructive) {
                            Task { await store.deleteConnection(config) }
                        } label: {
                            HStack {
                                Image(systemName: "trash")
                                Text("Remove This Server")
                                Spacer()
                            }
                            .font(.subheadline)
                            .foregroundStyle(theme.danger)
                        }
                    }
                }
            }
        }
    }

    private func editServer(_ config: ConnectionConfig) {
        editingServer = config
    }

    // MARK: - Provider and model cards

    private var availableProviders: [String] {
        if !configuredProviders.isEmpty {
            return configuredProviders.map(\.id)
        }
        // Compatibility with older gateways that omit the top-level provider
        // inventory. Their model rows may also omit `provider`, especially for
        // aggregator catalogs such as OpenRouter. In that case the live
        // capability provider is the inference service for the returned list.
        var seen = Set<String>()
        var providers = availableModels.compactMap(\.provider)
        let current = store.capabilities?.currentProvider ?? store.effectiveCurrentProvider
        if !current.isEmpty {
            providers.insert(current, at: 0)
        }
        // Legacy API-server builds expose OpenRouter by appending its live
        // catalog to `/v1/models`, but omit both the top-level provider list
        // and each row's normalized provider. The synthetic Hermes/profile
        // row is owned by `hermes`; every additional author-owned row exists
        // only because OPENROUTER_API_KEY was configured server-side.
        let hasLegacyOpenRouterCatalog = availableModels.contains { model in
            model.provider == nil
                && !(model.ownedBy ?? "").isEmpty
                && model.ownedBy?.lowercased() != "hermes"
        }
        if providers.isEmpty && hasLegacyOpenRouterCatalog {
            providers.append("openrouter")
        }
        return providers.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private var providerCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 0) {
                cardHeader("Provider", icon: "server.rack")
                    .padding(.bottom, theme.spacingS)

                NavigationLink {
                    ProviderSelectionView(
                        providers: availableProviders,
                        selectedProvider: $selectedProvider,
                        modelCount: { models(for: $0).count },
                        displayName: displayName(for:)
                    )
                } label: {
                    settingsNavigationRow(
                        title: "Provider",
                        subtitle: providerSummary,
                        icon: "server.rack",
                        value: displayName(for: selectedProvider)
                    )
                }
                .buttonStyle(.plain)

                Text("Choose the inference service first. The model screen then shows every model that service reported.")
                    .font(.caption)
                    .foregroundStyle(theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, theme.spacingS)
            }
        }
    }

    private var modelCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: theme.spacingS) {
                    cardHeader("Model", icon: "cpu")
                    Spacer()
                    if isLoadingModels {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .padding(.bottom, theme.spacingS)

                NavigationLink {
                    ModelSelectionView(
                        provider: selectedProvider,
                        models: modelsForSelectedProvider,
                        selectedModel: $selectedModel,
                        favoriteModels: store.favoriteModels,
                        isLoading: isLoadingModels,
                        refreshMessage: modelRefreshMessage,
                        refreshFailed: modelRefreshFailed,
                        displayName: displayName(for:),
                        subtitle: modelSubtitle,
                        onSelect: { model in
                            selectedModel = model.id
                            store.selectPreferredModel(model.id, provider: selectedProvider)
                        },
                        onToggleFavorite: { model in
                            _ = store.toggleFavorite(model.id)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        },
                        onRefresh: {
                            await refreshAllModels()
                        }
                    )
                } label: {
                    settingsNavigationRow(
                        title: "Active Model",
                        subtitle: modelSummary,
                        icon: "cpu",
                        value: selectedModel.isEmpty ? "Choose" : displayName(for: ModelInfo(id: selectedModel, ownedBy: selectedProvider))
                    )
                }
                .buttonStyle(.plain)

                Text("Refresh fetches the live catalog from your connected Hermes server without discarding the last successful list.")
                    .font(.caption)
                    .foregroundStyle(theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, theme.spacingS)
            }
        }
    }

    private var modelsForSelectedProvider: [ModelInfo] {
        models(for: selectedProvider)
    }

    private var providerSummary: String {
        let count = modelsForSelectedProvider.count
        if isLoadingModels { return "Refreshing model catalog..." }
        return count == 1 ? "1 model available" : "\(count) models available"
    }

    private var modelSummary: String {
        if let message = modelRefreshMessage, !message.isEmpty { return message }
        if selectedModel.isEmpty { return "No model selected" }
        return selectedModel
    }

    private func settingsNavigationRow(title: String, subtitle: String, icon: String, value: String) -> some View {
        HStack(spacing: theme.spacingM) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(theme.accent)
                .frame(width: 34, height: 34)
                .background(theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.textPrimary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(theme.textMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: theme.spacingS)

            Text(value)
                .font(.caption.weight(.medium))
                .foregroundStyle(theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 120, alignment: .trailing)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.textMuted)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 6)
    }

    private func modelSubtitle(_ model: ModelInfo) -> String {
        if let owner = model.ownedBy, !owner.isEmpty {
            return displayName(for: owner)
        }
        if let prefix = providerFromModelID(model.id) {
            return displayName(for: prefix)
        }
        return model.id
    }

    // MARK: - Reasoning card

    private static let thinkingOptions: [(value: String, label: String)] = [
        ("", "Off"),
        ("low", "Low"),
        ("medium", "Medium"),
        ("high", "High"),
    ]

    private var reasoningCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: theme.spacingM) {
                cardHeader("Reasoning", icon: "brain")

                Picker("Thinking", selection: $selectedThinking) {
                    ForEach(Self.thinkingOptions, id: \.value) { opt in
                        Text(opt.label).tag(opt.value)
                    }
                }
                .pickerStyle(.menu)
                .tint(theme.textPrimary)
                .onChange(of: selectedThinking) { _, newValue in
                    store.preferredThinking = newValue
                }

                Text("Local preference only — the gateway's chat endpoint doesn't currently honor a per-message reasoning override. Saved so it's ready when server support lands.")
                    .font(.caption)
                    .foregroundStyle(theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Capabilities card

    @ViewBuilder
    private var capabilitiesCard: some View {
        if let caps = store.capabilities {
            glassCard {
                VStack(alignment: .leading, spacing: theme.spacingM) {
                    cardHeader("Capabilities", icon: "sparkles")

                    Toggle("Skills API", isOn: .constant(caps.features.skillsAPI))
                        .tint(theme.accent)
                        .disabled(true)

                    capabilityRow("Streaming Chat", caps.features.sessionChatStreaming)
                    capabilityRow("Async Runs", caps.features.runSubmission)
                    capabilityRow("Tool Approvals", caps.features.runApprovalResponse)
                    capabilityRow("Session Forking", caps.features.sessionFork)
                }
            }
        }
    }

    private func capabilityRow(_ label: String, _ enabled: Bool) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(theme.textPrimary)
            Spacer()
            Image(systemName: enabled ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(enabled ? theme.accent : theme.textMuted)
        }
    }

    // MARK: - Tools card (Skills / Toolsets)

    private var toolsCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: theme.spacingM) {
                cardHeader("Tools", icon: "wrench.and.screwdriver")

                NavigationLink {
                    SkillsListView(store: store)
                } label: {
                    HStack {
                        Image(systemName: "books.vertical")
                            .foregroundStyle(theme.accent)
                        Text("Skills")
                            .foregroundStyle(theme.textPrimary)
                        Spacer()
                        Text("\(store.skills.count)")
                            .font(.caption)
                            .foregroundStyle(theme.textSecondary)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(theme.textMuted)
                    }
                }

                NavigationLink {
                    ToolsetsListView(store: store)
                } label: {
                    HStack {
                        Image(systemName: "gearshape.2")
                            .foregroundStyle(theme.accent)
                        Text("Toolsets")
                            .foregroundStyle(theme.textPrimary)
                        Spacer()
                        Text("\(store.toolsets.filter(\.enabled).count)/\(store.toolsets.count)")
                            .font(.caption)
                            .foregroundStyle(theme.textSecondary)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(theme.textMuted)
                    }
                }
            }
        }
    }

    // MARK: - Appearance card

    private var appearanceCard: some View {
        glassCard {
            NavigationLink {
                AppearanceSettingsView(appearance: appearance)
            } label: {
                HStack {
                    Image(systemName: "paintpalette")
                        .foregroundStyle(theme.accent)
                    Text("Appearance")
                        .foregroundStyle(theme.textPrimary)
                    Spacer()
                    Text(appearance.colorScheme.capitalized)
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(theme.textMuted)
                }
            }
        }
    }

    // MARK: - Voice card

    private var voiceCard: some View {
        glassCard {
            NavigationLink {
                VoiceSettingsView()
            } label: {
                HStack {
                    Image(systemName: "waveform")
                        .foregroundStyle(theme.accent)
                    Text("Voice")
                        .foregroundStyle(theme.textPrimary)
                    Spacer()
                    Text(voiceName)
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(theme.textMuted)
                }
            }
        }
    }

    // MARK: - Disconnect card

    private var disconnectCard: some View {
        glassCard {
            Button {
                store.disconnect()
                dismiss()
            } label: {
                HStack {
                    Image(systemName: "wifi.slash")
                    Text("Disconnect")
                    Spacer()
                }
                .font(.subheadline)
                .foregroundStyle(theme.danger)
            }
        }
    }

    // MARK: - About card

    private var aboutCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: theme.spacingM) {
                cardHeader("About", icon: "info.circle")

                HStack {
                    Text("Version")
                        .foregroundStyle(theme.textSecondary)
                    Spacer()
                    Text(appVersion)
                        .font(.caption)
                        .foregroundStyle(theme.textMuted)
                }

                Link(destination: URL(string: AppConfig.hermesDocsURL)!) {
                    HStack {
                        Text("Hermes Docs")
                            .foregroundStyle(theme.textPrimary)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                            .foregroundStyle(theme.textSecondary)
                    }
                }

                Link(destination: URL(string: AppConfig.repoURL)!) {
                    HStack {
                        Text("GitHub")
                            .foregroundStyle(theme.textPrimary)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                            .foregroundStyle(theme.textSecondary)
                    }
                }
            }
        }
    }

    // MARK: - Model Loading

    private func loadModels(forProvider provider: String? = nil, preferExistingSelection: Bool = true) async {
        await loadModels(
            forProvider: provider,
            preferExistingSelection: preferExistingSelection,
            forceRefresh: false
        )
    }

    private func refreshAllModels() async {
        let previousCount = availableModels.count
        modelRefreshMessage = "Refreshing all provider catalogs..."
        modelRefreshFailed = false
        await loadModels(
            forProvider: selectedProvider,
            preferExistingSelection: true,
            forceRefresh: true
        )
        guard !modelRefreshFailed else { return }
        let added = max(0, availableModels.count - previousCount)
        modelRefreshMessage = added > 0
            ? "Loaded \(availableModels.count) models (\(added) new)."
            : "Model catalog is current (\(availableModels.count) models)."
    }

    private func loadModels(
        forProvider provider: String?,
        preferExistingSelection: Bool,
        forceRefresh: Bool
    ) async {
        guard let client = store.apiClient else {
            modelRefreshFailed = forceRefresh
            if forceRefresh { modelRefreshMessage = "Connect to a server before refreshing." }
            return
        }
        let targetProvider = provider ?? selectedProvider
        isLoadingModels = true
        defer { isLoadingModels = false }

        do {
            let catalog = try await client.getModelCatalog(refresh: forceRefresh)
            availableModels = catalog.data
            configuredProviders = catalog.providers ?? []
            store.availableModels = availableModels.map(\.id)
            addCurrentModelIfNeeded()
            let resolvedProvider = availableProviders.contains(targetProvider)
                ? targetProvider
                : (availableProviders.first ?? "")
            if selectedProvider != resolvedProvider {
                selectedProvider = resolvedProvider
                store.preferredProvider = resolvedProvider
            }
            selectCurrentModel(forProvider: resolvedProvider, preferExistingSelection: preferExistingSelection)
            modelRefreshFailed = false
        } catch {
            if forceRefresh {
                modelRefreshFailed = true
                modelRefreshMessage = "Refresh failed: \(error.localizedDescription)"
            } else {
                if availableModels.isEmpty {
                    addCurrentModelIfNeeded()
                    selectCurrentModel(forProvider: targetProvider, preferExistingSelection: preferExistingSelection)
                }
            }
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
        if selectedProvider.isEmpty || (!availableProviders.isEmpty && !availableProviders.contains(selectedProvider)) {
            selectedProvider = availableProviders.first ?? ""
        }

        if !store.preferredModel.isEmpty && models(for: selectedProvider).contains(where: { $0.id == store.preferredModel }) {
            selectedModel = store.preferredModel
        } else {
            selectCurrentModel(forProvider: selectedProvider, preferExistingSelection: true)
        }

        selectedThinking = store.preferredThinking
    }

    // MARK: - Helpers

    private func modelForSelection(_ id: String) -> ModelInfo? {
        availableModels.first(where: { $0.id == id })
    }

    private func models(for provider: String) -> [ModelInfo] {
        if provider.isEmpty { return availableModels }
        return availableModels.filter { model in
            modelBelongsToProvider(model, provider: provider)
        }
    }

    /// Provider is the configured inference service, not the model author.
    /// OpenRouter IDs are normally `author/model`, while `/v1/models` may
    /// report `owned_by` as the author. Treat every routed author ID as an
    /// OpenRouter model so selecting OpenRouter shows the complete catalog.
    private func modelBelongsToProvider(_ model: ModelInfo, provider: String) -> Bool {
        let id = model.id
        let prefix = providerFromModelID(id)?.lowercased()
        let owner = model.ownedBy?.lowercased()
        let reportedProvider = model.provider?.lowercased()

        if let reportedProvider, !reportedProvider.isEmpty {
            return reportedProvider == provider.lowercased()
        }

        switch provider {
        case "openrouter":
            // Older Hermes gateways expose the full OpenRouter catalog but
            // identify each row by model author in `owned_by` and omit the
            // normalized `provider` field. Since capabilities says the active
            // inference service is OpenRouter, all non-Hermes catalog rows are
            // routed through OpenRouter regardless of author prefix.
            return owner != "hermes"
        case "nous":
            return owner == "nous" || owner == "hermes" || id.hasPrefix("nous/")
        case "ollama-local":
            return owner == "ollama-local" || owner == "ollama" || id.hasPrefix("ollama/")
        case "opencode":
            return owner == "opencode" || id.hasPrefix("opencode/")
        case "opencode-zen":
            return owner == "opencode-zen" || id.hasPrefix("opencode-zen/")
        case "custom":
            return owner == "custom" || id.hasPrefix("custom/")
        default:
            return owner == provider || prefix == provider
        }
    }

    private func selectCurrentModel(forProvider provider: String, preferExistingSelection: Bool) {
        let providerModels = models(for: provider)

        // Always respect the store's saved preference first, even when
        // preferExistingSelection is false (e.g. provider changed but the
        // saved model is still valid for the new provider).
        if !store.preferredModel.isEmpty,
           providerModels.contains(where: { $0.id == store.preferredModel }) {
            selectedModel = store.preferredModel
            return
        }

        if preferExistingSelection,
           !selectedModel.isEmpty,
           providerModels.contains(where: { $0.id == selectedModel }) {
            store.preferredModel = selectedModel
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
        if let reportedName = configuredProviders.first(where: { $0.id == slug })?.name,
           !reportedName.isEmpty {
            return reportedName
        }
        switch slug {
        case "ollama-local": return "Ollama (local)"
        case "opencode-zen": return "OpenCode Zen"
        case "opencode-go": return "OpenCode Go"
        case "ollama-cloud": return "Ollama Cloud"
        case "openai-api": return "OpenAI"
        case "codex-oauth", "openai-codex": return "OpenAI Codex"
        case "github-copilot", "copilot": return "GitHub Copilot"
        case "kimi-coding": return "Kimi"
        case "qwen-oauth": return "Qwen"
        case "minimax-oauth": return "MiniMax OAuth"
        case "lmstudio": return "LM Studio"
        case "zai": return "Z.AI / GLM"
        case "xai": return "xAI / Grok"
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
