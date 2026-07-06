import SwiftUI

/// Session picker matching the design handoff: dark base, sticky glass header,
/// glass card rows, mono teal subtype tags, bottom glass search bar.
struct SessionPickerView: View {
    @ObservedObject var store: AppStore
    @EnvironmentObject var appearance: AppearanceSettings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.activeTheme) private var theme

    @State private var isCreating = false
    @State private var newSessionTitle = ""
    @State private var renamingSession: HermesSession?
    @State private var detailSession: HermesSession?
    @State private var renameText = ""
    @State private var searchText = ""
    @State private var sortMode: SessionSortMode = .lastActive
    @State private var showSortOptions = false

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
        ZStack {
            // Deep base background from theme (#0A0E16)
            theme.backgroundView
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Sticky glass header
                SessionsHeader(
                    onDone: { dismiss() },
                    onNew: { isCreating = true },
                    onSort: { showSortOptions = true }
                )
                .zIndex(1)

                Divider()
                    .background(theme.cardBorder)
                    .zIndex(1)

                if store.sessions.isEmpty {
                    Spacer()
                    ContentUnavailableView(
                        "No Sessions",
                        systemImage: "tray",
                        description: Text("Create a new session to start chatting.")
                    )
                    .foregroundStyle(theme.textPrimary)
                    Spacer()
                } else if visibleSessions.isEmpty {
                    Spacer()
                    ContentUnavailableView.search(text: searchText)
                        .foregroundStyle(theme.textPrimary)
                    Spacer()
                } else {
                    // Scrollable session list
                    ScrollView {
                        LazyVStack(spacing: theme.spacingS) {
                            ForEach(visibleSessions) { session in
                                SessionRowButton(
                                    session: session,
                                    isActive: store.activeSession?.id == session.id,
                                    onSelect: {
                                        Task {
                                            await store.selectSession(session)
                                            dismiss()
                                        }
                                    },
                                    onRename: {
                                        renamingSession = session
                                        renameText = session.title ?? ""
                                    },
                                    onDetails: {
                                        detailSession = session
                                    },
                                    onFork: {
                                        Task {
                                            await store.forkSession(session)
                                            dismiss()
                                        }
                                    },
                                    onDelete: {
                                        Task { await store.deleteSession(session) }
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, theme.spacingM)
                        .padding(.top, theme.spacingS)
                        .padding(.bottom, theme.spacingXL + 60) // space for floating search bar
                    }
                    .refreshable {
                        await store.refreshSessions()
                    }
                }

            Spacer(minLength: 0)
        }

            // Bottom glass search bar
            VStack {
                Spacer()
                HStack(spacing: theme.spacingS) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(theme.textMuted)

                    TextField("Search sessions", text: $searchText)
                        .font(theme.uiFont)
                        .foregroundStyle(theme.textPrimary)
                }
                .padding(.horizontal, theme.spacingM)
                .padding(.vertical, theme.spacingS + 2)
                .background(
                    AnyView(theme.glassCard(cornerRadius: theme.radiusS))
                )
                .padding(.horizontal, theme.spacingM)
                .padding(.bottom, theme.spacingM)
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
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
        .confirmationDialog("Sort Sessions", isPresented: $showSortOptions, titleVisibility: .visible) {
            ForEach(SessionSortMode.allCases) { mode in
                Button {
                    sortMode = mode
                } label: {
                    Label(mode.label, systemImage: mode.icon)
                }
            }
            Button("Cancel", role: .cancel) { }
        }
    }
}

// MARK: - Sticky Glass Header

private struct SessionsHeader: View {
    @EnvironmentObject var appearance: AppearanceSettings
    @Environment(\.activeTheme) private var theme

    let onDone: () -> Void
    let onNew: () -> Void
    let onSort: () -> Void

    var body: some View {
        HStack(spacing: theme.spacingS) {
            Button(action: onDone) {
                Text("Done")
                    .font(theme.uiFont.weight(.semibold))
                    .foregroundStyle(theme.accent)
            }
            .buttonStyle(.plain)

            Spacer()

            Text("Sessions")
                .font(theme.uiFont.weight(.bold))
                .foregroundStyle(theme.textPrimary)

            Spacer()

                HStack(spacing: theme.spacingXS) {
                Button(action: onNew) {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(theme.accent)
                        .frame(width: 38, height: 32)
                        .background(
                            AnyView(theme.glassCard(cornerRadius: theme.controlRadius))
                        )
                }
                .buttonStyle(.plain)

                Button(action: onSort) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(theme.accent)
                        .frame(width: 38, height: 32)
                        .background(
                            AnyView(theme.glassCard(cornerRadius: theme.controlRadius))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, theme.spacingM)
        .padding(.vertical, theme.spacingS)
        .background(
            AnyView(
                theme.glassCard(cornerRadius: 0)
                    .opacity(0.9)
            )
        )
    }
}

// MARK: - Session Sort Mode

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

// MARK: - Session Row Button

private struct SessionRowButton: View {
    let session: HermesSession
    let isActive: Bool
    let onSelect: () -> Void
    let onRename: () -> Void
    let onDetails: () -> Void
    let onFork: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onSelect) {
            SessionRow(session: session, isActive: isActive)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(action: onRename) {
                Label("Rename", systemImage: "pencil")
            }
            Button(action: onDetails) {
                Label("Details", systemImage: "info.circle")
            }
            Button(action: onFork) {
                Label("Fork", systemImage: "arrow.triangle.branch")
            }
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Session Row

struct SessionRow: View {
    @EnvironmentObject var appearance: AppearanceSettings
    @Environment(\.activeTheme) private var theme

    let session: HermesSession
    let isActive: Bool

    var body: some View {
        HStack(alignment: .center, spacing: theme.spacingS) {
            VStack(alignment: .leading, spacing: theme.spacingXS) {
                Text(session.title ?? "Untitled")
                    .font(theme.uiFont.weight(.semibold))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(2)

                Text(subtypeLabel)
                    .font(.system(.caption, design: .monospaced, weight: .medium))
                    .foregroundStyle(theme.accent)

                Text(metadata)
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
            }
            .multilineTextAlignment(.leading)

            Spacer()

            if isActive {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(red: 0.012, green: 0.137, blue: 0.118)) // #03231e on teal
                    .frame(width: 22, height: 22)
                    .background(theme.accent)
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, theme.spacingM)
        .padding(.vertical, theme.spacingS + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            AnyView(theme.glassCard(cornerRadius: theme.radiusM))
                .overlay(
                    AnyView(
                        RoundedRectangle(cornerRadius: theme.radiusM, style: .continuous)
                            .stroke(isActive ? theme.accent.opacity(0.35) : theme.cardBorder, lineWidth: isActive ? 1.5 : theme.cardBorderWidth)
                    )
                )
        )
        .contentShape(Rectangle())
        }

        /// Mono teal subtype tag shown under the title.
        private var subtypeLabel: String {
        session.source?.lowercased() ?? "api_server"
    }

    /// Metadata line: "{messageCount} messages · {duration}".
    private var metadata: String {
        let count = session.messageCount ?? 0
        let countText = count == 1 ? "1 message" : "\(count) messages"
        return "\(countText) · \(durationText)"
    }

    /// Human-readable duration between session start and last activity.
    private var durationText: String {
        let end = session.lastActive ?? session.startedAt ?? Date().timeIntervalSince1970
        let start = session.startedAt ?? end
        let duration = max(0, end - start)
        return formatDuration(duration)
    }
}

// MARK: - Session Detail

struct SessionDetailView: View {
    @ObservedObject var store: AppStore
    @EnvironmentObject var appearance: AppearanceSettings
    @Environment(\.activeTheme) private var theme
    let session: HermesSession
    @Environment(\.dismiss) private var dismiss
    @State private var detail: SessionDetail?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                theme.backgroundView
                    .ignoresSafeArea()

                List {
                    if isLoading {
                        HStack {
                            ProgressView()
                            Text("Loading session...")
                                .foregroundStyle(theme.textSecondary)
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
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Session Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(theme.accent)
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
                .foregroundStyle(theme.textSecondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
                .foregroundStyle(theme.textPrimary)
        }
    }
}

// MARK: - Helpers

private func formatDuration(_ interval: TimeInterval) -> String {
    let totalSeconds = Int(interval)
    let seconds = totalSeconds % 60
    let minutes = (totalSeconds / 60) % 60
    let hours = totalSeconds / 3600
    let days = totalSeconds / 86400

    if days > 0 {
        let remainingHours = (totalSeconds % 86400) / 3600
        if remainingHours > 0 {
            return "\(days) day\(days == 1 ? "" : "s"), \(remainingHours) hr"
        }
        return "\(days) day\(days == 1 ? "" : "s")"
    } else if hours > 0 {
        return "\(hours) hr, \(minutes) min"
    } else if minutes > 0 {
        if seconds > 0 {
            return "\(minutes) min, \(seconds) sec"
        }
        return "\(minutes) min"
    } else {
        return "\(seconds) sec"
    }
}

private extension HermesSession {
    var lastActiveDate: Date? {
        guard let lastActive else { return nil }
        return Date(timeIntervalSince1970: lastActive)
    }
}
