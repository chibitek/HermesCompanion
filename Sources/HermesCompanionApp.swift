import SwiftUI

@main
struct HermesCompanionApp: App {
    @StateObject private var store = AppStore()
    @StateObject private var appearance = AppearanceSettings()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView(store: store)
                .environmentObject(appearance)
                .preferredColorScheme(effectiveColorScheme)
                .tint(appearance.accent)
                .task {
                    // Auto-connect if a saved config exists in Keychain.
                    // AppStore.init already loads it into connectionConfig;
                    // here we verify the server is reachable and populate
                    // capabilities/sessions so the user goes straight to chat.
                    if store.connectionConfig != nil && !store.isConnected {
                        await store.autoConnect()
                    }
                }
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .active:
                        // App returned to foreground. Reconnect if needed.
                        Task { await store.reconnectIfNeeded() }
                    case .background:
                        // App went to background. Start a brief background task
                        // to keep the connection alive during quick app switches.
                        store.beginBackgroundKeepAlive()
                    case .inactive:
                        break
                    @unknown default:
                        break
                    }
                }
        }
    }

    /// Force dark mode for themes that are inherently dark (Matrix, Cyberpunk).
    /// For the default Hermes theme, respect the user's color scheme picker.
    private var effectiveColorScheme: ColorScheme? {
        let theme = appearance.activeTheme
        if !theme.usesGlass {
            return .dark  // Matrix: always dark
        }
        if theme.id == "cyberpunk" {
            return .dark  // Cyberpunk: always dark
        }
        return appearance.preferredColorScheme
    }
}

/// Routes between setup and main chat based on connection state.
struct RootView: View {
    @ObservedObject var store: AppStore
    @EnvironmentObject var appearance: AppearanceSettings

    var body: some View {
        if store.isLoadingConnection {
            // Auto-login in progress — show a clean loading screen
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.2)
                Text("Connecting to Hermes...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))
            .ignoresSafeArea()
        } else if store.isConnected {
            ChatView(store: store)
                .task {
                    // Delay to avoid publishing changes during view update
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
                    await MainActor.run {
                        if store.activeSession == nil {
                            Task {
                                if store.sessions.isEmpty {
                                    await store.refreshSessions()
                                }
                                if !store.sessions.isEmpty {
                                    await store.selectSession(store.sessions[0])
                                }
                            }
                        }
                    }
                }
        } else {
            ConnectionSetupView(store: store)
        }
    }
}