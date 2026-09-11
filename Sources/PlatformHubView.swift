import SwiftUI

struct PlatformHubView: View {
    @ObservedObject var store: AppStore
    @EnvironmentObject private var appearance: AppearanceSettings
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var activeJobID: String?
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
                    messagingSection
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
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Hermes Platform")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search platform")
            .toolbar {
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
            }
        }
    }

    private var sessionsSection: some View {
        Section("History") {
            platformRow("Total Chats", "\(store.sessions.count)", icon: "bubble.left.and.bubble.right")
            platformRow("Active Chats", "\(activeSessions.count)", icon: "bubble.left")
            platformRow("Pinned Chats", "\(pinnedSessions.count)", icon: "pin")
            platformRow("Archived Chats", "\(store.sessions.filter { $0.isArchived == true }.count)", icon: "archivebox")
        }
    }

    private var modelsSection: some View {
        Section("Models") {
            platformRow("Gateway Default", store.gatewayDefaultModel, icon: "cpu")
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
