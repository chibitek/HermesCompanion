import SwiftUI

/// Compact model picker sheet shown from the chat input bar.
/// Layout: Favorites section first, then a scrollable provider list.
/// Tapping a provider shows that provider's models (favorites pinned to top).
struct InputModelPicker: View {
    let currentModel: String
    let availableModels: [String]
    let favoriteModels: [String]
    let modelInfos: [String: ModelInfo]
    let onSelect: (String) -> Void
    var onToggleFavorite: ((String) -> Void)? = nil

    @EnvironmentObject private var appearance: AppearanceSettings
    @Environment(\.dismiss) private var dismiss
    @State private var selectedProvider: String?
    @State private var searchText = ""

    private var theme: any HermesTheme { appearance.activeTheme }
    private var favoriteSet: Set<String> { Set(favoriteModels) }

    /// Favorites that are either in the available list or the current model.
    private var validFavorites: [String] {
        favoriteModels.filter { availableModels.contains($0) || $0 == currentModel }
    }

    /// Resolve the source (provider) for a model.
    /// Uses the server-reported provider from ModelInfo, falling back to
    /// the model ID prefix (e.g. "openai/gpt-4" -> "openai"), then "Other".
    private func sourceOf(_ model: String) -> String {
        if let info = modelInfos[model], let provider = info.provider, !provider.isEmpty {
            return provider
        }
        if let info = modelInfos[model], let owned = info.ownedBy, !owned.isEmpty {
            return owned
        }
        return ProviderUtils.providerOf(model) ?? "Other"
    }

    /// All sources that have available models.
    private var allProviders: [String] {
        var seen = Set<String>()
        var result: [String] = []

        for model in availableModels {
            let prov = sourceOf(model)
            if seen.insert(prov).inserted {
                result.append(prov)
            }
        }
        return result.sorted()
    }

    /// Models for the selected provider — all models, favorites sorted first.
    /// If searching, filter by query.
    private var filteredModels: [String] {
        guard let provider = selectedProvider else { return [] }
        let providerModels = availableModels.filter { sourceOf($0) == provider }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base = query.isEmpty ? providerModels : providerModels.filter {
            $0.lowercased().contains(query) || ProviderUtils.shortModelName($0).lowercased().contains(query)
        }
        // Sort: favorites first, then alphabetical
        return base.sorted { a, b in
            let aFav = favoriteSet.contains(a)
            let bFav = favoriteSet.contains(b)
            if aFav != bFav { return aFav && !bFav }
            return ProviderUtils.shortModelName(a).localizedCaseInsensitiveCompare(ProviderUtils.shortModelName(b)) == .orderedAscending
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                theme.backgroundView.ignoresSafeArea()

                if selectedProvider == nil {
                    // First screen: favorites + provider list
                    providerList
                } else {
                    // Second screen: models for selected provider
                    modelList
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Provider List (first screen)

    private var providerList: some View {
        List {
            // Favorites section — only show if user has favorites
            if !validFavorites.isEmpty {
                Section {
                    ForEach(validFavorites, id: \.self) { model in
                        modelRow(model)
                    }
                } header: {
                    HStack {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                            .font(.caption)
                        Text("Favorites")
                            .foregroundStyle(theme.textSecondary)
                    }
                }
            }

            // Providers section
            Section {
                ForEach(allProviders, id: \.self) { provider in
                    Button {
                        selectedProvider = provider
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: providerIcon(provider))
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(theme.accent)
                                .frame(width: 34, height: 34)
                                .background(theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(providerDisplayName(provider))
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(theme.textPrimary)
                                let count = availableModels.filter { sourceOf($0) == provider }.count
                                Text(count == 1 ? "1 model" : "\(count) models")
                                    .font(.caption)
                                    .foregroundStyle(theme.textMuted)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(theme.textMuted)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Sources")
                    .foregroundStyle(theme.textSecondary)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .navigationTitle("Select Model")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
                    .foregroundStyle(theme.accent)
            }
        }
    }

    // MARK: - Model List (second screen)

    private var modelList: some View {
        List {
            // Favorites for this provider
            let providerFavorites = filteredModels.filter { favoriteSet.contains($0) }
            let nonFavorites = filteredModels.filter { !favoriteSet.contains($0) }

            if !providerFavorites.isEmpty {
                Section {
                    ForEach(providerFavorites, id: \.self) { model in
                        modelRow(model)
                    }
                } header: {
                    HStack {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                            .font(.caption)
                        Text("Favorites")
                            .foregroundStyle(theme.textSecondary)
                    }
                }
            }

            if !nonFavorites.isEmpty {
                Section {
                    ForEach(nonFavorites, id: \.self) { model in
                        modelRow(model)
                    }
                } header: {
                    HStack {
                        Text(providerDisplayName(selectedProvider ?? ""))
                        Spacer()
                        Text("\(filteredModels.count)")
                    }
                    .foregroundStyle(theme.textSecondary)
                }
            }

            if filteredModels.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "No Models" : "No Matching Models",
                    systemImage: "cpu"
                )
                .foregroundStyle(theme.textSecondary)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .navigationTitle(providerDisplayName(selectedProvider ?? ""))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search models")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    selectedProvider = nil
                    searchText = ""
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .foregroundStyle(theme.accent)
                }
            }
        }
    }

    // MARK: - Model Row

    private func modelRow(_ model: String) -> some View {
        let isSelected = model == currentModel
        let isFavorite = favoriteSet.contains(model)

        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onSelect(model)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "cpu")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isSelected ? theme.accent : theme.textSecondary)
                    .frame(width: 34, height: 34)
                    .background(theme.accent.opacity(isSelected ? 0.16 : 0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(ProviderUtils.shortModelName(model))
                        .font(.body.weight(.medium))
                        .foregroundStyle(isSelected ? theme.accent : theme.textPrimary)
                        .lineLimit(1)
                    Text(model)
                        .font(.caption)
                        .foregroundStyle(theme.textMuted)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                // Star/unstar button
                if let onToggleFavorite {
                    Button {
                        onToggleFavorite(model)
                    } label: {
                        Image(systemName: isFavorite ? "star.fill" : "star")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(isFavorite ? .yellow : theme.textMuted)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isFavorite ? "Remove from favorites" : "Add to favorites")
                } else if isFavorite {
                    Image(systemName: "star.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.yellow)
                }

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(theme.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func providerIcon(_ provider: String) -> String { ProviderUtils.icon(for: provider) }

    private func providerDisplayName(_ provider: String) -> String { ProviderUtils.displayName(for: provider) }
}
