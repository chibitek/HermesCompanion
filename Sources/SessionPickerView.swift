import SwiftUI

/// Session picker with Liquid Glass styling.
struct SessionPickerView: View {
    @ObservedObject var store: AppStore
    @State private var isCreating = false
    @State private var newSessionTitle = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color(.systemBackground), Color(.secondarySystemBackground)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                Group {
                    if store.sessions.isEmpty {
                        ContentUnavailableView(
                            "No Sessions",
                            systemImage: "tray",
                            description: Text("Create a new session to start chatting.")
                        )
                    } else {
                        ScrollView {
                            LazyVStack(spacing: GlassTheme.spacingS) {
                                ForEach(store.sessions) { session in
                                    Button {
                                        Task {
                                            await store.selectSession(session)
                                            dismiss()
                                        }
                                    } label: {
                                        GlassSessionRow(
                                            session: session,
                                            isActive: store.activeSession?.id == session.id
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            Task { await store.deleteSession(session) }
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                            .padding(GlassTheme.spacingL)
                        }
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
        }
    }
}

struct GlassSessionRow: View {
    let session: HermesSession
    let isActive: Bool

    var body: some View {
        HStack(spacing: GlassTheme.spacingM) {
            VStack(alignment: .leading, spacing: GlassTheme.spacingXS) {
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
                    .foregroundStyle(GlassTheme.accent)
            }
        }
        .padding(GlassTheme.spacingM)
        .glassEffect(isActive ? .regular.tint(GlassTheme.accent.opacity(0.12)) : .regular)
        .clipShape(RoundedRectangle(cornerRadius: GlassTheme.radiusL, style: .continuous))
    }
}