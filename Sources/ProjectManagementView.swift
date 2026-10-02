import SwiftUI

struct ProjectManagementView: View {
    let client: HermesAPIClient

    var body: some View {
        WorkspaceReadView(load: { try await client.workspaceBots() }) { roster in
            Section {
                Text("Manage saved projects in their owning Hermes profile. Automatically discovered folders remain available in the project browser.")
                    .font(.callout).foregroundStyle(.secondary)
                ForEach(roster.profiles) { profile in
                    NavigationLink(profile.title) {
                        ManagedProjectListView(client: client, profile: profile.name)
                    }
                }
            }
        }
        .navigationTitle("Manage Projects")
    }
}

private struct ManagedProjectListView: View {
    let client: HermesAPIClient
    let profile: String
    @State private var revision = 0
    @State private var showCreate = false
    @State private var failure: String?
    @State private var isWorking = false

    var body: some View {
        WorkspaceReadView(load: { try await client.managedProjects(profile: profile) }) { snapshot in
            if let failure { Text(failure).foregroundStyle(.red).textSelection(.enabled) }
            if snapshot.projects.isEmpty {
                ContentUnavailableView("No Saved Projects", systemImage: "folder", description: Text("Create a project to organize folders on the server."))
            }
            ForEach(snapshot.projects) { project in
                NavigationLink {
                    ManagedProjectDetailView(client: client, profile: profile, id: project.id)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(project.name)
                        if project.archived { Text("Archived").font(.caption).foregroundStyle(.secondary) }
                        if project.id == snapshot.active_id { Text("Active project").font(.caption).foregroundStyle(.secondary) }
                        if let path = project.primary_path { Text(path).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
            if snapshot.active_id != nil {
                Button("Clear Active Project") {
                    Task { @MainActor in
                        guard !isWorking else { return }
                        isWorking = true
                        defer { isWorking = false }
                        do {
                            try await client.activateProject(profile: profile, id: nil)
                            failure = nil
                            revision += 1
                        } catch { failure = "Could not clear the active project: \(error.localizedDescription) Refresh to confirm its current state." }
                    }
                }.disabled(isWorking)
            }
        }
        .id(revision)
        .navigationTitle(profile)
        .toolbar { Button("New Project", systemImage: "plus") { showCreate = true } }
        .sheet(isPresented: $showCreate) {
            ProjectEditorView(client: client, profile: profile) { revision += 1 }
        }
    }
}

private struct ManagedProjectDetailView: View {
    let client: HermesAPIClient
    let profile: String
    let id: String
    @State private var revision = 0
    @State private var editing: ManagedProject?
    @State private var showFolder = false
    @State private var editingFolder: ManagedProjectFolder?
    @State private var removeFolder: ManagedProjectFolder?
    @State private var archiveTarget: ManagedProject?
    @State private var deleteTarget: ManagedProject?
    @Environment(\.dismiss) private var dismiss
    @State private var failure: String?
    @State private var notice: String?
    @State private var isWorking = false
    @State private var canManage = false

    var body: some View {
        WorkspaceReadView(load: { try await client.managedProject(profile: profile, id: id) }) { project in
            if let failure { Text(failure).foregroundStyle(.red).textSelection(.enabled) }
            if let notice { Text(notice).foregroundStyle(.secondary) }
            Section("Project") {
                LabeledContent("Profile", value: profile)
                Text(project.name).font(.headline)
                LabeledContent("Slug", value: project.slug)
                if let description = project.description, !description.isEmpty { Text(description) }
                if let board = project.board_slug, !board.isEmpty { LabeledContent("Board", value: board) }
                Button("Edit Project") { editing = project }.disabled(!canManage || isWorking)
                Button("Use as Active Project") {
                    perform("activate the project") { try await client.activateProject(profile: profile, id: id) }
                }.disabled(!canManage || isWorking || project.archived)
                Button(project.archived ? "Restore Project" : "Archive Project") { archiveTarget = project }
                    .disabled(!canManage || isWorking)
            }
            Section {
                Button("Delete Project Record", role: .destructive) { deleteTarget = project }.disabled(!canManage || isWorking)
            }
            Section("Server Folders") {
                ForEach(project.folders) { folder in
                    VStack(alignment: .leading, spacing: 6) {
                        if let label = folder.label, !label.isEmpty { Text(label).font(.headline) }
                        Text(folder.path).textSelection(.enabled)
                        if folder.is_primary { Text("Primary folder").font(.caption).foregroundStyle(.secondary) }
                        HStack {
                            if !folder.is_primary {
                                Button("Make Primary") {
                                    perform("set the primary folder") {
                                        _ = try await client.changeProjectFolder(profile: profile, id: id, action: .primary, payload: ProjectFolderWrite(path: folder.path))
                                    }
                                }
                            }
                            Button("Edit Label") { editingFolder = folder; showFolder = true }
                            Button("Remove Link", role: .destructive) { removeFolder = folder }
                        }.buttonStyle(.borderless).disabled(!canManage || isWorking)
                    }
                }
                Button("Add Server Folder") { editingFolder = nil; showFolder = true }.disabled(!canManage || isWorking)
                Text("Folder links point to paths on the Hermes server. Removing a link does not delete files.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if isWorking { ProgressView("Waiting for Hermes…") }
        }
        .id(revision)
        .navigationTitle("Project")
        .sheet(item: $editing) { project in
            ProjectEditorView(client: client, profile: profile, existing: project) { revision += 1 }
        }
        .sheet(isPresented: $showFolder) {
            ProjectFolderEditorView(client: client, profile: profile, projectID: id, existing: editingFolder) { revision += 1 }
        }
        .confirmationDialog("Remove this folder link?", isPresented: Binding(get: { removeFolder != nil }, set: { if !$0 { removeFolder = nil } }), titleVisibility: .visible) {
            if let folder = removeFolder {
                Button("Remove Link", role: .destructive) {
                    perform("remove the folder link") {
                        _ = try await client.changeProjectFolder(profile: profile, id: id, action: .remove, payload: ProjectFolderWrite(path: folder.path))
                    }
                }
            }
        } message: { Text(removeFolder?.path ?? "") }
        .confirmationDialog(archiveTarget?.archived == true ? "Restore this project?" : "Archive this project?", isPresented: Binding(get: { archiveTarget != nil }, set: { if !$0 { archiveTarget = nil } }), titleVisibility: .visible) {
            if let project = archiveTarget {
                Button(project.archived ? "Restore" : "Archive") {
                    perform(project.archived ? "restore the project" : "archive the project") {
                        try await client.archiveProject(profile: profile, id: id, restore: project.archived)
                    }
                }
            }
        } message: { Text("This changes the saved project record in \(profile). Server files and conversations are retained.") }
        .confirmationDialog("Delete this saved project?", isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }), titleVisibility: .visible) {
            Button("Delete Project Record", role: .destructive) {
                perform("delete the project") {
                    try await client.deleteProject(profile: profile, id: id)
                    dismiss()
                }
            }
        } message: { Text("This permanently removes the project record and its folder links from \(profile). Server files and conversations are retained.") }
        .task {
            do {
                canManage = try await client.workspaceCapabilities().project_manage == true
                if !canManage { failure = "This gateway does not advertise project editing. Install Companion bridge 0.1.9 to enable these controls." }
            } catch { failure = "Could not check project editing support: \(error.localizedDescription)" }
        }
    }

    private func perform(_ action: String, operation: @escaping () async throws -> Void) {
        guard !isWorking else { return }
        isWorking = true
        failure = nil
        notice = nil
        Task { @MainActor in
            defer { isWorking = false }
            do {
                try await operation()
                notice = "Hermes confirmed the change."
                revision += 1
            } catch { failure = "Could not \(action): \(error.localizedDescription) Refresh this project before retrying an uncertain request." }
        }
    }
}

private struct ProjectEditorView: View {
    let client: HermesAPIClient
    let profile: String
    let existing: ManagedProject?
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var description: String
    @State private var icon: String
    @State private var color: String
    @State private var board: String
    @State private var slug = ""
    @State private var folderPaths = ""
    @State private var failure: String?
    @State private var canManage = false
    @State private var isSaving = false
    @State private var creationUncertain = false

    init(client: HermesAPIClient, profile: String, existing: ManagedProject? = nil, onSaved: @escaping () -> Void) {
        self.client = client; self.profile = profile; self.existing = existing; self.onSaved = onSaved
        _name = State(initialValue: existing?.name ?? "")
        _description = State(initialValue: existing?.description ?? "")
        _icon = State(initialValue: existing?.icon ?? "")
        _color = State(initialValue: existing?.color ?? "")
        _board = State(initialValue: existing?.board_slug ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                if let failure { Text(failure).foregroundStyle(.red).textSelection(.enabled) }
                Section("Project") {
                    LabeledContent("Profile", value: profile)
                    TextField("Name", text: $name)
                    TextField("Description", text: $description, axis: .vertical).lineLimit(3...8)
                    TextField("Icon", text: $icon)
                    TextField("Color", text: $color)
                    TextField("Kanban board slug", text: $board).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                if existing == nil {
                    Section("Server Folders") {
                        TextField("Slug (optional)", text: $slug).textInputAutocapitalization(.never).autocorrectionDisabled()
                        TextField("Absolute server paths, one per line", text: $folderPaths, axis: .vertical)
                            .lineLimit(3...10).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Text("The first folder becomes primary. Leave paths empty to create a project without folders.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .disabled(isSaving || creationUncertain)
            .navigationTitle(existing == nil ? "New Project" : "Edit Project")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(isSaving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") { Task { await save() } }
                        .disabled(isSaving || creationUncertain || !canManage || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .interactiveDismissDisabled(isSaving)
            .task {
                do {
                    canManage = try await client.workspaceCapabilities().project_manage == true
                    if !canManage { failure = "Project editing requires Companion bridge 0.1.9 on this server." }
                } catch { failure = "Could not check project editing support: \(error.localizedDescription)" }
            }
        }
    }

    @MainActor private func save() async {
        guard !isSaving, canManage, !creationUncertain else { return }
        isSaving = true
        failure = nil
        defer { isSaving = false }
        do {
            let payload: ProjectWrite
            if let existing {
                payload = ProjectWrite.changes(from: existing, name: name.trimmingCharacters(in: .whitespacesAndNewlines), description: description, icon: icon, color: color, board: board)
                if payload.isEmpty { dismiss(); return }
            } else {
                var value = ProjectWrite()
                value.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                value.description = description
                value.icon = icon
                value.color = color
                value.board_slug = board
                value.slug = slug.isEmpty ? nil : slug
                value.folders = folderPaths.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                payload = value
            }
            _ = try await client.saveProject(profile: profile, id: existing?.id, payload: payload)
            onSaved()
            dismiss()
        } catch {
            var rejected = false
            if let apiError = error as? APIError, case .http(let failure) = apiError {
                rejected = [400, 401, 403, 404, 422].contains(failure.status)
            }
            creationUncertain = existing == nil && !rejected
            failure = "Could not confirm the project save: \(error.localizedDescription) " + (creationUncertain ? "Cancel and refresh the project list before creating again; Hermes may already have saved it." : "Your edits are kept. Correct rejected fields or refresh before retrying an uncertain update.")
        }
    }
}

private struct ProjectFolderEditorView: View {
    let client: HermesAPIClient
    let profile: String
    let projectID: String
    let existing: ManagedProjectFolder?
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var path = ""
    @State private var label = ""
    @State private var primary = false
    @State private var failure: String?
    @State private var isSaving = false

    init(client: HermesAPIClient, profile: String, projectID: String, existing: ManagedProjectFolder? = nil, onSaved: @escaping () -> Void) {
        self.client = client; self.profile = profile; self.projectID = projectID
        self.existing = existing; self.onSaved = onSaved
        _path = State(initialValue: existing?.path ?? "")
        _label = State(initialValue: existing?.label ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                if let failure { Text(failure).foregroundStyle(.red).textSelection(.enabled) }
                TextField("Absolute server folder path", text: $path).textInputAutocapitalization(.never).autocorrectionDisabled().disabled(existing != nil)
                TextField("Label (optional)", text: $label)
                if existing == nil { Toggle("Make primary", isOn: $primary) }
            }.disabled(isSaving)
            .navigationTitle(existing == nil ? "Add Server Folder" : "Edit Folder Label")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(isSaving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") {
                        guard !isSaving else { return }
                        isSaving = true
                        Task { @MainActor in
                            defer { isSaving = false }
                            do {
                                _ = try await client.changeProjectFolder(profile: profile, id: projectID, action: .add,
                                    payload: ProjectFolderWrite(path: path.trimmingCharacters(in: .whitespacesAndNewlines), label: label, is_primary: primary))
                                onSaved(); dismiss()
                            } catch { failure = "Could not add the folder link: \(error.localizedDescription) Your values are kept. Refresh to confirm the current folders before retrying." }
                        }
                    }.disabled(isSaving || path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
    }
}
