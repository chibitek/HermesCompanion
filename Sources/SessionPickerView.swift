import SwiftUI

/// Session picker with clean, Apple-like styling.
struct SessionPickerView: View {
    @ObservedObject var store: AppStore
    @EnvironmentObject var appearance: AppearanceSettings
    @State private var isCreating = false
    @State private var newSessionTitle = ""
    @State private var renamingSession: HermesSession?
    @State private var renameText = ""
    @Environment(\.dismiss) private var dismiss

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
                    } else {
                        List {
                            ForEach(store.sessions) { session in
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
                                    Button(role: .destructive) {
                                        Task { await store.deleteSession(session) }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
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
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
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
