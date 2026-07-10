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
    @State private var isLoadingModels = false
    @State private var showingAddServer = false
    @State private var editingServer: ConnectionConfig?

    // Local working copies of picker selections, so the pickers don't
    // fight the parent's @Published when the user is mid-edit.
    @State private var selectedProvider: String = Self.knownProviders.first ?? ""
    @State private var selectedModel: String = ""
    @State private var selectedThinking: String = ""
    @State private var selectedServerURL: String = ""
    @State private var modelSearch: String = ""

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

    // MARK: - Provider card

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

    private var providerCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: theme.spacingM) {
                cardHeader("Provider", icon: "server.rack")

                Picker("Provider", selection: $selectedProvider) {
                    ForEach(availableProviders, id: \.self) { slug in
                        Text(displayName(for: slug))
                            .tag(slug)
                    }
                }
                .pickerStyle(.menu)
                .tint(theme.textPrimary)
                .onChange(of: selectedProvider) { _, newValue in
                    store.preferredProvider = newValue
                    Task {
                        await loadModels(forProvider: newValue, preferExistingSelection: false)
                    }
                }

                Text("Synced with macOS Hermes. The list of providers and their available models comes from the connected server.")
                    .font(.caption)
                    .foregroundStyle(theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Model card

    /// Models filtered to the selected provider, or all if no provider is set.
    private var modelsForSelectedProvider: [ModelInfo] {
        models(for: selectedProvider)
    }

    private var modelCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 0) {
                cardHeader("Model", icon: "cpu")

                if isLoadingModels {
                    ProgressView()
                        .padding(.vertical, theme.spacingM)
                } else if availableModels.isEmpty {
                    Text("No models available — connect to a server to load them.")
                        .font(.subheadline)
                        .foregroundStyle(theme.textSecondary)
                        .padding(.vertical, theme.spacingM)
                } else {
                    // Search bar
                    HStack(spacing: theme.spacingS) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(theme.textMuted)
                            .font(.system(size: 13, weight: .medium))
                        TextField("Search models...", text: $modelSearch)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .foregroundStyle(theme.textPrimary)
                        if !modelSearch.isEmpty {
                            Button {
                                modelSearch = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(theme.textMuted)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(theme.textMuted.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .padding(.top, theme.spacingM)
                    .padding(.horizontal, theme.spacingM)

                    // Scrollable list of rows (Claude iOS style)
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            // Favorites first
                            if !favoriteModelRows.isEmpty {
                                // Section header
                                HStack {
                                    Text("Favorites")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(theme.textSecondary)
                                    Spacer()
                                    Text("\(store.favoriteModels.count)/10")
                                        .font(.caption)
                                        .foregroundStyle(theme.textMuted)
                                }
                                .padding(.top, theme.spacingM)
                                .padding(.horizontal, theme.spacingM)

                                ForEach(favoriteModelRows) { model in
                                    modelRow(model, starred: true, active: store.preferredModel == model.id, theme: theme)
                                }
                            }

                            // All models (filtered by search)
                            HStack {
                                Text("All Models")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(theme.textSecondary)
                                Spacer()
                                Text("\(filteredAllModels.count)")
                                    .font(.caption)
                                    .foregroundStyle(theme.textMuted)
                            }
                            .padding(.top, theme.spacingM)
                            .padding(.horizontal, theme.spacingM)

                                if filteredAllModels.isEmpty {
                                    Text(modelSearch.isEmpty
                                          ? "No models loaded."
                                          : "No models match \(modelSearch).")
                                        .font(.subheadline)
                                        .foregroundStyle(theme.textMuted)
                                        .padding(.vertical, theme.spacingM)
                                } else {
                                ForEach(Array(filteredAllModels.prefix(50))) { model in
                                    modelRow(model, starred: store.favoriteModels.contains(model.id), active: store.preferredModel == model.id, theme: theme)
                                }
                                if filteredAllModels.count > 50 {
                                    Text("Showing 50 of \(filteredAllModels.count). Type more to narrow.")
                                        .font(.caption)
                                        .foregroundStyle(theme.textMuted)
                                        .padding(.vertical, theme.spacingM)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// Favorites that still resolve (plus dangling ids the gateway no longer lists).
    private var favoriteModelRows: [ModelInfo] {
        store.favoriteModels.map { id in
            if let known = availableModels.first(where: { $0.id == id }) {
                return known
            }
            let owner = providerFromModelID(id)
            return ModelInfo(id: id, ownedBy: owner)
        }
    }

    /// Full catalog, filtered by search text (id + ownedBy). Not limited by
    /// the Provider picker -- that filter was making favorites look empty when
    /// Hermes provider slugs (nous) don't match model owned_by (openrouter).
    private var filteredAllModels: [ModelInfo] {
        let q = modelSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base: [ModelInfo]
        if q.isEmpty {
            base = availableModels
        } else {
            base = availableModels.filter { model in
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
    
    /// Active/selected row helper (matches favoriteRow but shows checkmark instead of star)
    private func modelRow(_ model: ModelInfo, starred: Bool, active: Bool, theme: any HermesTheme) -> some View {
        HStack(spacing: theme.spacingM) {
            // Model icon placeholder
            Image(systemName: modelHasImages(model) ? "photo" : "cpu.fill")
                .font(.title3)
                .foregroundStyle(active ? theme.accent : (starred ? theme.accent : theme.textSecondary))
                .frame(width: 36)
            
            // Title + subtitle
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
            .padding(.leading, 4)
            
            Spacer(minLength: 0)
            
            // Active indicator or star
            if active {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.accent)
                    .frame(width: 36)
            } else {
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
        }
        .padding(.vertical, 4)
        .background(active ? theme.bgSurfaceAlt.opacity(0.5) : .clear)
        .cornerRadius(10)
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
            if let owner = model.ownedBy, owner == provider {
                return true
            }
            return providerFromModelID(model.id) == provider
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
