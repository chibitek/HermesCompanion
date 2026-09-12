import SwiftUI

struct BotHistoryView: View {
    let client: HermesAPIClient
    let bot: ServerBot

    var body: some View {
        WorkspaceHistoryView(title: bot.title, identity: bot.name) { offset in
            try await client.botHistory(profile: bot.name, offset: offset)
        }
    }
}

struct WorkspaceHistoryView: View {
    let title: String
    let identity: String
    let load: (Int) async throws -> BotHistory
    @State private var offset = 0

    var body: some View {
        WorkspaceReadView(load: { try await load(offset) },
                          refreshAutomatically: offset == 0) { history in
            Section {
                if offset > 0 {
                    Button { offset = max(0, offset - history.pagination.limit) } label: {
                        Label("Newer Messages", systemImage: "arrow.up")
                    }
                }
                if history.session_id == nil {
                    ContentUnavailableView("No Conversation", systemImage: "bubble.left")
                } else if history.messages.isEmpty {
                    ContentUnavailableView("No Messages", systemImage: "bubble.left")
                }
            }
            ForEach(history.messages) { message in
                if let text = message.visibleText, !text.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(message.role.capitalized).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(text).font(.body).textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if history.pagination.returned == history.pagination.limit {
                Button { offset += history.pagination.limit } label: {
                    Label("Older Messages", systemImage: "arrow.down")
                }
            }
        }
        .id("\(identity):\(offset)")
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
