import SwiftUI

private struct WorkspaceRevisionKey: EnvironmentKey { static let defaultValue = 0 }
extension EnvironmentValues {
    var workspaceRevision: Int {
        get { self[WorkspaceRevisionKey.self] }
        set { self[WorkspaceRevisionKey.self] = newValue }
    }
}
import QuickLook

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
            .toolbar {
                NavigationLink {
                    ProjectManagementView(client: client)
                } label: { Label("Manage Projects", systemImage: "folder.badge.gearshape") }
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
                                if let config = store.connectionConfig {
                                    NavigationLink {
                                        BotChatAccessView(rootClient: client, rootConfig: config, bot: bot)
                                    } label: {
                                        Label("Chat with Bot", systemImage: "bubble.left.and.text.bubble.right")
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
            ServerBoardsView(client: client)
        }
    }

    private func projectDetail(_ project: ServerProject, profile: String, client: HermesAPIClient) -> some View {
        WorkspaceReadView(load: { try await client.workspaceProject(profile: profile, id: project.id) }) { detail in
            if let current = detail.project {
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
            } else {
                ContentUnavailableView("Project Unavailable", systemImage: "folder.badge.questionmark",
                                       description: Text("Hermes did not return this project in its current folder tree."))
            }
        }
        .navigationTitle(project.label)
    }
}

private struct ServerBoardView: View {
    let client: HermesAPIClient
    let board: ServerBoard
    @State private var showCreate = false
    @State private var revision = 0
    @State private var notice: String?

    var body: some View {
        WorkspaceReadView(load: { try await client.workspaceBoard(slug: board.slug) }) { detail in
            if let notice { Text(notice).foregroundStyle(.secondary) }
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
        .id(revision)
        .navigationTitle(board.title)
        .toolbar { Button("New Task", systemImage: "plus") { showCreate = true } }
        .sheet(isPresented: $showCreate) {
            ServerTaskEditorView(client: client, board: board.slug) { receipt in
                notice = receipt.warning
                revision += 1
            }
        }
    }
}

private struct ServerTaskDetailView: View {
    let client: HermesAPIClient
    let board: String
    let taskID: String
    @State private var previewURL: URL?
    @State private var downloadedURL: URL?
    @State private var downloadError: String?
    @State private var downloadTask: Task<Void, Never>?
    @State private var downloadID = UUID()
    @State private var editingTask: ServerBoardTask?
    @State private var showComment = false
    @State private var mutationRevision = 0
    @State private var mutationNotice: String?

