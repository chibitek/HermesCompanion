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
                    if store.connectionConfig != nil && store.capabilities == nil {
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

/// Routes between splash, setup, and main chat based on connection state.
struct RootView: View {
    @ObservedObject var store: AppStore
    @EnvironmentObject var appearance: AppearanceSettings
    @State private var showSplash = true

    var body: some View {
        ZStack {
            if showSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(1)
            }

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
        .onAppear {
            // Fade out the splash after 1.8 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                withAnimation(.easeOut(duration: 0.6)) {
                    showSplash = false
                }
            }
        }
    }
}

/// Full-screen logo splash shown on app launch. Fades in over 0.4s,
/// holds for ~1.2s, then RootView fades it out over 0.6s.
struct SplashView: View {
    @State private var logoOpacity: Double = 0
    @State private var logoScale: Double = 0.92

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                if let logo = UIImage(named: "logo") {
                    Image(uiImage: logo)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 200, height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 44))
                        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
                } else {
                    // Fallback: use the app icon from the asset catalog
                    Image("AppIcon")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 200, height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 44))
                        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
                }

                Text("Hermes Companion")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)

                Text("by Chibitek Labs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .opacity(logoOpacity)
            .scaleEffect(logoScale)
        }
        .onAppear {
            withAnimation(.easeIn(duration: 0.4)) {
                logoOpacity = 1
                logoScale = 1.0
            }
        }
    }
}
