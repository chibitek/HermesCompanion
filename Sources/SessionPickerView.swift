import SwiftUI

/// Session picker: list, create, select, delete sessions.
struct SessionPickerView: View {
    @ObservedObject var store: AppStore
    @State private var isCreating = false
    @State private var newSessionTitle = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if store.sessions.isEmpty {
                    ContentUnavailableView(
                        "No Sessions",
                        systemImage: "tray",
                        description: Text("Create a new session to start chatting.")
                    )
                } else {
                    ForEach(store.sessions) { session in
                        Button {
                            Task {
                                await store.selectSession(session)
                                dismiss()
                            }
                        } label: {
                            SessionRow(session: session, isActive: store.activeSession?.id == session.id)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task { await store.deleteSession(session) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
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
            .refreshable {
                await store.refreshSessions()
            }
        }
    }
}

struct SessionRow: View {
    let session: HermesSession
    let isActive: Bool

    var body: some View {
        HStack {
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
                    .foregroundStyle(.blue)
            }
        }
        .padding(.vertical, 4)
    }
}