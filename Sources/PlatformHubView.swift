import SwiftUI

struct PlatformHubView: View {
    @ObservedObject var store: AppStore
    @EnvironmentObject private var appearance: AppearanceSettings
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var activeJobID: String?
    @State private var editingJob: HermesJob?
    @State private var showJobEditor = false
    @State private var isUploadingArtifact = false
    @State private var showArtifactPicker = false

    private var theme: any HermesTheme { appearance.activeTheme }

    private var activeSessions: [HermesSession] {
        store.sessions.filter { $0.isArchived != true }
    }

    private var pinnedSessions: [HermesSession] {
        activeSessions.filter { $0.isPinned == true }
    }

    private var botSessions: [HermesSession] {
        store.sessions.filter {
            let source = ($0.source ?? "").lowercased()
            return source == "bot" || source == "bot_room"
        }
    }

    private var kanbanSessions: [HermesSession] {
        store.sessions.filter { ($0.source ?? "").lowercased() == "kanban" }
    }

    private var connectedPlatforms: [HermesPlatformStatus] {
        let platformMap = store.platformHealth?.platforms ?? [:]
        return platformMap.values.sorted { $0.name < $1.name }
    }

    private var messagingPlatforms: [HermesPlatformStatus] {
        connectedPlatforms.filter { !["api_server", "webhook"].contains($0.name.lowercased()) }
    }

    private var enabledToolsets: [ToolsetInfo] {
        store.toolsets.filter(\.enabled)
    }