    var body: some View {
        WorkspaceReadView(load: { try await client.workspaceTask(board: board, id: taskID) }) { detail in
            if let mutationNotice { Text(mutationNotice).foregroundStyle(.secondary) }
            if let downloadError {
                Label(downloadError, systemImage: "exclamationmark.triangle")
            }
            Section {
                Text(detail.task.title).font(.headline)
                Button("Edit Task") { editingTask = detail.task }
                LabeledContent("Status", value: detail.task.status)
                if let assignee = detail.task.assignee { LabeledContent("Assignee", value: assignee) }
            }
            if let body = detail.task.body, !body.isEmpty { Section("Description") { Text(body) } }
            if let summary = detail.task.latest_summary, !summary.isEmpty {
                Section("Summary") { Text(summary) }
            }
            if let result = detail.task.result, !result.isEmpty { Section("Result") { Text(result) } }
            if let attachments = detail.attachments, !attachments.isEmpty {
                Section("Attachments") {
                    ForEach(attachments) { attachment in
                        Button {
                            download(attachment)
                        } label: {
                            Label {
                                VStack(alignment: .leading) {
                                    Text(attachment.filename)
                                    Text(ByteCountFormatter.string(fromByteCount: Int64(attachment.size), countStyle: .file))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            } icon: { Image(systemName: "arrow.down.doc") }
                        }
                        .disabled(downloadTask != nil)
                    }
                    if downloadTask != nil { ProgressView("Downloading...") }
                }
            }
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
                Button("Add Comment") { showComment = true }
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
        .id(mutationRevision)
        .sheet(item: $editingTask) { task in
            ServerTaskEditorView(client: client, board: board, existing: task) { receipt in
                mutationNotice = receipt.warning
                mutationRevision += 1
            }
        }
        .sheet(isPresented: $showComment) {
            ServerTaskCommentView(client: client, board: board, taskID: taskID) {
                mutationRevision += 1
            }
        }
        .textSelection(.enabled)
        .navigationTitle("Task")
        .navigationBarTitleDisplayMode(.inline)
        .quickLookPreview($previewURL)
        .onChange(of: previewURL) { _, url in
            if url == nil { clearDownload() }
        }
        .onDisappear {
            downloadID = UUID()
            downloadTask?.cancel()
            downloadTask = nil
            if previewURL == nil { clearDownload() }
        }
    }

    private func clearDownload() {
        if let downloadedURL { try? FileManager.default.removeItem(at: downloadedURL.deletingLastPathComponent()) }
        downloadedURL = nil
    }

    private func download(_ attachment: ServerTaskAttachment) {
        downloadError = nil
        clearDownload()
        let requestID = UUID()
        downloadID = requestID
        downloadTask = Task { @MainActor in
            defer { if downloadID == requestID { downloadTask = nil } }
            do {
                let file = try await client.downloadTaskAttachment(board: board, taskID: taskID, attachment: attachment)
                guard !Task.isCancelled, downloadID == requestID else {
                    try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
                    return
                }
                downloadedURL = file
                previewURL = file
            } catch {
                guard !Task.isCancelled, downloadID == requestID else { return }
                downloadError = "Attachment download failed: \(error.localizedDescription)"
            }
        }
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
    @Environment(\.workspaceRevision) private var workspaceRevision
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
        .task(id: "\(scenePhase)-\(refreshAutomatically ? workspaceRevision : 0)") {
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
            if let failure = error as? APIError, failure.isNotFound {
                self.error = "This workspace endpoint is unavailable on the server: \(error.localizedDescription)"
            } else {
                self.error = "Workspace sync failed: \(error.localizedDescription)"
            }
        }
    }
}

private struct ServerBoardsView: View {
    let client: HermesAPIClient
    @Environment(\.workspaceRevision) private var workspaceRevision
    @State private var revision = 0
    @State private var capabilities: WorkspaceCapabilities?
    @State private var notice: String?
    @State private var isWorking = false
    @State private var showEditor = false
    @State private var editingBoard: ServerBoard?
    @State private var archiveTarget: ServerBoard?

    var body: some View {
        WorkspaceReadView(load: { try await client.workspaceBoards() }) { snapshot in
            if let notice { Section { Text(notice).foregroundStyle(.secondary) } }
            if capabilities?.board_manage != true {
                Section { Text("Board management requires Companion bridge 0.1.10. Existing boards and tasks remain available.").foregroundStyle(.secondary) }
            }
            if snapshot.boards.isEmpty { ContentUnavailableView("No Kanban Boards", systemImage: "rectangle.3.group") }
            ForEach(snapshot.boards) { board in
                HStack {
                    NavigationLink {
                        ServerBoardView(client: client, board: board)
                    } label: {
                        WorkspaceRow(title: board.title,
                            detail: board.slug == snapshot.current ? "Active board" : board.project_name,
                            trailing: board.total.map(String.init), icon: "rectangle.3.group")
                    }
                    Menu {
                        Button("Edit Board", systemImage: "pencil") { editingBoard = board; showEditor = true }
                        Button("Use as Active Board", systemImage: "checkmark.circle") { perform(board, archive: false) }
                            .disabled(board.slug == snapshot.current)
                        if board.slug != "default" {
                            Button("Archive Board", systemImage: "archivebox", role: .destructive) { archiveTarget = board }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle").accessibilityLabel("Manage \(board.title)")
                    }
                    .disabled(isWorking || capabilities?.board_manage != true)
                }
                .disabled(isWorking)
            }
        }
        .id(revision)
        .toolbar {
            Button("New Board", systemImage: "plus") { editingBoard = nil; showEditor = true }
                .disabled(isWorking || capabilities?.board_manage != true)
        }
        .task(id: workspaceRevision) {
            do { capabilities = try await client.workspaceCapabilities() }
            catch { notice = "Could not check board management support: \(error.localizedDescription)" }
        }
        .sheet(isPresented: $showEditor) {
            ServerBoardEditorView(client: client, existing: editingBoard) { receipt in
                notice = receipt.already_exists == true ? "That board ID already exists. Its saved details were kept; use Edit Board to change them." : nil
                revision += 1
            }
        }
        .confirmationDialog("Archive \(archiveTarget?.title ?? "board")?", isPresented: Binding(
            get: { archiveTarget != nil }, set: { if !$0 { archiveTarget = nil } })) {
                if let target = archiveTarget {
                    Button("Archive Board", role: .destructive) { perform(target, archive: true) }
                }
            } message: {
                Text("The board and its tasks are retained in the server's archive and removed from the board list. If it is active, Hermes returns to the default board.")
            }
    }

    private func perform(_ board: ServerBoard, archive: Bool) {
        guard capabilities?.board_manage == true, !isWorking else {
            notice = "Update the Companion bridge to 0.1.10 before managing boards."
            return
        }
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await client.performWorkspaceBoardAction(slug: board.slug, archive: archive)
                notice = archive ? "Board archived on the server; its tasks were retained." : "Hermes now uses this board for CLI and slash-command tasks."
            } catch {
                notice = "Board action was not confirmed: \(error.localizedDescription) Refresh the list before retrying."
            }
            revision += 1
        }
    }
}

private struct ServerBoardEditorView: View {
    let client: HermesAPIClient
    let existing: ServerBoard?
    let onSaved: (ServerBoardReceipt) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var slug = ""
    @State private var name: String
    @State private var description: String
    @State private var icon: String
    @State private var color: String
    @State private var workdir: String
    @State private var projectID: String
    @State private var canManage = false
    @State private var isSaving = false
    @State private var failure: String?
    @State private var attemptedCreation: ServerBoardWrite?

