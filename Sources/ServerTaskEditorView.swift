import SwiftUI

struct ServerTaskEditorView: View {
    let client: HermesAPIClient
    let board: String
    let existing: ServerBoardTask?
    let onSaved: (ServerTaskWriteReceipt) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var taskBody: String
    @State private var assignee: String
    @State private var priority: Int
    @State private var status: String
    @State private var result: String
    @State private var summary = ""
    @State private var blockReason = ""
    @State private var triage = true
    @State private var creationKey = UUID().uuidString
    @State private var submittedCreation: ServerTaskWrite?
    @State private var capabilities: WorkspaceCapabilities?
    @State private var failure: String?
    @State private var isSaving = false

    init(client: HermesAPIClient, board: String, existing: ServerBoardTask? = nil,
         onSaved: @escaping (ServerTaskWriteReceipt) -> Void) {
        self.client = client
        self.board = board
        self.existing = existing
        self.onSaved = onSaved
        _title = State(initialValue: existing?.title ?? "")
        _taskBody = State(initialValue: existing?.body ?? "")
        _assignee = State(initialValue: existing?.assignee ?? "")
        _priority = State(initialValue: existing?.priority ?? 0)
        _status = State(initialValue: existing?.status ?? "triage")
        _result = State(initialValue: existing?.result ?? "")
    }

    private var canSave: Bool {
        !isSaving && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (existing == nil ? capabilities?.task_create == true : capabilities?.task_update == true)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let failure {
                    Section { Text(failure).foregroundStyle(.red).textSelection(.enabled) }
                }
                Section("Task") {
                    LabeledContent("Board", value: board)
                    TextField("Title", text: $title, axis: .vertical)
                    TextField("Description", text: $taskBody, axis: .vertical).lineLimit(4...12)
                    TextField("Assignee profile (blank for unassigned)", text: $assignee)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Stepper("Priority: \(priority)", value: $priority)
                }
                .disabled(submittedCreation != nil)
                Section("Workflow") {
                    if existing == nil {
                        Toggle("Hold in triage", isOn: $triage)
                    } else {
                        Picker("Status", selection: $status) {
                            if capabilities?.task_statuses.contains(status) != true {
                                Text(status.capitalized + " (server controlled)").tag(status)
                            }
                            ForEach(capabilities?.task_statuses ?? [], id: \.self) { value in
                                Text(value.capitalized).tag(value)
                            }
                        }
                    }
                    Text("Ready tasks may start automatically when assigned. Hermes checks dependencies and active workers before accepting a transition.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .disabled(submittedCreation != nil)
                if let existing, status != existing.status, ["done", "review", "blocked", "scheduled"].contains(status) {
                    Section("Handoff") {
                        if status == "done" {
                            TextField("Result", text: $result, axis: .vertical).lineLimit(3...10)
                        }
                        if status == "done" || status == "review" {
                            TextField("New summary", text: $summary, axis: .vertical).lineLimit(2...6)
                        }
                        if status == "blocked" || status == "scheduled" {
                            TextField("Reason", text: $blockReason, axis: .vertical)
                        }
                    }
                }
                if capabilities == nil && failure == nil { ProgressView("Checking editing support…") }
            }
            .disabled(isSaving)
            .navigationTitle(existing == nil ? "New Task" : "Edit Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") { Task { await save() } }.disabled(!canSave)
                }
            }
            .task {
                do {
                    capabilities = try await client.workspaceCapabilities()
                    if existing == nil ? capabilities?.task_create != true : capabilities?.task_update != true {
                        failure = "This server does not advertise support for this task operation. Check its Companion bridge capabilities."
                    }
                }
                catch {
                    guard !Task.isCancelled else { return }
                    failure = "Task editing needs Companion bridge 0.1.8 on this server. \(error.localizedDescription)"
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    @MainActor private func save() async {
        guard canSave else { return }
        isSaving = true
        failure = nil
        defer { isSaving = false }
        do {
            let receipt: ServerTaskWriteReceipt
            if let existing {
                let changes = ServerTaskWrite.changes(from: existing,
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines), body: taskBody,
                    assignee: assignee.trimmingCharacters(in: .whitespacesAndNewlines), priority: priority,
                    status: status, result: result, summary: summary, blockReason: blockReason)
                guard !changes.isEmpty else { dismiss(); return }
                receipt = try await client.updateWorkspaceTask(board: board, taskID: existing.id, payload: changes)
            } else {
                var payload = ServerTaskWrite()
                payload.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                payload.body = taskBody
                payload.assignee = assignee.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : assignee.trimmingCharacters(in: .whitespacesAndNewlines)
                payload.priority = priority
                payload.triage = triage
                payload.idempotency_key = creationKey
                // Keep retries identical after an uncertain response. A changed
                // payload with the same key could otherwise silently return the old task.
                if submittedCreation == nil { submittedCreation = payload }
                receipt = try await client.createWorkspaceTask(board: board, payload: submittedCreation!)
            }
            onSaved(receipt)
            dismiss()
        } catch {
            if existing == nil, let apiError = error as? APIError,
               case .http(let failure) = apiError, [400, 422].contains(failure.status) {
                submittedCreation = nil
            }
            failure = "Could not confirm the task save: \(error.localizedDescription) Your edits are kept. " + (existing == nil ? (submittedCreation == nil ? "Correct the rejected fields and save again." : "Retry sends the same creation request to prevent duplicates. Cancel to return to the board.") : "Refresh the task before retrying an uncertain update.")
        }
    }
}

struct ServerTaskCommentView: View {
    let client: HermesAPIClient
    let board: String
    let taskID: String
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var failure: String?
    @State private var canComment = false
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                if let failure { Text(failure).foregroundStyle(.red).textSelection(.enabled) }
                TextField("Comment", text: $text, axis: .vertical).lineLimit(5...15)
            }
            .disabled(isSaving)
            .navigationTitle("Add Comment")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(isSaving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Adding…" : "Add") { Task { await save() } }
                        .disabled(isSaving || !canComment || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .task {
                do {
                    canComment = try await client.workspaceCapabilities().task_comment
                    if !canComment { failure = "This server does not advertise task comment support. Check its Companion bridge capabilities." }
                }
                catch {
                    guard !Task.isCancelled else { return }
                    failure = "Comments need Companion bridge 0.1.8 on this server. \(error.localizedDescription)"
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    @MainActor private func save() async {
        guard !isSaving, canComment else { return }
        isSaving = true
        failure = nil
        defer { isSaving = false }
        do {
            try await client.commentWorkspaceTask(board: board, taskID: taskID, body: text)
            onSaved()
            dismiss()
        } catch {
            failure = "Could not confirm the comment: \(error.localizedDescription) Check the task's comments before retrying so the same comment is not added twice. Your text is kept."
        }
    }
}