    private var workspaceProjects: [String] {
        ProjectStore.workspacePaths(from: store.sessions)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                theme.backgroundView.ignoresSafeArea()

                List {
                    if let error = store.platformError, !error.isEmpty {
                        Section {
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(theme.danger)
                        }
                    }

                    overviewSection
                    capabilitiesSection
                    endpointsSection
                    messagingSection
                    projectsSection
                    sessionsSection
                    modelsSection
                    toolsetsSection
                    skillsSection
                    jobsSection
                    artifactsSection
                    kanbanSection
                    botsSection
                }
                .sheet(isPresented: $showArtifactPicker) {
                    FilePickerView { data, fileName, mimeType in
                        isUploadingArtifact = true
                        Task {
                            await store.uploadArtifact(
                                data: data, fileName: fileName, mimeType: mimeType
                            )
                            isUploadingArtifact = false
                        }
                    }
                    .withActiveTheme(appearance)
                }
                .sheet(isPresented: $showJobEditor) {
                    JobEditorView(store: store, existingJob: editingJob)
                        .withActiveTheme(appearance)
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Hermes Platform")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search platform")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        editingJob = nil
                        showJobEditor = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(theme.accent)
                    }
                    .accessibilityLabel("Create Scheduled Job")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(theme.accent)
                }
            }
            .refreshable { await store.refreshPlatform() }
            .task { await store.refreshPlatform() }
        }
    }

    private var overviewSection: some View {
        Section("Gateway") {
            if store.isLoadingPlatform && store.platformHealth == nil {
                HStack { ProgressView(); Text("Syncing from Hermes...") }
            } else if let health = store.platformHealth {
                platformRow("Status", health.status, icon: "checkmark.shield")
                platformRow("Version", health.version ?? "Unknown", icon: "info.circle")
                platformRow("Gateway", health.gatewayState ?? "Unknown", icon: "antenna.radiowaves.left.and.right")
                platformRow("Active Agents", "\(health.activeAgents ?? 0)", icon: "person.2")
                platformRow("Busy", health.gatewayBusy == true ? "Yes" : "No", icon: "speedometer")
                platformRow("Session Store", health.readiness?.checks?["session_store"]?.status ?? "Unknown", icon: "externaldrive")
                platformRow("Model", health.readiness?.checks?["model"]?.status ?? "Unknown", icon: "cpu")
            } else {
                ContentUnavailableView(
                    "Gateway Unavailable",
                    systemImage: "antenna.radiowaves.left.and.right.slash",
                    description: Text(store.platformError ?? "Connect to a Hermes gateway to sync platform state.")
                )
            }
        }
    }

    private var capabilitiesSection: some View {
        Section("Capabilities") {
            if let features = store.capabilities?.features {
                platformRow("Session Chat", features.sessionChat ? "Yes" : "No", icon: "bubble.left.and.bubble.right")
                platformRow("Streaming Chat", features.sessionChatStreaming ? "Yes" : "No", icon: "waveform")
                platformRow("Session Fork", features.sessionFork ? "Yes" : "No", icon: "arrow.triangle.branch")
                platformRow("Model Lock", features.sessionModelLock == true ? "Yes" : "No", icon: "lock")
                platformRow("Artifacts", features.artifactTransport == true ? "Yes" : "No", icon: "externaldrive")
                platformRow("Skills API", features.skillsAPI ? "Yes" : "No", icon: "books.vertical")
                platformRow(
                    "Browser Control",
                    features.browserExtensionControl == true ? "Enabled" : "Disabled",
                    icon: "externaldrive.badge.icloud"
                )
                platformRow(
                    "Tool Approvals",
                    features.runApprovalResponse ? "Yes" : "No",
                    icon: "checkmark.shield"
                )
                platformRow(
                    "Tool Progress",
                    features.toolProgressEvents ? "Yes" : "No",
                    icon: "wrench.and.screwdriver"
                )
                platformRow(
                    "Session Resources",
                    features.sessionResources ? "Yes" : "No",
                    icon: "folder"
                )
                platformRow(
                    "Runs",
                    features.runSubmission ? "Yes" : "No",
                    icon: "arrow.right.circle"
                )
                platformRow(
                    "Run Events",
                    features.runEventsSSE ? "Yes" : "No",
                    icon: "dot.radiowaves.left.and.right"
                )
                platformRow(
                    "Run Stop",
                    features.runStop ? "Yes" : "No",
                    icon: "stop.circle"
                )
                platformRow(
                    "Approval Events",
                    features.approvalEvents ? "Yes" : "No",
                    icon: "checkmark.circle"
                )
                platformRow(
                    "Model Options",
                    features.modelOptions == true ? "Yes" : "No",
                    icon: "cpu"
                )
                platformRow(
                    "Chat Completions",
                    features.chatCompletions ? "Yes" : "No",
                    icon: "bubble.left.and.bubble.right"
                )
                platformRow(
                    "Chat Completions Streaming",
                    features.chatCompletionsStreaming ? "Yes" : "No",
                    icon: "waveform"
                )
            } else {
                Text("Capabilities are not exposed by this gateway yet.")
                    .foregroundStyle(theme.textSecondary)
            }
        }
    }

    private var endpointsSection: some View {
        Section("Endpoints") {
            if let endpoints = store.capabilities?.endpoints, !endpoints.isEmpty {
                ForEach(endpoints.keys.sorted(), id: \.self) { key in
                    if let endpoint = endpoints[key] {
                        platformRow(key, "\(endpoint.method) \(endpoint.path)", icon: "link")
                    }
                }
            } else {
                Text("Endpoints are not exposed by this gateway yet.")
                    .foregroundStyle(theme.textSecondary)
            }
        }
    }

    private var messagingSection: some View {
        Section("Messaging") {
            if messagingPlatforms.isEmpty {
                Text("No messaging platforms are configured.")
                    .foregroundStyle(theme.textSecondary)
            } else {
                ForEach(messagingPlatforms) { platform in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(platform.name.capitalized)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(theme.textPrimary)
                            Spacer()
                            stateBadge(platform.state ?? "Unknown")
                        }
                        if let message = platform.errorMessage, !message.isEmpty {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(theme.danger)
                        }
                    }
                }
                if !pinnedSessions.isEmpty {
                    ForEach(pinnedSessions.prefix(12)) { session in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.title ?? "Untitled")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(theme.textPrimary)
                                .lineLimit(1)
                            if let model = session.model, !model.isEmpty {
                                Text(model)
                                    .font(.caption)
                                    .foregroundStyle(theme.textSecondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                } else {
                    Text("No pinned sessions are reported by this gateway.")
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                }
            }
        }
    }

    private var sessionsSection: some View {
        Section("History") {
            platformRow("Total Chats", "\(store.sessions.count)", icon: "bubble.left.and.bubble.right")
            platformRow("Active Chats", "\(activeSessions.count)", icon: "bubble.left")
            platformRow("Pinned Chats", "\(pinnedSessions.count)", icon: "pin")
            if !pinnedSessions.isEmpty {
                ForEach(pinnedSessions.prefix(12)) { session in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.title ?? "Untitled")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(theme.textPrimary)
                            .lineLimit(1)
                        if let model = session.model, !model.isEmpty {
                            Text(model)
                                .font(.caption)
                                .foregroundStyle(theme.textSecondary)
                                .lineLimit(1)
                        }
                    }
                }
            } else {
                Text("No pinned sessions are reported by this gateway.")
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
            }
            platformRow("Archived Chats", "\(store.sessions.filter { $0.isArchived == true }.count)", icon: "archivebox")
        }
    }

    private var projectsSection: some View {
        Section("Projects") {
            if workspaceProjects.isEmpty {
                Text("No workspace folders are exposed by this gateway yet.")
                    .foregroundStyle(theme.textSecondary)
            } else {
                ForEach(workspaceProjects.prefix(20), id: \.self) { path in
                    let sessions = store.sessions.filter { $0.cwd == path || $0.gitRepoRoot == path }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(path)
                            .font(.caption.monospaced())
                            .foregroundStyle(theme.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.head)
                        Text("\(sessions.count) sessions")
                            .font(.caption2)
                            .foregroundStyle(theme.textMuted)
                    }
                }
                if workspaceProjects.count > 20 {
                    Text("+ \(workspaceProjects.count - 20) more")
                        .font(.caption)
                        .foregroundStyle(theme.textMuted)
                }
            }
        }
    }

    private var modelsSection: some View {
        Section("Models") {
            platformRow("Gateway Default", store.gatewayDefaultModel, icon: "cpu")
            platformRow("Active Session Model", store.effectiveCurrentModel, icon: "cpu")
            platformRow("Active Session Provider", store.effectiveCurrentProvider, icon: "server.rack")
            platformRow("Gateway Source", store.gatewayDefaultProvider, icon: "server.rack")
            platformRow("Providers", "\(store.configuredProviders.count)", icon: "square.stack.3d.up")
            platformRow("Selectable Models", "\(store.availableModels.count)", icon: "list.bullet")
                platformRow("Model Locks", store.sessionModelLockAvailable ? "Supported" : "Unavailable", icon: "lock")
        }
    }

    private var toolsetsSection: some View {
        Section("Toolsets") {
            platformRow("Enabled", "\(enabledToolsets.count)/\(store.toolsets.count)", icon: "wrench.and.screwdriver")
            platformRow("Total Tools", "\(store.toolsets.reduce(0) { $0 + ($1.tools.count) })", icon: "hammer")
        }
    }

    private var skillsSection: some View {
        Section("Skills") {
            platformRow("Loaded Skills", "\(store.skills.count)", icon: "books.vertical")
        }
    }

    private var jobsSection: some View {
        Section("Scheduled Jobs") {
            if store.platformJobs.isEmpty {
                Text("No scheduled jobs are reported by this gateway.")
                    .foregroundStyle(theme.textSecondary)
            } else {
                ForEach(store.platformJobs) { job in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(job.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(theme.textPrimary)
                            Spacer()
                            stateBadge(job.state ?? (job.enabled == true ? "Enabled" : "Paused"))
                        }

                        if let schedule = job.scheduleDisplay, !schedule.isEmpty {
                            Text(schedule)
                                .font(.caption)
                                .foregroundStyle(theme.textSecondary)
                        }
                        if let deliver = job.deliver, !deliver.isEmpty {
                            Text("Deliver: \(deliver)")
                                .font(.caption)
                                .foregroundStyle(theme.textSecondary)
                        }
                        if let lastStatus = job.lastStatus, !lastStatus.isEmpty {
                            Text("Last: \(lastStatus)")
                                .font(.caption)
                                .foregroundStyle(theme.textSecondary)
                        }
                        if let error = job.lastError, !error.isEmpty {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(theme.danger)
                                .lineLimit(2)
                        }

                        Button {
                            editingJob = job
                            showJobEditor = true
                        } label: {
                            Label("Edit Job", systemImage: "pencil")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(theme.accent)
                        }
                        .padding(.vertical, 4)

                        Menu {
                            if job.enabled == true {
                                Button {
                                    activeJobID = job.id
                                    Task { await store.controlJob(job, action: .pause) }
                                } label: {
                                    Label("Pause", systemImage: "pause.circle")
                                }
                            } else {
                                Button {
                                    activeJobID = job.id
                                    Task { await store.controlJob(job, action: .resume) }
                                } label: {
                                    Label("Resume", systemImage: "play.circle")
                                }
                            }

                            Button {
                                activeJobID = job.id
                                Task { await store.controlJob(job, action: .run) }
                            } label: {
                                Label("Run Now", systemImage: "bolt.circle")
                            }

                            Button(role: .destructive) {
                                activeJobID = job.id
                                Task { await store.controlJob(job, action: .delete) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        } label: {
                            HStack(spacing: 4) {
                                if activeJobID == job.id {
                                    ProgressView()
                                        .controlSize(.mini)
                                } else {
                                    Image(systemName: "ellipsis.circle")
                                }
                                Text("Control")
                                    .font(.caption.weight(.medium))
                            }
                            .foregroundStyle(theme.accent)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .background(Capsule().fill(theme.accent.opacity(0.12)))
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var artifactsSection: some View {
        Section("Artifacts") {
            if let receipt = store.artifactReceipt {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Uploaded \(receipt.filename)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.textPrimary)
                    Text("ID: \(receipt.artifactId)")
                        .font(.caption.monospaced())
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                    Text("SHA-256: \(receipt.sha256)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(theme.textMuted)
                        .lineLimit(1)
                    Text("Expires: \(Date(timeIntervalSince1970: receipt.expiresAt).formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(theme.textMuted)
                }
            }

            platformRow(
                "Upload Endpoint",
                store.capabilities?.endpoints["artifact_upload"]?.path ?? "Unavailable",
                icon: "arrow.up.doc"
            )
            platformRow(
                "Download Endpoint",
                store.capabilities?.endpoints["artifact_download"]?.path ?? "Unavailable",
                icon: "arrow.down.doc"
            )
            platformRow(
                "Transport",
                store.capabilities?.features.browserExtensionControl == true ? "Gateway Managed" : "Disabled",
                icon: "externaldrive"
            )

            if store.capabilities?.features.browserExtensionControl == true {
                Button {
                    showArtifactPicker = true
                } label: {
                    HStack {
                        if isUploadingArtifact {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "square.and.arrow.up")
                        }
                        Text("Upload Artifact")
                    }
                    .foregroundStyle(theme.accent)
                }
                .disabled(isUploadingArtifact)
            } else {
                Text("Artifact transport is disabled because browser control is disabled on this Hermes gateway.")
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
            }
        }
    }

    private var kanbanSection: some View {
        Section("Kanban") {
            platformRow("Kanban Sessions", "\(kanbanSessions.count)", icon: "square.stack.3d.up")
            platformRow("Dashboard Plugin", store.platformHealth != nil ? "Gateway Managed" : "Unavailable", icon: "uiwindow.split.2x1")
        }
    }

    private var botsSection: some View {
        Section("Bots") {
            platformRow("Bot Sessions", "\(botSessions.count)", icon: "person.crop.rectangle.stack")
            if botSessions.isEmpty {
                Text("No bot sessions are exposed by this gateway yet.")
                    .foregroundStyle(theme.textSecondary)
            } else {
                ForEach(botSessions.prefix(10)) { session in
                    Text(session.title ?? session.id)
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private func platformRow(_ label: String, _ value: String, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(theme.accent)
            Text(label)
                .foregroundStyle(theme.textPrimary)
            Spacer()
            Text(value.isEmpty ? "Unknown" : value)
                .font(.caption)
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func stateBadge(_ state: String) -> some View {
        let connected = ["connected", "running", "ok", "scheduled"].contains(state.lowercased())
        return Text(state.capitalized)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill((connected ? theme.accent : theme.danger).opacity(0.16))
            )
            .foregroundStyle(connected ? theme.accent : theme.danger)
    }
}

private struct JobEditorView: View {
    @ObservedObject var store: AppStore
    @EnvironmentObject private var appearance: AppearanceSettings
    @Environment(\.dismiss) private var dismiss

    let existingJob: HermesJob?

    @State private var name = ""
    @State private var schedule = ""
    @State private var prompt = ""
    @State private var deliver = "local"
    @State private var skillsText = ""
    @State private var isSaving = false

    private var theme: any HermesTheme { appearance.activeTheme }
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !schedule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Job") {
                    TextField("Name", text: $name)
                    TextField("Schedule (cron or interval)", text: $schedule)
                }

                Section("Prompt") {
                    TextEditor(text: $prompt)
                        .frame(minHeight: 140)
                        .accessibilityLabel("Prompt")
                }

                Section("Delivery") {
                    TextField("local", text: $deliver)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Skills") {
                    TextField("Comma separated skill IDs", text: $skillsText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !store.skills.isEmpty {
                        Text("Available: \(store.skills.prefix(8).compactMap(\.name).joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(theme.textMuted)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.backgroundView.ignoresSafeArea())
            .navigationTitle(existingJob == nil ? "New Job" : "Edit Job")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(!canSave || isSaving)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard let job = existingJob else { return }
        name = job.name
        schedule = job.scheduleDisplay ?? ""
        prompt = job.prompt ?? ""
        deliver = job.deliver ?? "local"
        skillsText = (job.skills ?? []).joined(separator: ", ")
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let skills = skillsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let payload = HermesJobWrite(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            schedule: schedule.trimmingCharacters(in: .whitespacesAndNewlines),
            prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines),
            deliver: deliver.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "local" : deliver.trimmingCharacters(in: .whitespacesAndNewlines),
            skills: skills
        )
        await store.saveJob(payload, jobId: existingJob?.id)
        dismiss()
    }
}
