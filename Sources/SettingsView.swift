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

    /// Favorites that resolve for the selected inference provider, plus
    /// dangling ids the gateway no longer reports.
    private var favoriteModelRows: [ModelInfo] {
        store.favoriteModels.compactMap { id in
            let model: ModelInfo
            if let known = availableModels.first(where: { $0.id == id }) {
                model = known
            } else {
                model = ModelInfo(id: id, ownedBy: providerFromModelID(id))
            }
            return selectedProvider.isEmpty || modelBelongsToProvider(model, provider: selectedProvider)
                ? model
                : nil
        }
    }

    /// Full catalog, filtered by search text (id + ownedBy). Not limited by
    /// the Provider picker -- that filter was making favorites look empty when
    /// Hermes provider slugs (nous) don't match model owned_by (openrouter).
    private var filteredAllModels: [ModelInfo] {
        let q = modelSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let providerModels = models(for: selectedProvider)
        let base: [ModelInfo]
        if q.isEmpty {
            base = providerModels
        } else {
            base = providerModels.filter { model in
                model.id.lowercased().contains(q)
                    || (model.ownedBy?.lowercased().contains(q) ?? false)
                    || displayName(for: model).lowercased().contains(q)
            }
        }
        // Favorites first, then the rest alphabetically by display name
        let favSet = Set(store.favoriteModels)
        return base.sorted { a, b in
            let af = favSet.contains(a.id)
            let bf = favSet.contains(b.id)
            if af != bf { return af && !bf }
            return displayName(for: a).localizedCaseInsensitiveCompare(displayName(for: b)) == .orderedAscending
        }
    }

    @ViewBuilder
    private func favoriteRow(_ model: ModelInfo, starred: Bool) -> some View {
        HStack(spacing: theme.spacingM) {
            // Model icon placeholder (can be extended later)
            Image(systemName: modelHasImages(model) ? "photo" : "cpu.fill")
                .font(.title3)
                .foregroundStyle(starred ? theme.accent : theme.textSecondary)
                .frame(width: 36)
            
            // Title + subtitle
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName(for: model))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                Text(modelSubtitle(model))
                    .font(.caption)
                    .foregroundStyle(theme.textMuted)
                    .lineLimit(1)
            }
            .padding(.leading, 4)
            
            Spacer(minLength: 0)
            
            // Star on the right (dedicated button)
            Button {
                _ = store.toggleFavorite(model.id)
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
            } label: {
                Image(systemName: starred ? "star.fill" : "star")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(starred ? .yellow : theme.textMuted)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(starred ? "Remove from favorites" : "Add to favorites")
        }
        .padding(.vertical, 4)
    }
    
    /// Model row with separate selection and favorite controls so tapping the
    /// star never changes the active model.
    private func modelRow(_ model: ModelInfo, starred: Bool, active: Bool, theme: any HermesTheme) -> some View {
        HStack(spacing: theme.spacingS) {
            Button {
                selectedModel = model.id
                store.selectPreferredModel(model.id)
            } label: {
                HStack(spacing: theme.spacingM) {
                    Image(systemName: modelHasImages(model) ? "photo" : "cpu.fill")
                        .font(.title3)
                        .foregroundStyle(active ? theme.accent : (starred ? theme.accent : theme.textSecondary))
                        .frame(width: 36)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(displayName(for: model))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(active ? theme.accent : theme.textPrimary)
                            .lineLimit(1)
                        Text(modelSubtitle(model))
                            .font(.caption)
                            .foregroundStyle(theme.textMuted)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    if active {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(theme.accent)
                            .frame(width: 24)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                _ = store.toggleFavorite(model.id)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Image(systemName: starred ? "star.fill" : "star")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(starred ? .yellow : theme.textMuted)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(starred ? "Remove from favorites" : "Add to favorites")
        }
        .padding(.vertical, 4)
        .background(active ? theme.bgSurfaceAlt.opacity(0.5) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, theme.spacingM)
    }
    
    private func modelHasImages(_ model: ModelInfo) -> Bool {
        // Placeholder for future icon image support
        return false
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

    private func pickerLabel(for model: ModelInfo) -> String {
        let name = displayName(for: model)
        if let owner = model.ownedBy, !owner.isEmpty {
            return "\(name) · \(displayName(for: owner))"
        }
        return name
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

    private func settingRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(theme.textSecondary)
            Spacer()
            Text(value)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

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

// MARK: - Claude-style provider selection

private struct ProviderSelectionView: View {
    let providers: [String]
    @Binding var selectedProvider: String
    let modelCount: (String) -> Int
    let displayName: (String) -> String

    @EnvironmentObject private var appearance: AppearanceSettings
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var theme: any HermesTheme { appearance.activeTheme }
    private var filteredProviders: [String] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return providers }
        return providers.filter { provider in
            provider.localizedCaseInsensitiveContains(query)
                || displayName(provider).localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        ZStack {
            theme.backgroundView.ignoresSafeArea()

            List {
                Section {
                    ForEach(filteredProviders, id: \.self) { provider in
                        Button {
                            selectedProvider = provider
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: providerIcon(provider))
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(selectedProvider == provider ? theme.accent : theme.textSecondary)
                                    .frame(width: 34, height: 34)
                                    .background(theme.accent.opacity(selectedProvider == provider ? 0.16 : 0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(displayName(provider))
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(theme.textPrimary)
                                    let count = modelCount(provider)
                                    Text(count == 1 ? "1 model" : "\(count) models")
                                        .font(.caption)
                                        .foregroundStyle(theme.textMuted)
                                }

                                Spacer()

                                if selectedProvider == provider {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(theme.accent)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(AnyView(theme.glassCard(cornerRadius: 0)))
                    }
                } header: {
                    Text("Inference Provider")
                        .foregroundStyle(theme.textSecondary)
                } footer: {
                    Text("Only providers backed by an active subscription, OAuth login, API key, or configured local endpoint are shown.")
                        .foregroundStyle(theme.textMuted)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Provider")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search providers")
    }

    private func providerIcon(_ provider: String) -> String {
        switch provider {
        case "ollama-local", "lmstudio": return "desktopcomputer"
        case "ollama-cloud", "openrouter", "nous": return "cloud"
        case "anthropic", "openai-api", "gemini", "xai": return "sparkles"
        case "github-copilot", "copilot", "codex-oauth", "openai-codex", "qwen-oauth", "minimax-oauth": return "person.badge.key"
        default: return "server.rack"
        }
    }
}

// MARK: - Claude-style model selection

private struct ModelSelectionView: View {
    let provider: String
    let models: [ModelInfo]
    @Binding var selectedModel: String
    let favoriteModels: [String]
    let isLoading: Bool
    let refreshMessage: String?
    let refreshFailed: Bool
    let displayName: (ModelInfo) -> String
    let subtitle: (ModelInfo) -> String
    let onSelect: (ModelInfo) -> Void
    let onToggleFavorite: (ModelInfo) -> Void
    let onRefresh: () async -> Void

    @EnvironmentObject private var appearance: AppearanceSettings
    @State private var searchText = ""

    private var theme: any HermesTheme { appearance.activeTheme }
    private var favoriteSet: Set<String> { Set(favoriteModels) }
    private var filteredModels: [ModelInfo] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base = query.isEmpty ? models : models.filter { model in
            model.id.lowercased().contains(query)
                || displayName(model).lowercased().contains(query)
                || subtitle(model).lowercased().contains(query)
        }
        return base.sorted { left, right in
            let leftFavorite = favoriteSet.contains(left.id)
            let rightFavorite = favoriteSet.contains(right.id)
            if leftFavorite != rightFavorite { return leftFavorite && !rightFavorite }
            return displayName(left).localizedCaseInsensitiveCompare(displayName(right)) == .orderedAscending
        }
    }

    var body: some View {
        ZStack {
            theme.backgroundView.ignoresSafeArea()

            List {
                if isLoading && models.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView("Refreshing models...")
                            .foregroundStyle(theme.textSecondary)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                } else if filteredModels.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "No Models for \(providerDisplayName)" : "No Matching Models",
                        systemImage: "cpu",
                        description: Text(searchText.isEmpty
                                          ? "Tap Refresh to ask the connected Hermes server for this provider's models."
                                          : "Try another model name.")
                    )
                    .foregroundStyle(theme.textSecondary)
                    .listRowBackground(Color.clear)
                } else {
                    Section {
                        ForEach(filteredModels) { model in
                            modelRow(model)
                                .listRowBackground(AnyView(theme.glassCard(cornerRadius: 0)))
                        }
                    } header: {
                        HStack {
                            Text(providerDisplayName)
                            Spacer()
                            Text("\(filteredModels.count)")
                        }
                        .foregroundStyle(theme.textSecondary)
                    }
                }

                if let refreshMessage, !refreshMessage.isEmpty {
                    Section {
                        Text(refreshMessage)
                            .font(.caption)
                            .foregroundStyle(refreshFailed ? theme.danger : theme.textMuted)
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Models")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search \(providerDisplayName) models")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await onRefresh() }
                } label: {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(theme.accent)
                    }
                }
                .disabled(isLoading)
                .accessibilityLabel("Refresh models")
            }
        }
    }

    private func modelRow(_ model: ModelInfo) -> some View {
        let isSelected = selectedModel == model.id
        let isFavorite = favoriteSet.contains(model.id)

        return HStack(spacing: 10) {
            Button {
                selectedModel = model.id
                onSelect(model)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "cpu")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(isSelected ? theme.accent : theme.textSecondary)
                        .frame(width: 34, height: 34)
                        .background(theme.accent.opacity(isSelected ? 0.16 : 0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(displayName(model))
                            .font(.body.weight(.medium))
                            .foregroundStyle(isSelected ? theme.accent : theme.textPrimary)
                            .lineLimit(1)
                        Text(model.id)
                            .font(.caption)
                            .foregroundStyle(theme.textMuted)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(theme.accent)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                onToggleFavorite(model)
            } label: {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isFavorite ? .yellow : theme.textMuted)
                    .frame(width: 38, height: 38)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isFavorite ? "Remove from favorites" : "Add to favorites")
        }
        .padding(.vertical, 3)
    }

    private var providerDisplayName: String {
        switch provider {
        case "openrouter": return "OpenRouter"
        case "ollama-local": return "Ollama (local)"
        case "ollama-cloud": return "Ollama Cloud"
        case "opencode-zen": return "OpenCode Zen"
        case "opencode-go": return "OpenCode Go"
        case "openai-api": return "OpenAI"
        case "codex-oauth", "openai-codex": return "OpenAI Codex"
        case "github-copilot", "copilot": return "GitHub Copilot"
        case "kimi-coding": return "Kimi"
        case "qwen-oauth": return "Qwen"
        default: return provider.capitalized
        }
    }
}

// MARK: - Skills List View

struct SkillsListView: View {
    @ObservedObject var store: AppStore
    @EnvironmentObject var appearance: AppearanceSettings
    @State private var searchText = ""

    private var theme: any HermesTheme { appearance.activeTheme }

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
            theme.backgroundView
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
                                .foregroundStyle(theme.textPrimary)
                            if let desc = skill.description {
                                Text(desc)
                                    .font(.caption)
                                    .foregroundStyle(theme.textSecondary)
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
                        .foregroundStyle(theme.accent)
                }
            }
        }
    }
}

