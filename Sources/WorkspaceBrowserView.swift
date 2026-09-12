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
                        WorkspaceReadView(load: { try await client.workspaceBots() }) { current in
                            if let bot = current.profile(named: bot.name) {
                                Section("Profile") {
                                    LabeledContent("Name", value: bot.name)
                                    if let value = bot.description, !value.isEmpty { Text(value) }
                                    LabeledContent("Provider", value: bot.provider ?? "Not reported")
                                    LabeledContent("Model", value: bot.model ?? "Not reported")
                                    if let count = bot.skill_count { LabeledContent("Skills", value: "\(count)") }
                                }
                                if let session = bot.canonical_session {
                                    Section("Conversation") {
                                        Text(session.title ?? "Untitled")
                                        if let preview = session.preview, !preview.isEmpty { Text(preview) }
                                    }
                                }
                                NavigationLink {
                                    BotHistoryView(client: client, bot: bot)
                                } label: {
                                    Label("Conversation History", systemImage: "bubble.left.and.bubble.right")
                                }
                            } else {
                                ContentUnavailableView("Bot No Longer Available", systemImage: "person.crop.circle.badge.questionmark")
                            }
                        }
                        .navigationTitle(bot.name)
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
                                            ServerTaskDetailView(client: client, board: board.slug, taskID: task.id)
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
                                    NavigationLink {
                                        WorkspaceHistoryView(title: session.title ?? "Untitled", identity: "\(profile):\(session.id)") { offset in
                                            try await client.projectHistory(profile: profile, projectID: project.id,
                                                                            sessionID: session.id, offset: offset)
                                        }
                                    } label: {
                                        Label(session.title ?? "Untitled", systemImage: "bubble.left")
                                    }
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

private struct ServerTaskDetailView: View {
    let client: HermesAPIClient
    let board: String
    let taskID: String

    var body: some View {
        WorkspaceReadView(load: { try await client.workspaceTask(board: board, id: taskID) }) { detail in
            Section {
                Text(detail.task.title).font(.headline)
                LabeledContent("Status", value: detail.task.status)
                if let assignee = detail.task.assignee { LabeledContent("Assignee", value: assignee) }
            }
            if let body = detail.task.body, !body.isEmpty { Section("Description") { Text(body) } }
            if let summary = detail.task.latest_summary, !summary.isEmpty {
                Section("Summary") { Text(summary) }
            }
            if let result = detail.task.result, !result.isEmpty { Section("Result") { Text(result) } }
            if let links = detail.links {
                if !links.parents.isEmpty {
                    Section("Dependencies") {
                        ForEach(links.parents, id: \.self) { parentID in
                            NavigationLink {
                                ServerTaskDetailView(client: client, board: board, taskID: parentID)
                            } label: {
                                Label(parentID, systemImage: "arrow.up.forward")
                            }
                        }
                    }
                }
                if !links.children.isEmpty {
                    Section("Child Tasks (\(links.children.count))") {
                        ForEach(links.children, id: \.self) { childID in
                            let child = detail.child_results?.first { $0.id == childID }
                            NavigationLink {
                                ServerTaskDetailView(client: client, board: board, taskID: childID)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(child?.title ?? childID)
                                    if let child {
                                        Text(child.status).font(.caption).foregroundStyle(.secondary)
                                        if let summary = child.latest_summary ?? child.result, !summary.isEmpty {
                                            Text(summary).font(.callout)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            Section("Comments (\(detail.comments.count))") {
                ForEach(detail.comments) { comment in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(comment.author).font(.headline)
                        Text(Date(timeIntervalSince1970: comment.created_at), style: .date)
                            .font(.caption).foregroundStyle(.secondary)
                        Text(comment.body)
                    }
                }
            }
            Section("Runs (\(detail.runs.count))") {
                ForEach(detail.runs) { run in
                    DisclosureGroup {
                        if let profile = run.profile { LabeledContent("Profile", value: profile) }
                        if let outcome = run.outcome { LabeledContent("Outcome", value: outcome) }
                        if let summary = run.summary, !summary.isEmpty { Text(summary) }
                        if let error = run.error, !error.isEmpty {
                            Label(error, systemImage: "exclamationmark.triangle")
                        }
                    } label: {
                        VStack(alignment: .leading) {
                            Text("#\(run.id) \(run.status)")
                            Text(Date(timeIntervalSince1970: run.started_at), style: .date)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .textSelection(.enabled)
        .navigationTitle("Task")
        .navigationBarTitleDisplayMode(.inline)
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

struct WorkspaceReadView<Value, Content: View>: View {
    let load: () async throws -> Value
    var refreshAutomatically = true
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
                guard refreshAutomatically else { return }
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
            // Do not leave removed server resources actionable beneath a sync error.
            value = nil
            if case APIError.notFound = error {
                self.error = "This workspace endpoint is unavailable on the server."
            } else {
                self.error = "Workspace sync failed: \(error.localizedDescription)"
            }
        }
    }
}
