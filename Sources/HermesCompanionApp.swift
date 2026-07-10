import SwiftUI
import UserNotifications

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
                    // Request notification permission so we can alert the
                    // user when a chat response arrives while backgrounded.
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
                }
                .onChange(of: scenePhase) { _, newPhase in
                                    switch newPhase {
                                    case .active:
                                        store.handleForegroundReturn()
                                        Task { await store.reconnectIfNeeded() }
                                    case .background:
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

/// Routes between splash, server picker, setup, and main chat.
struct RootView: View {
    @ObservedObject var store: AppStore
    @EnvironmentObject var appearance: AppearanceSettings
    @State private var showSplash = true
    @State private var splashFinished = false
    @State private var autoConnectAttempted = false
    @State private var showServerPicker = false

    var body: some View {
        ZStack {
            if showSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(1)
            } else if store.isLoadingConnection {
                ConnectingView()
            } else if store.isConnected {
                ChatView(store: store)
                    .task {
                        try? await Task.sleep(nanoseconds: 100_000_000)
                        await MainActor.run {
                            if store.activeSession == nil {
                                Task {
                                    if store.sessions.isEmpty {
                                        await store.refreshSessions()
                                    }
                                    // Always create a fresh session for the app —
                                    // reusing an existing Hermes session pulls in
                                    // its system prompt, tools, and context, which
                                    // causes the model to make tool calls, hit the
                                    // iteration limit, and drop the SSE connection.
                                    await store.createSession(title: nil)
                                }
                            }
                        }
                    }
            } else if showServerPicker {
                ServerPickerView(store: store, appearance: appearance) { config in
                    Task {
                        store.connectionConfig = config
                        await store.autoConnect()
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
                splashFinished = true
            }
        }
        .onChange(of: splashFinished) { _, finished in
            guard finished, !autoConnectAttempted else { return }
            autoConnectAttempted = true
            Task {
                // If we have saved connections, ping all of them for health status
                if !store.savedConnections.isEmpty {
                    await store.checkAllServerHealth()
                }
                // Try auto-connecting to the last active server
                if store.connectionConfig != nil {
                    await store.autoConnect()
                    // If auto-connect failed, show the server picker instead of
                    // the full setup screen
                    if !store.isConnected && !store.savedConnections.isEmpty {
                        showServerPicker = true
                    }
                } else if !store.savedConnections.isEmpty {
                    // No active config but we have saved servers — show picker
                    showServerPicker = true
                }
            }
        }
    }
}

/// Loading spinner shown while connecting to a server.
struct ConnectingView: View {
    var body: some View {
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
    }
}

/// Server picker shown after splash when auto-connect fails or when there
/// are multiple saved servers. Shows health status (online/offline) for each
/// so the user doesn't waste time tapping a server that's known to be down.
struct ServerPickerView: View {
    @ObservedObject var store: AppStore
    var appearance: AppearanceSettings
    var onSelect: (ConnectionConfig) -> Void

    private var theme: any HermesTheme { appearance.activeTheme }

    var body: some View {
        ZStack {
            theme.backgroundView.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    // Logo
                    Image("Logo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 100, height: 100)
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                        .shadow(color: .black.opacity(0.3), radius: 12, y: 6)

                    Text("Select a Server")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundStyle(theme.textPrimary)

                    Text("Tap a server to connect. Health status is checked automatically.")
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    // Server list
                    ForEach(store.savedConnections, id: \.baseURL) { config in
                        serverRow(config)
                    }

                    // Add new server button
                    Button {
                        onSelect(ConnectionConfig(baseURL: "", apiKey: "", label: "New Server"))
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                            Text("Add New Server")
                                .font(.body)
                                .fontWeight(.medium)
                        }
                        .foregroundStyle(theme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(theme.accent.opacity(0.4), lineWidth: 1)
                        )
                    }
                    .padding(.horizontal, 24)

                    // Retry health check button
                    Button {
                        Task { await store.checkAllServerHealth() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                            Text("Re-check all servers")
                        }
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                    }
                    .padding(.top, 8)
                }
                .padding(.vertical, 24)
            }
        }
    }

    private func serverRow(_ config: ConnectionConfig) -> some View {
        let health = store.serverHealthStatus[config.baseURL]
        let isOnline = health?.status == .online
        let isChecking = health?.status == .checking
        let isLastUsed = store.connectionConfig?.baseURL == config.baseURL

        return Button {
            onSelect(config)
        } label: {
            HStack(spacing: 14) {
                // Health indicator
                ZStack {
                    Circle()
                        .fill(statusColor(isOnline: isOnline, isChecking: isChecking).opacity(0.15))
                        .frame(width: 44, height: 44)
                    if isChecking {
                        ProgressView()
                            .scaleEffect(0.6)
                    } else {
                        Circle()
                            .fill(statusColor(isOnline: isOnline, isChecking: isChecking))
                            .frame(width: 12, height: 12)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(config.label)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(theme.textPrimary)
                        if isLastUsed {
                            Text("LAST")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(theme.accent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(theme.accent.opacity(0.15)))
                        }
                    }
                    Text(config.baseURL)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let latency = health?.latencyMs, isOnline {
                        Text("\(latency)ms")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(latency < 100 ? .green : (latency < 500 ? .orange : .red))
                    } else if isOnline {
                        Text("Online")
                            .font(.system(size: 11))
                            .foregroundStyle(.green)
                    } else if isChecking {
                        Text("Checking...")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.textSecondary)
                    } else {
                        Text("Offline")
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                    }
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(theme.textSecondary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(theme.bgSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isLastUsed ? theme.accent.opacity(0.3) : theme.cardBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(isChecking ? 0.7 : 1.0)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
    }

    private func statusColor(isOnline: Bool, isChecking: Bool) -> Color {
        if isOnline { return .green }
        if isChecking { return theme.textSecondary }
        return .red
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
                // Use "Logo" (capital L) to match the imageset name in the asset catalog
                Image("Logo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 200, height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 44))
                    .shadow(color: .black.opacity(0.3), radius: 20, y: 10)

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
