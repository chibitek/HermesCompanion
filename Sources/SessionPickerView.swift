import SwiftUI

struct SessionPickerView: View {
    @ObservedObject var store: AppStore
    @EnvironmentObject var appearance: AppearanceSettings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.activeTheme) private var theme

    @StateObject private var projects = ProjectStore()
    @State private var mode: HistoryMode = .chats
    @State private var selectedProjectID: UUID?
    @State private var isCreatingSession = false
    @State private var newSessionTitle = ""
    @State private var isCreatingProject = false
    @State private var newProjectName = ""
    @State private var renamingSession: HermesSession?
    @State private var renameText = ""
    @State private var renamingProject: ChatProject?
    @State private var projectRenameText = ""
    @State private var detailSession: HermesSession?
    @State private var movingSession: HermesSession?
    @State private var searchText = ""
    @State private var sortMode: SessionSortMode = .lastActive
    @State private var showSortOptions = false

    private var visibleSessions: [HermesSession] {
        var result = store.sessions
        if mode == .projects, let selectedProjectID {
            let ids = Set(projects.sessionIDs(in: selectedProjectID))
            result = result.filter { ids.contains($0.id) }
        }
        if !searchText.isEmpty {
            result = result.filter {
                ($0.title ?? "").localizedCaseInsensitiveContains(searchText) ||
                ($0.source ?? "").localizedCaseInsensitiveContains(searchText) ||
                $0.id.localizedCaseInsensitiveContains(searchText) ||
                (projects.project(for: $0.id)?.name.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
        switch sortMode {
        case .lastActive:
            return result.sorted { ($0.lastActive ?? $0.startedAt ?? 0) > ($1.lastActive ?? $1.startedAt ?? 0) }
        case .title:
            return result.sorted { ($0.title ?? "Untitled").localizedCaseInsensitiveCompare($1.title ?? "Untitled") == .orderedAscending }
        case .messageCount:
            return result.sorted { ($0.messageCount ?? 0) > ($1.messageCount ?? 0) }
        }
    }

    private var title: String {
        if mode == .projects, let selectedProjectID,
           let project = projects.projects.first(where: { $0.id == selectedProjectID }) {
            return project.name
        }
        return mode == .chats ? "History" : "Projects"
    }

    var body: some View {
        ZStack {
            theme.backgroundView.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Divider().background(theme.cardBorder)

                if mode == .projects && selectedProjectID == nil {
                    projectsOverview
                } else {
                    chatsView
                }
            }

            if !(mode == .projects && selectedProjectID == nil) {
                searchBar
            }
        }
        .alert("New Chat", isPresented: $isCreatingSession) {
            TextField("Title (optional)", text: $newSessionTitle)
            Button("Create") {
                Task {
                    await store.createSession(title: newSessionTitle.isEmpty ? nil : newSessionTitle)
                    if let sessionID = store.activeSession?.id, mode == .projects {
                        projects.assign(sessionID: sessionID, to: selectedProjectID)
                    }
                    newSessionTitle = ""
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) { newSessionTitle = "" }
        }
        .alert("New Project", isPresented: $isCreatingProject) {
            TextField("Project Name", text: $newProjectName)
            Button("Create") {
                let project = projects.createProject(name: newProjectName)
                newProjectName = ""
                selectedProjectID = project.id
            }
            Button("Cancel", role: .cancel) { newProjectName = "" }
        }
        .alert("Rename Chat", isPresented: Binding(
            get: { renamingSession != nil },
            set: { if !$0 { renamingSession = nil } }
        )) {
            TextField("Chat Title", text: $renameText)
            Button("Rename") {
                if let session = renamingSession, !renameText.isEmpty {
                    Task { await store.renameSession(session, newTitle: renameText) }
                }
                renamingSession = nil
            }
            Button("Cancel", role: .cancel) { renamingSession = nil }
        }
        .alert("Rename Project", isPresented: Binding(
            get: { renamingProject != nil },
            set: { if !$0 { renamingProject = nil } }
        )) {
            TextField("Project Name", text: $projectRenameText)
            Button("Rename") {
                if let project = renamingProject {
                    projects.renameProject(project.id, name: projectRenameText)
                }
                renamingProject = nil
            }
            Button("Cancel", role: .cancel) { renamingProject = nil }
        }
        .sheet(item: $detailSession) { session in
            SessionDetailView(store: store, session: session)
        }
        .sheet(item: $movingSession) { session in
            ProjectAssignmentSheet(projects: projects, session: session)
                .withActiveTheme(appearance)
        }
        .confirmationDialog("Sort Chats", isPresented: $showSortOptions, titleVisibility: .visible) {
            ForEach(SessionSortMode.allCases) { sortMode in
                Button { self.sortMode = sortMode } label: {
                    Label(sortMode.label, systemImage: sortMode.icon)
                }
            }
            Button("Cancel", role: .cancel) { }
        }
    }

    private var header: some View {
        VStack(spacing: theme.spacingS) {
            HStack {
                Button {
                    if selectedProjectID != nil {
                        selectedProjectID = nil
                    } else {
                        dismiss()
                    }
                } label: {
                    Image(systemName: selectedProjectID == nil ? "xmark" : "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                        .frame(width: 38, height: 34)
                        .background(AnyView(theme.glassCard(cornerRadius: theme.controlRadius)))
                }
                .buttonStyle(.plain)

                Spacer()

                Text(title)
                    .font(theme.uiFont.weight(.bold))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)

                Spacer()

                HStack(spacing: theme.spacingXS) {
                    Button {
                        if mode == .projects && selectedProjectID == nil {
                            isCreatingProject = true
                        } else {
                            isCreatingSession = true
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(theme.accent)
                            .frame(width: 38, height: 34)
                            .background(AnyView(theme.glassCard(cornerRadius: theme.controlRadius)))
                    }
                    .buttonStyle(.plain)

                    if !(mode == .projects && selectedProjectID == nil) {
                        Button { showSortOptions = true } label: {
                            Image(systemName: "arrow.up.arrow.down")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(theme.accent)
                                .frame(width: 38, height: 34)
                                .background(AnyView(theme.glassCard(cornerRadius: theme.controlRadius)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if selectedProjectID == nil {
                Picker("History View", selection: $mode) {
                    ForEach(HistoryMode.allCases) { mode in
                        Label(mode.label, systemImage: mode.icon).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .tint(theme.accent)
            }
        }
        .padding(.horizontal, theme.spacingM)
        .padding(.vertical, theme.spacingS)
        .background(AnyView(theme.glassCard(cornerRadius: 0).opacity(0.94)))
    }

    @ViewBuilder
    private var projectsOverview: some View {
        if projects.projects.isEmpty {
            Spacer()
            ContentUnavailableView(
                "No Projects",
                systemImage: "folder.badge.plus",
                description: Text("Create a project to organize related chats.")
            )
            .foregroundStyle(theme.textPrimary)
            Button("Create Project") { isCreatingProject = true }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent)
            Spacer()
        } else {
            ScrollView {
                LazyVStack(spacing: theme.spacingS) {
                    ForEach(projects.projects) { project in
                        Button { selectedProjectID = project.id } label: {
                            projectRow(project)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                renamingProject = project
                                projectRenameText = project.name
                            } label: {
                                Label("Rename Project", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                projects.deleteProject(project.id)
                            } label: {
                                Label("Delete Project", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(theme.spacingM)
            }
        }
    }

    private func projectRow(_ project: ChatProject) -> some View {
        HStack(spacing: theme.spacingM) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(theme.accent.opacity(0.14))
                Image(systemName: "folder.fill")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(theme.accent)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
                    .font(theme.uiFont.weight(.semibold))
                    .foregroundStyle(theme.textPrimary)
                let count = projects.sessionCount(in: project.id)
                Text(count == 1 ? "1 chat" : "\(count) chats")
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(theme.textMuted)
        }
        .padding(theme.spacingM)
        .background(AnyView(theme.glassCard(cornerRadius: theme.radiusM)))
    }

    @ViewBuilder
    private var chatsView: some View {
        if visibleSessions.isEmpty {
            Spacer()
            ContentUnavailableView(
                searchText.isEmpty ? "No Chats" : "No Results",
                systemImage: searchText.isEmpty ? "bubble.left.and.bubble.right" : "magnifyingglass",
                description: Text(mode == .projects ? "Move chats here with a long press in History." : "Create a new chat to get started.")
            )
            .foregroundStyle(theme.textPrimary)
            Spacer()
        } else {
            ScrollView {
                LazyVStack(spacing: theme.spacingS) {
                    ForEach(visibleSessions) { session in
                        SessionRowButton(
                            session: session,
                            isActive: store.activeSession?.id == session.id,
                            projectName: projects.project(for: session.id)?.name,
                            onSelect: {
                                Task {
                                    await store.selectSession(session)
                                    dismiss()
                                }
                            },
                            onMove: { movingSession = session },
                            onRename: {
                                renamingSession = session
                                renameText = session.title ?? ""
                            },
                            onDetails: { detailSession = session },
                            onFork: {
                                Task {
                                    await store.forkSession(session)
                                    dismiss()
                                }
                            },
                            onDelete: {
                                projects.assign(sessionID: session.id, to: nil)
                                Task { await store.deleteSession(session) }
                            }
                        )
                    }
                }
                .padding(.horizontal, theme.spacingM)
                .padding(.top, theme.spacingS)
                .padding(.bottom, theme.spacingXL + 60)
            }
            .refreshable { await store.refreshSessions() }
        }
    }

    private var searchBar: some View {
        VStack {
            Spacer()
            HStack(spacing: theme.spacingS) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(theme.textMuted)
                TextField("Search chats and projects", text: $searchText)
                    .font(theme.uiFont)
                    .foregroundStyle(theme.textPrimary)
            }
            .padding(.horizontal, theme.spacingM)
            .padding(.vertical, theme.spacingS + 2)
            .background(AnyView(theme.glassCard(cornerRadius: theme.radiusS)))
            .padding(.horizontal, theme.spacingM)
            .padding(.bottom, theme.spacingM)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }
}

private enum HistoryMode: String, CaseIterable, Identifiable {
    case chats
    case projects
    var id: String { rawValue }
    var label: String { self == .chats ? "Chats" : "Projects" }
    var icon: String { self == .chats ? "bubble.left.and.bubble.right" : "folder" }
}

enum SessionSortMode: String, CaseIterable, Identifiable {
    case lastActive
    case title
    case messageCount
    var id: String { rawValue }
    var label: String {
        switch self {
        case .lastActive: return "Last Active"
        case .title: return "Title"
        case .messageCount: return "Message Count"
        }
    }
    var icon: String {
        switch self {
        case .lastActive: return "clock"
        case .title: return "textformat"
        case .messageCount: return "number"
        }
    }
}

private struct SessionRowButton: View {
    let session: HermesSession
    let isActive: Bool
    let projectName: String?
    let onSelect: () -> Void
    let onMove: () -> Void
    let onRename: () -> Void
    let onDetails: () -> Void
    let onFork: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onSelect) {
            SessionRow(session: session, isActive: isActive, projectName: projectName)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(action: onMove) {
                Label(projectName == nil ? "Move to Project" : "Change Project", systemImage: "folder")
            }
            Button(action: onRename) { Label("Rename", systemImage: "pencil") }
            Button(action: onDetails) { Label("Details", systemImage: "info.circle") }
            Button(action: onFork) { Label("Fork", systemImage: "arrow.triangle.branch") }
            Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") }
        }
    }
}

struct SessionRow: View {
    @Environment(\.activeTheme) private var theme
    let session: HermesSession
    let isActive: Bool
    var projectName: String? = nil

    var body: some View {
        HStack(spacing: theme.spacingS) {
            VStack(alignment: .leading, spacing: theme.spacingXS) {
                Text(session.title ?? "Untitled")
                    .font(theme.uiFont.weight(.semibold))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    if let projectName {
                        Label(projectName, systemImage: "folder.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(theme.accent)
                            .lineLimit(1)
                    } else {
                        Text(session.source?.lowercased() ?? "api_server")
                            .font(.system(.caption, design: .monospaced, weight: .medium))
                            .foregroundStyle(theme.accent)
                    }
                }

                Text(metadata)
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
            }
            .multilineTextAlignment(.leading)

            Spacer()

            if isActive {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(red: 0.012, green: 0.137, blue: 0.118))
                    .frame(width: 22, height: 22)
                    .background(theme.accent)
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, theme.spacingM)
        .padding(.vertical, theme.spacingS + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AnyView(theme.glassCard(cornerRadius: theme.radiusM)))
        .overlay(
            RoundedRectangle(cornerRadius: theme.radiusM, style: .continuous)
                .stroke(isActive ? theme.accent.opacity(0.35) : theme.cardBorder, lineWidth: isActive ? 1.5 : theme.cardBorderWidth)
        )
        .contentShape(Rectangle())
    }

    private var metadata: String {
        let count = session.messageCount ?? 0
        let countText = count == 1 ? "1 message" : "\(count) messages"
        let end = session.lastActive ?? session.startedAt ?? Date().timeIntervalSince1970
        let start = session.startedAt ?? end
        return "\(countText) · \(formatDuration(max(0, end - start)))"
    }
}

private struct ProjectAssignmentSheet: View {
    @ObservedObject var projects: ProjectStore
    let session: HermesSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.activeTheme) private var theme
    @State private var newProjectName = ""

    var body: some View {
        NavigationStack {
            ZStack {
                theme.backgroundView.ignoresSafeArea()
                List {
                    Section {
                        Button {
                            projects.assign(sessionID: session.id, to: nil)
                            dismiss()
                        } label: {
                            Label("No Project", systemImage: projects.project(for: session.id) == nil ? "checkmark.circle.fill" : "circle")
                        }

                        ForEach(projects.projects) { project in
                            Button {
                                projects.assign(sessionID: session.id, to: project.id)
                                dismiss()
                            } label: {
                                HStack {
                                    Label(project.name, systemImage: "folder.fill")
                                    Spacer()
                                    if projects.project(for: session.id)?.id == project.id {
                                        Image(systemName: "checkmark").foregroundStyle(theme.accent)
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("Move \"\(session.title ?? "Untitled")\"")
                    }

                    Section("Create Project") {
                        TextField("Project Name", text: $newProjectName)
                        Button("Create and Move") {
                            let project = projects.createProject(name: newProjectName)
                            projects.assign(sessionID: session.id, to: project.id)
                            dismiss()
                        }
                        .disabled(newProjectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Move to Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

struct SessionDetailView: View {
    @ObservedObject var store: AppStore
    @Environment(\.activeTheme) private var theme
    let session: HermesSession
    @Environment(\.dismiss) private var dismiss
    @State private var detail: SessionDetail?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                theme.backgroundView.ignoresSafeArea()
                List {
                    if isLoading {
                        HStack { ProgressView(); Text("Loading chat...") }
                    } else if let detail {
                        Section("Chat") {
                            row("Title", detail.title ?? "Untitled")
                            row("ID", detail.id)
                            if let source = detail.source { row("Source", source) }
                            if let model = detail.model { row("Model", model) }
                        }
                        Section("Activity") {
                            if let started = detail.date { row("Started", started.formatted(date: .abbreviated, time: .shortened)) }
                            if let active = detail.lastActiveDate { row("Last Active", active.formatted(date: .abbreviated, time: .shortened)) }
                            if let count = detail.messageCount { row("Messages", "\(count)") }
                            if let count = detail.toolCallCount { row("Tool Calls", "\(count)") }
                        }
                        Section("Tokens") {
                            if let count = detail.inputTokens { row("Input", count.formatted()) }
                            if let count = detail.outputTokens { row("Output", count.formatted()) }
                            if let count = detail.reasoningTokens { row("Reasoning", count.formatted()) }
                        }
                        if let preview = detail.preview, !preview.isEmpty {
                            Section("Preview") { Text(preview).textSelection(.enabled) }
                        }
                    } else {
                        ContentUnavailableView("Chat Unavailable", systemImage: "exclamationmark.triangle", description: Text(errorMessage ?? "Details could not be loaded."))
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Chat Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private func load() async {
        guard let client = store.apiClient else { errorMessage = "Not connected"; return }
        isLoading = true
        defer { isLoading = false }
        do {
            detail = try await client.getSession(sessionId: session.id)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(theme.textSecondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing).textSelection(.enabled).foregroundStyle(theme.textPrimary)
        }
    }
}

private func formatDuration(_ seconds: TimeInterval) -> String {
    let total = Int(seconds)
    if total < 60 { return "\(total)s" }
    let minutes = total / 60
    if minutes < 60 { return "\(minutes)m" }
    let hours = minutes / 60
    if hours < 24 { return "\(hours)h \(minutes % 60)m" }
    return "\(hours / 24)d \(hours % 24)h"
}
