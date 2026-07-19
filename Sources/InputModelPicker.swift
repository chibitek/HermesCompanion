import SwiftUI

/// Model picker: shows unique model names (deduplicated across sources).
/// Tap a model to see which sources serve it, then pick a source.
struct InputModelPicker: View {
    let currentModel: String
    let availableModels: [String]
    let favoriteModels: [String]
    let modelInfos: [String: ModelInfo]
    let onSelect: (String) -> Void
    var onToggleFavorite: ((String) -> Void)? = nil

    @EnvironmentObject private var appearance: AppearanceSettings
    @Environment(\.dismiss) private var dismiss
    @State private var selectedModelName: String?
    @State private var searchText = ""

    private var theme: any HermesTheme { appearance.activeTheme }
    private var favoriteSet: Set<String> { Set(favoriteModels) }

    // MARK: - Deduplication

    /// All unique model names (short names), deduplicated across sources.
    /// Each name maps to the list of model IDs that share it.
    private var uniqueModels: [(name: String, ids: [String])] {
        var groups: [String: [String]] = [:]
        for model in availableModels {
            let name = ProviderUtils.shortModelName(model)
            groups[name, default: []].append(model)
        }
        return groups.map { (name: $0.key, ids: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Sources for a given model name (deduplicated).
    private func sourcesFor(_ name: String) -> [(id: String, provider: String)] {
        let ids = uniqueModels.first { $0.name == name }?.ids ?? []
        return ids.map { (id: $0, provider: sourceOf($0)) }
            .sorted { ProviderUtils.displayName(for: $0.provider).localizedCaseInsensitiveCompare(ProviderUtils.displayName(for: $1.provider)) == .orderedAscending }
    }

    // MARK: - Source resolution

    private func sourceOf(_ model: String) -> String {
        if let info = modelInfos[model], let provider = info.provider, !provider.isEmpty {
            return provider
        }
        if let info = modelInfos[model], let owned = info.ownedBy, !owned.isEmpty {
            return owned
        }
        return ProviderUtils.providerOf(model) ?? "Other"
    }

    // MARK: - Search

    private var filteredUnique: [(name: String, ids: [String])] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return uniqueModels }
        return uniqueModels.filter { $0.name.lowercased().contains(query) }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                theme.backgroundView.ignoresSafeArea()

                if selectedModelName == nil {
                    modelList
                } else {
                    sourceList
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Screen 1: Model list

    private var modelList: some View {
        List {
            // Favorites — deduplicated by name, show first
            let favNames = filteredUnique.filter { name, ids in
                ids.contains { favoriteSet.contains($0) }
            }
            let otherNames = filteredUnique.filter { name, ids in
                !ids.contains { favoriteSet.contains($0) }
            }

            if !favNames.isEmpty {
                Section {
                    ForEach(favNames, id: \.name) { entry in
                        modelRow(entry)
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

            if !otherNames.isEmpty {
                Section {
                    ForEach(otherNames, id: \.name) { entry in
                        modelRow(entry)
                    }
                } header: {
                    HStack {
                        Text("Models")
                        Spacer()
                        Text("\(filteredUnique.count)")
                    }
                    .foregroundStyle(theme.textSecondary)
                }
            }

            if filteredUnique.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "No Models" : "No Matching Models",
                    systemImage: "cpu"
                )
                .foregroundStyle(theme.textSecondary)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .navigationTitle("Select Model")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search models")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
                    .foregroundStyle(theme.accent)
            }
        }
    }

    // MARK: - Screen 2: Source list for a model

    private var sourceList: some View {
        List {
            if let name = selectedModelName {
                let sources = sourcesFor(name)
                ForEach(sources, id: \.id) { source in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onSelect(source.id)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: ProviderUtils.icon(for: source.provider))
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(theme.accent)
                                .frame(width: 34, height: 34)
                                .background(theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(ProviderUtils.displayName(for: source.provider))
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(theme.textPrimary)
                                Text(source.id)
                                    .font(.caption)
                                    .foregroundStyle(theme.textMuted)
                                    .lineLimit(1)
                            }

                            Spacer()

                            if source.id == currentModel {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(theme.accent)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .navigationTitle(selectedModelName ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    selectedModelName = nil
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

    private func modelRow(_ entry: (name: String, ids: [String])) -> some View {
        let isFavorite = entry.ids.contains { favoriteSet.contains($0) }
        let isSelected = entry.ids.contains { $0 == currentModel }
        let sourceCount = entry.ids.count

        return Button {
            if sourceCount == 1 {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onSelect(entry.ids[0])
                dismiss()
            } else {
                selectedModelName = entry.name
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "cpu")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isSelected ? theme.accent : theme.textSecondary)
                    .frame(width: 34, height: 34)
                    .background(theme.accent.opacity(isSelected ? 0.16 : 0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(isSelected ? theme.accent : theme.textPrimary)
                        .lineLimit(1)
                    if sourceCount > 1 {
                        Text("\(sourceCount) sources")
                            .font(.caption)
                            .foregroundStyle(theme.textMuted)
                    } else {
                        Text(entry.ids[0])
                            .font(.caption)
                            .foregroundStyle(theme.textMuted)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                // Star — onTapGesture to avoid nested-button issue
                if let onToggleFavorite {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isFavorite ? .yellow : theme.textMuted)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            // ponytail: favorite the first id for this name
                            onToggleFavorite(entry.ids[0])
                        }
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

                if sourceCount > 1 {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(theme.textMuted)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