    init(client: HermesAPIClient, existing: ServerBoard?, onSaved: @escaping (ServerBoardReceipt) -> Void) {
        self.client = client
        self.existing = existing
        self.onSaved = onSaved
        _name = State(initialValue: existing?.name ?? "")
        _description = State(initialValue: existing?.description ?? "")
        _icon = State(initialValue: existing?.icon ?? "")
        _color = State(initialValue: existing?.color ?? "")
        _workdir = State(initialValue: existing?.default_workdir ?? "")
        _projectID = State(initialValue: existing?.project_id ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                if let failure { Section { Text(failure).foregroundStyle(.red).textSelection(.enabled) } }
                Section("Board") {
                    if let existing { LabeledContent("Board ID", value: existing.slug) }
                    else { TextField("Board ID", text: $slug).textInputAutocapitalization(.never).autocorrectionDisabled() }
                    TextField("Name", text: $name)
                    TextField("Description", text: $description, axis: .vertical).lineLimit(2...8)
                    TextField("Icon", text: $icon)
                    TextField("Color", text: $color)
                }
                Section {
                    TextField("Server folder", text: $workdir).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Project ID or slug", text: $projectID).textInputAutocapitalization(.never).autocorrectionDisabled()
                } header: { Text("Optional server workspace") } footer: {
                    Text("Use an existing absolute folder path on the server. Linking a Hermes project uses its primary folder unless a folder is supplied.")
                }
            }
            .disabled(isSaving || attemptedCreation != nil)
            .navigationTitle(existing == nil ? "New Board" : "Edit Board")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(isSaving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") { Task { await save() } }
                        .disabled(isSaving || !canManage || (existing == nil && slug.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                }
            }
            .interactiveDismissDisabled(isSaving)
            .task {
                do {
                    canManage = try await client.workspaceCapabilities().board_manage == true
                    if !canManage { failure = "Board management requires Companion bridge 0.1.10 on this server." }
                } catch { failure = "Could not check board editing support: \(error.localizedDescription)" }
            }
        }
    }

    @MainActor private func save() async {
        guard canManage, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        var payload = ServerBoardWrite()
        if existing == nil { payload.slug = slug }
        // Omit unchanged fields so a phone edit does not overwrite unrelated Mac edits.
        if name != (existing?.name ?? "") { payload.name = name }
        if description != (existing?.description ?? "") { payload.description = description }
        if icon != (existing?.icon ?? "") { payload.icon = icon }
        if color != (existing?.color ?? "") { payload.color = color }
        if workdir != (existing?.default_workdir ?? "") { payload.default_workdir = workdir }
        if projectID != (existing?.project_id ?? "") { payload.project_id = projectID }
        if existing != nil, [payload.name, payload.description, payload.icon, payload.color,
                             payload.default_workdir, payload.project_id].allSatisfy({ $0 == nil }) {
            dismiss()
            return
        }
        do {
            let receipt: ServerBoardReceipt
            if let existing { receipt = try await client.updateWorkspaceBoard(slug: existing.slug, payload: payload) }
            else {
                if attemptedCreation == nil { attemptedCreation = try payload.validatedCreation() }
                receipt = try await client.createWorkspaceBoard(payload: attemptedCreation!)
            }
            onSaved(receipt)
            dismiss()
        } catch {
            if case APIError.http(let rejected) = error, [400, 401, 403, 404, 422].contains(rejected.status) {
                attemptedCreation = nil
            }
            failure = "Board save was not confirmed: \(error.localizedDescription) \(attemptedCreation != nil ? "Retry keeps the same board ID and fields; cancel and refresh to inspect the server." : "Check the supplied fields and refresh if another client may have edited this board.")"
        }
    }
}
