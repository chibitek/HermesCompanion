import SwiftUI

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
                if let failure = store.skillsError {
                    Section {
                        Label(failure, systemImage: "exclamationmark.triangle")
                        Button("Retry") { Task { await store.refreshSkills() } }
                    }
                }
                if filteredSkills.isEmpty && store.skillsError == nil {
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
        .task { await store.refreshSkills() }
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
