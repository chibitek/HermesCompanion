import SwiftUI

// MARK: - Claude-style model selection

struct ModelSelectionView: View {
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
