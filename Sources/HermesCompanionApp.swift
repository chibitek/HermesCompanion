import SwiftUI

@main
struct HermesCompanionApp: App {
    @StateObject private var store = AppStore()
    @StateObject private var appearance = AppearanceSettings()

    var body: some Scene {
        WindowGroup {
            RootView(store: store)
                .environmentObject(appearance)
                .preferredColorScheme(appearance.preferredColorScheme)
                .tint(appearance.accent)
        }
    }
}

/// Routes between setup and main chat based on connection state.
struct RootView: View {
    @ObservedObject var store: AppStore
    @EnvironmentObject var appearance: AppearanceSettings

    var body: some View {
        if store.isConnected {
            ChatView(store: store)
                .task {
                    if store.activeSession == nil && !store.sessions.isEmpty {
                        await store.selectSession(store.sessions[0])
                    }
                }
        } else {
            ConnectionSetupView(store: store)
        }
    }
}