import SwiftUI

/// Session picker with clean, Apple-like styling.
struct SessionPickerView: View {
    @ObservedObject var store: AppStore
    @EnvironmentObject var appearance: AppearanceSettings
    @State private var isCreating = false
    @State private var newSessionTitle = ""
    @State private var renamingSession: HermesSession?
    @State private var detailSession: HermesSession?
    @State private var renameText = ""
    @State private var searchText = ""
    @State private var sortMode: SessionSortMode = .lastActive
    @Environment(\.dismiss) private var dismiss

    private var visibleSessions: [HermesSession] {
        var result = store.sessions
        if !searchText.isEmpty {
            result = result.filter {
                ($0.title ?? "").localizedCaseInsensitiveContains(searchText) ||
                ($0.source ?? "").localizedCaseInsensitiveContains(searchText) ||
                $0.id.localizedCaseInsensitiveContains(searchText)
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

    var body: some View {
        NavigationStack {
            ZStack {
                appearance.activeTheme.backgroundView
                    .ignoresSafeArea()

                Group {
                    if store.sessions.isEmpty {
                        ContentUnavailableView(
                            "No Sessions",
                            systemImage: "tray",
                            description: Text("Create a new session to start chatting.")
                        )
                    } else if visibleSessions.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                    } else {
                        List {
                            ForEach(visibleSessions) { session in
                                Button {
                                    Task {
                                        await store.selectSession(session)
                                        dismiss()
                                    }
                                } label: {
                                    SessionRow(
                                        session: session,
                                        isActive: store.activeSession?.id == session.id
                                    )
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button {
                                        renamingSession = session
                                        renameText = session.title ?? ""
                                    } label: {
                                        Label("Rename", systemImage: "pencil")
                                    }
                                    Button {
                                        detailSession = session
                                    } label: {
                                        Label("Details", systemImage: "info.circle")
                                    }
                                    Button {
                                        Task {
                                            await store.forkSession(session)
                                            dismiss()
                                        }
                                    } label: {
                                        Label("Fork", systemImage: "arrow.triangle.branch")
                                    }
                                    Button(role: .destructive) {
                                        Task { await store.deleteSession(session) }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        Task { await store.deleteSession(session) }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    Button {
                                        renamingSession = session
                                        renameText = session.title ?? ""
                                    } label: {
                                        Label("Rename", systemImage: "pencil")
                                    }
                                    .tint(.blue)
                                }
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    Button {
                                        Task {
                                            await store.forkSession(session)
                                            dismiss()
                                        }
                                    } label: {
                                        Label("Fork", systemImage: "arrow.triangle.branch")
                                    }
                                    .tint(.purple)
                                }
                            }
                        }
                        .listStyle(.insetGrouped)
                        .scrollContentBackground(.hidden)
                        .refreshable {
                            await store.refreshSessions()
                        }
                    }
                }
            }
            .navigationTitle("Sessions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isCreating = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Sort", selection: $sortMode) {
                            ForEach(SessionSortMode.allCases) { mode in
                                Label(mode.label, systemImage: mode.icon).tag(mode)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
            .searchable(text: $searchText, prompt: "Search sessions")
            .alert("New Session", isPresented: $isCreating) {
                TextField("Title (optional)", text: $newSessionTitle)
                Button("Create") {
                    Task {
                        await store.createSession(title: newSessionTitle.isEmpty ? nil : newSessionTitle)
                        newSessionTitle = ""
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {
                    newSessionTitle = ""
                }
            }
            .alert("Rename Session", isPresented: Binding(
                get: { renamingSession != nil },
                set: { if !$0 { renamingSession = nil } }
            )) {
                TextField("Session Title", text: $renameText)
                Button("Rename") {
                    if let session = renamingSession, !renameText.isEmpty {
                        Task { await store.renameSession(session, newTitle: renameText) }
                    }
                    renamingSession = nil
                }
                Button("Cancel", role: .cancel) {
                    renamingSession = nil
                }
            }
            .sheet(item: $detailSession) { session in
                SessionDetailView(store: store, session: session)
            }
        }
    }
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

struct SessionRow: View {
    let session: HermesSession
    let isActive: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title ?? "Untitled")
                    .font(.body)
                    .fontWeight(isActive ? .semibold : .regular)

                if let source = session.source {
                    Text(source)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let count = session.messageCount {
                    Text("\(count) messages")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let date = session.lastActiveDate {
                    Text(date, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
            }
        }
        .padding(.vertical, 4)
    }
}

struct SessionDetailView: View {
    @ObservedObject var store: AppStore
    let session: HermesSession
    @Environment(\.dismiss) private var dismiss
    @State private var detail: SessionDetail?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if isLoading {
                    HStack {
                        ProgressView()
                        Text("Loading session...")
                            .foregroundStyle(.secondary)
                    }
                } else if let detail {
                    Section("Session") {
                        row("Title", detail.title ?? "Untitled")
                        row("ID", detail.id)
                        if let source = detail.source { row("Source", source) }
                        if let model = detail.model { row("Model", model) }
                        if let parent = detail.parentSessionId { row("Parent", parent) }
                    }
                    Section("Activity") {
                        if let started = detail.date { row("Started", started.formatted(date: .abbreviated, time: .shortened)) }
                        if let active = detail.lastActiveDate { row("Last Active", active.formatted(date: .abbreviated, time: .shortened)) }
                        if let count = detail.messageCount { row("Messages", "\(count)") }
                        if let count = detail.toolCallCount { row("Tool Calls", "\(count)") }
                        if let count = detail.apiCallCount { row("API Calls", "\(count)") }
                    }
                    Section("Tokens") {
                        if let count = detail.inputTokens { row("Input", count.formatted()) }
                        if let count = detail.outputTokens { row("Output", count.formatted()) }
                        if let count = detail.reasoningTokens { row("Reasoning", count.formatted()) }
                        if let count = detail.cacheReadTokens { row("Cache Read", count.formatted()) }
                        if let count = detail.cacheWriteTokens { row("Cache Write", count.formatted()) }
                    }
                    Section("Cost") {
                        if let cost = detail.estimatedCostUsd { row("Estimated", cost.formatted(.currency(code: "USD"))) }
                        if let cost = detail.actualCostUsd { row("Actual", cost.formatted(.currency(code: "USD"))) }
                    }
                    if let preview = detail.preview, !preview.isEmpty {
                        Section("Preview") {
                            Text(preview)
                                .textSelection(.enabled)
                        }
                    }
                    Section {
                        Button {
                            Task {
                                await store.forkSession(session)
                                dismiss()
                            }
                        } label: {
                            Label("Fork Session", systemImage: "arrow.triangle.branch")
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "Session Unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage ?? "Details could not be loaded.")
                    )
                }
            }
            .navigationTitle("Session Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await load()
            }
            .refreshable {
                await load()
            }
        }
    }

    private func load() async {
        guard let client = store.apiClient else {
            errorMessage = "Not connected"
            return
        }
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
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }
}

private extension HermesSession {
    var lastActiveDate: Date? {
        guard let lastActive else { return nil }
        return Date(timeIntervalSince1970: lastActive)
    }
}
