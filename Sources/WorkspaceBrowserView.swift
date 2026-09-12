import SwiftUI

enum WorkspaceSection: String, CaseIterable, Identifiable {
    case projects = "Projects", bots = "Bots", kanban = "Kanban"
    var id: Self { self }
    var icon: String {
        switch self {
        case .projects: "folder"
        case .bots: "person.2"
        case .kanban: "rectangle.split.3x1"
        }
    }
}

struct WorkspaceBrowserView: View {
    @ObservedObject var store: AppStore
    let section: WorkspaceSection
    var onSessionSelected: (() -> Void)? = nil

    var body: some View {
        if let client = store.apiClient {
            NavigationStack {
                content(client)
                    .navigationTitle(section.rawValue)
                    .navigationBarTitleDisplayMode(.inline)
            }
            // Navigation destinations and in-flight reads belong to one connection.
            .id(ObjectIdentifier(client))
        } else {
            ContentUnavailableView("Not Connected", systemImage: "network.slash")
        }
    }

    @ViewBuilder
    private func content(_ client: HermesAPIClient) -> some View {
        switch section {
        case .projects:
            WorkspaceReadView(load: { try await client.workspaceProjects() }) { snapshot in
                ForEach(snapshot.errors, id: \.profile) { error in
                    Label("\(error.profile): \(error.message)", systemImage: "exclamationmark.triangle")
                }
                if snapshot.groups.allSatisfy({ $0.projects.isEmpty }) && snapshot.errors.isEmpty {
                    ContentUnavailableView("No Server Projects", systemImage: "folder")
                }
                ForEach(snapshot.groups) { group in
                    Section(group.profile) {
                        ForEach(group.projects) { project in
                            NavigationLink {
                                projectDetail(project, profile: group.profile, client: client)
                            } label: {
                                WorkspaceRow(title: project.label, detail: project.path,
                                             trailing: "\(project.sessionCount)", icon: "folder")
                            }
                        }
                    }
                }
            }
        case .bots:
            WorkspaceReadView(load: { try await client.workspaceBots() }) { snapshot in
                if snapshot.profiles.isEmpty {
                    ContentUnavailableView("No Bots", systemImage: "person.2")
                }
                ForEach(snapshot.profiles) { bot in
                    NavigationLink {
                        List {
                            Section("Profile") {
                                LabeledContent("Name", value: bot.name)
                                if let value = bot.description, !value.isEmpty { Text(value) }
                                LabeledContent("Provider", value: bot.provider ?? "Not reported")
                                LabeledContent("Model", value: bot.model ?? "Not reported")
                                if let count = bot.skill_count { LabeledContent("Skills", value: "\(count)") }
                            }
                            if let session = bot.canonical_session ?? bot.last_session {
                                Section("Conversation") {
                                    Text(session.title ?? "Untitled")
                                    if let preview = session.preview, !preview.isEmpty { Text(preview) }
                                }
                            }
                        }
                        .navigationTitle(bot.title)
                    } label: {
                        WorkspaceRow(title: bot.title, detail: bot.model, trailing: nil, icon: "person.crop.circle")
                    }
                }
            }
        case .kanban:
            WorkspaceReadView(load: { try await client.workspaceBoards() }) { snapshot in
                if snapshot.boards.isEmpty {
                    ContentUnavailableView("No Kanban Boards", systemImage: section.icon)
                }
                ForEach(snapshot.boards) { board in
                    NavigationLink {
                        WorkspaceReadView(load: { try await client.workspaceBoard(slug: board.slug) }) { detail in
                            ForEach(detail.columns) { column in
                                Section("\(column.name.capitalized) (\(column.tasks.count))") {
                                    ForEach(column.tasks) { task in
                                        NavigationLink {
                                            List {
                                                Section { Text(task.title).font(.headline) }
                                                LabeledContent("Status", value: task.status)
                                                if let assignee = task.assignee { LabeledContent("Assignee", value: assignee) }
                                                if let body = task.body, !body.isEmpty { Section("Description") { Text(body) } }
                                                if let summary = task.latest_summary, !summary.isEmpty {
                                                    Section("Summary Preview") { Text(summary) }
                                                }
                                            }
                                            .navigationTitle("Task")
                                        } label: {
                                            WorkspaceRow(title: task.title, detail: task.assignee, trailing: nil, icon: "checklist")
                                        }
                                    }
                                }
                            }
                        }
                        .navigationTitle(board.title)
                    } label: {
                        WorkspaceRow(title: board.title, detail: board.project_name,
                                     trailing: board.total.map(String.init), icon: section.icon)
                    }
                }
            }
        }
    }

    private func projectDetail(_ project: ServerProject, profile: String, client: HermesAPIClient) -> some View {
        WorkspaceReadView(load: { try await client.workspaceProject(profile: profile, id: project.id) }) { detail in
            // Discovered empty repositories may not appear in the hydrated response.
            let current = detail.project ?? project
            ForEach(current.repos) { repo in
                Section(repo.label) {
                    if let path = repo.path { Text(path).font(.caption).foregroundStyle(.secondary) }
                    ForEach(repo.groups) { lane in
                        DisclosureGroup {
                            if let path = lane.path { Text(path).font(.caption).foregroundStyle(.secondary) }
                            ForEach(lane.sessions) { session in
                                // A profile's session ID must never be submitted to another profile.
                                if profile == "default",
                                   store.connectionConfig?.normalizedBaseURL.contains("/p/") != true,
                                   let known = store.sessions.first(where: { $0.id == session.id }) {
                                    Button {
                                        Task {
                                            await store.selectSession(known)
                                            guard store.apiClient === client else { return }
                                            onSessionSelected?()
                                        }
                                    } label: {
                                        Label(session.title ?? "Untitled", systemImage: "bubble.left")
                                    }
                                } else {
                                    Label(session.title ?? "Untitled", systemImage: "bubble.left")
                                }
                            }
                        } label: {
                            Text(lane.label)
                        }
                    }
                }
            }
            if current.repos.isEmpty {
                ContentUnavailableView("No Folders", systemImage: "folder")
            }
        }
        .navigationTitle(project.label)
    }
}

private struct WorkspaceRow: View {
    let title: String
    let detail: String?
    let trailing: String?
    let icon: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).frame(width: 22)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.body)
                if let detail, !detail.isEmpty {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let trailing { Text(trailing).font(.caption).foregroundStyle(.secondary) }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct WorkspaceReadView<Value, Content: View>: View {
    let load: () async throws -> Value
    @ViewBuilder let content: (Value) -> Content
    @Environment(\.scenePhase) private var scenePhase
    @State private var value: Value?
    @State private var error: String?
    @State private var requestID = UUID()

    var body: some View {
        List {
            if let error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                    Button("Retry") { Task { await refresh() } }
                }
            }
            if let value { content(value) }
            else if error == nil { ProgressView("Syncing with Hermes...") }
        }
        .refreshable { await refresh() }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            repeat {
                await refresh()
                do { try await Task.sleep(for: .seconds(30)) }
                catch { return }
            } while !Task.isCancelled
        }
    }

    @MainActor
    private func refresh() async {
        let id = UUID()
        requestID = id
        do {
            let next = try await load()
            guard !Task.isCancelled, requestID == id else { return }
            value = next
            error = nil
        } catch {
            guard !Task.isCancelled, requestID == id else { return }
            if case APIError.notFound = error {
                self.error = "This server does not expose the Companion workspace bridge."
            } else {
                self.error = "Workspace sync failed: \(error.localizedDescription)"
            }
        }
    }
}
