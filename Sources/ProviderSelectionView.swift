import SwiftUI

// MARK: - Claude-style provider selection

struct ProviderSelectionView: View {
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
                                Image(systemName: ProviderUtils.icon(for: provider))
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
        .navigationTitle("Source")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search providers")
    }
}
