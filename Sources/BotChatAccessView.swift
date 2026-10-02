import SwiftUI

struct BotChatAccessView: View {
    @EnvironmentObject private var store: AppStore
    let rootClient: HermesAPIClient
    let rootConfig: ConnectionConfig
    let bot: ServerBot
    @State private var ready: Ready?
    @State private var failure: String?
    @State private var checking = false
    @State private var revision = 0
    @State private var generation = UUID()

    private struct Ready {
        let client: HermesAPIClient
        let config: ConnectionConfig
        let session: HermesSession
        let features: CapabilitiesResponse.Features?
        let model: String?
        let provider: String?
    }

    var body: some View {
        List {
            Section("Bot Connection") {
                Text(bot.title)
                if checking { ProgressView("Verifying profile and canonical conversation…") }
                if let failure { Text(failure).foregroundStyle(.red).textSelection(.enabled) }
                if let ready {
                    Text("Verified profile: \(bot.name)").foregroundStyle(.secondary)
                    Text(ready.config.normalizedBaseURL).font(.caption).textSelection(.enabled)
                    NavigationLink {
                        DurableRunView(client: ready.client,
                                       scope: ready.config.normalizedBaseURL + "#bot=" + bot.name,
                                       capabilities: ready.features, session: ready.session,
                                       model: ready.model, provider: ready.provider)
                    } label: { Label("Open Bot Chat", systemImage: "bubble.left.and.text.bubble.right") }
                    Text("Messages continue this Bot's canonical conversation using the model and provider reported for this profile. Run Controls provides live output, approvals, guidance, and stop controls when supported by this gateway.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button("Check Connection Again") { revision += 1 }.disabled(checking)
            }
            NavigationLink("Conversation History") { BotHistoryView(client: rootClient, bot: bot) }
        }
        .navigationTitle("Chat with \(bot.title)")
        .task(id: revision) { await prepare() }
        .onChange(of: store.savedConnections) { _, _ in revision += 1 }
    }

    @MainActor
    private func prepare() async {
        let token = UUID()
        generation = token
        ready = nil; failure = nil; checking = true
        defer { if generation == token { checking = false } }
        do {
            let config = try BotChatAccess.connection(root: rootConfig, profile: bot.name, saved: store.savedConnections)
            let roster = try await rootClient.workspaceBots()
            guard let current = roster.profile(named: bot.name) else {
                throw BotChatAccess.Failure(message: "Bot \(bot.name) is no longer present in the server roster. Return to Bots and refresh.")
            }
            guard let canonical = current.canonical_session else {
                throw BotChatAccess.Failure(message: "Bot \(bot.name) has no canonical Bot Chat conversation. Initialize its Bot Chat in Hermes, then check again. Companion cannot safely select an unrelated conversation.")
            }
            let client = HermesAPIClient(config: config)
            let capabilities = try await client.getCapabilities()
            let detail = try await client.getSession(sessionId: canonical.id)
            let session = try BotChatAccess.session(detail, canonical: canonical, profile: bot.name)
            try Task.checkCancellation()
            guard generation == token else { return }
            ready = Ready(client: client, config: config, session: session, features: capabilities.features, model: current.model, provider: current.provider)
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled, generation == token else { return }
            failure = "Bot \(bot.name) chat unavailable: \(error.localizedDescription)"
        }
    }
}