// MARK: - Toolsets List View

struct ToolsetsListView: View {
    @ObservedObject var store: AppStore
    @EnvironmentObject var appearance: AppearanceSettings
    @State private var searchText = ""

    private var theme: any HermesTheme { appearance.activeTheme }

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
        ZStack {
            theme.backgroundView
                .ignoresSafeArea()

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
                                        .foregroundStyle(theme.textPrimary)
                                    Text(toolset.name)
                                        .font(.caption2)
                                        .foregroundStyle(theme.textSecondary)
                                }
                                Spacer()
                                Label(toolset.enabled ? "Enabled" : "Disabled",
                                      systemImage: toolset.enabled ? "checkmark.circle.fill" : "circle")
                                    .labelStyle(.iconOnly)
                                    .foregroundStyle(toolset.enabled ? theme.accent : theme.textMuted)
                            }

                            Text(toolset.description)
                                .font(.caption)
                                .foregroundStyle(theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)

                            if !toolset.tools.isEmpty {
                                Text(toolset.tools.joined(separator: ", "))
                                    .font(.caption2)
                                    .foregroundStyle(theme.textMuted)
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
        .navigationTitle("Toolsets")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search toolsets")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await store.refreshToolsets() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(theme.accent)
                }
            }
        }
        .task {
            await store.refreshToolsets()
        }
    }
}
