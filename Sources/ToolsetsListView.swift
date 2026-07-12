import SwiftUI

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
