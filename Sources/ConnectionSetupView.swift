import SwiftUI

/// First-run setup with clean, Apple-like Form design.
struct ConnectionSetupView: View {
    @ObservedObject var store: AppStore
    @EnvironmentObject var appearance: AppearanceSettings
    @State private var baseURL = ""
    @State private var apiKey = ""
    @State private var label = "My Hermes"
    @State private var isTesting = false
    
    // Whether we're editing an existing connection
    private let initialConfig: ConnectionConfig?

    init(store: AppStore, initialConfig: ConnectionConfig? = nil) {
        self.store = store
        self.initialConfig = initialConfig
    }

    private var versionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        return "\(version) ($build)"
    }
    @State private var testResult: TestResult?
    
    enum TestResult {
        case success(String)
        case failure(String)
    }

    var body: some View {
        NavigationStack {
            Form {
                // Header
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "bubble.left.and.exclamationmark.bubble.right.fill")
                            .font(.system(size: 36, weight: .medium))
                            .foregroundStyle(appearance.accent)
                            .frame(width: 72, height: 72)

                        Text("Hermes Companion")
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text(initialConfig == nil ? "Connect to your Hermes Agent" : "Edit Server Connection")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text(versionString)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }

                // Connection fields
                Section("Connection Details") {
                    setupField(
                        title: "Hermes URL",
                        text: $baseURL,
                        placeholder: "http://100.x.x.x:8642",
                        icon: "globe",
                        keyboardType: .URL
                    )

                    setupField(
                        title: "API Key",
                        text: $apiKey,
                        placeholder: "API_SERVER_KEY",
                        icon: "key.fill",
                        isSecure: true
                    )

                    setupField(
                        title: "Label",
                        text: $label,
                        placeholder: "My Hermes",
                        icon: "tag"
                    )
                }

                // Test result
                if let result = testResult {
                    Section {
                        testResultView(result)
                    }
                }

                // Buttons
                Section {
                    HStack {
                        Spacer()
                        Button {
                            Task { await testConnection() }
                        } label: {
                            HStack(spacing: 6) {
                                if isTesting {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                }
                                Text("Test Connection")
                            }
                        }
                        .disabled(isTesting || baseURL.isEmpty || apiKey.isEmpty)

                        Spacer()

                        Button {
                            Task { await saveAndConnect() }
                        } label: {
                            Text(initialConfig == nil ? "Save & Connect" : "Update")
                                .fontWeight(.semibold)
                        }
                        .disabled(baseURL.isEmpty || apiKey.isEmpty)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }

                // Help text
                Section("Tips") {
                    Label("Tailscale IP (100.x.x.x) + port 8642", systemImage: "network")
                    Label("LAN IP (192.168.x.x) if on same network", systemImage: "wifi")
                    Label("API key is in your Hermes .env file", systemImage: "lock")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .navigationTitle(initialConfig == nil ? "Setup" : "Edit Server")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                prefillDebugConnectionIfAvailable()
                prefillExistingConnectionIfAvailable()
            }
        }
    }

    // MARK: - Field Component

    private func setupField(
        title: String,
        text: Binding<String>,
        placeholder: String,
        icon: String,
        isSecure: Bool = false,
        keyboardType: UIKeyboardType = .default
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)

            Group {
                if isSecure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                        .keyboardType(keyboardType)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        }
    }

    // MARK: - Test Result

    @ViewBuilder
    private func testResultView(_ result: TestResult) -> some View {
        switch result {
        case .success(let version):
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(version)
                    .font(.subheadline)
            }

        case .failure(let msg):
            HStack(spacing: 8) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                Text(msg)
                    .font(.subheadline)
            }
        }
    }

    // MARK: - Actions

    private func testConnection() async {
        isTesting = true
        testResult = nil
        let config = ConnectionConfig(baseURL: baseURL, apiKey: apiKey, label: label)
        let client = HermesAPIClient(config: config)
        do {
            // Timeout wrapper: if the server is unreachable, fail fast instead of
            // spinning forever (waitsForConnectivity keeps URLSession retrying).
            let result: (HealthResponse, CapabilitiesResponse)
            do {
                result = try await Self.runWithTimeout(seconds: 10) {
                    let health = try await client.checkHealth()
                    let caps = try await client.getCapabilities()
                    return (health, caps)
                }
                testResult = .success("Connected — Hermes v\(result.0.version ?? "unknown")")
            } catch {
                testResult = .failure(error.localizedDescription)
            }
        } catch let error as APIError {
            testResult = .failure(error.errorDescription ?? "Connection failed")
        } catch {
            testResult = .failure(error.localizedDescription)
        }
        isTesting = false
    }

    /// Run an async operation with a hard timeout.
    private static func runWithTimeout<T>(seconds: Double, operation: @escaping @Sendable () async throws -> T) async throws -> T {
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask(operation: operation)
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw URLError(.cancelled)
            }
            guard let result = try await group.next() else { throw URLError(.cancelled) }
            group.cancelAll()
            return result
        }
    }

    private func saveAndConnect() async {
        let config = ConnectionConfig(baseURL: baseURL, apiKey: apiKey, label: label)
        
        // If we're editing an existing connection with the same baseURL, update it
        if let initialConfig = initialConfig, initialConfig.baseURL == baseURL {
            // Update the existing connection in keychain
            do {
                try KeychainManager.shared.addOrUpdate(config)
                // If this was the active connection, update it by reconnecting
                if store.connectionConfig?.baseURL == baseURL {
                    // Update the saved connections list
                    store.savedConnections = KeychainManager.shared.loadAll()
                    // Reconnect to update the active connection
                    _ = await store.connect(config: config)
                    return
                }
                // Update the saved connections list
                store.savedConnections = KeychainManager.shared.loadAll()
            } catch {
                testResult = .failure("Failed to update connection: \(error.localizedDescription)")
                return
            }
        } else {
            // Save as new connection
            do {
                try KeychainManager.shared.addOrUpdate(config)
                store.savedConnections = KeychainManager.shared.loadAll()
            } catch {
                testResult = .failure("Failed to save connection: \(error.localizedDescription)")
                return
            }
        }
        
        // Connect to the new/updated configuration
        let success = await store.connect(config: config)
        if !success {
            testResult = .failure(store.error?.message ?? "Connection failed")
        }
    }

    private func prefillExistingConnectionIfAvailable() {
        guard let config = initialConfig else { return }
        baseURL = config.baseURL
        apiKey = config.apiKey
        label = config.label
    }
    
    private func prefillDebugConnectionIfAvailable() {
        #if DEBUG
        let defaults = UserDefaults.standard
        if baseURL.isEmpty, let value = defaults.string(forKey: "debug_baseURL"), !value.isEmpty {
            baseURL = value
        }
        if apiKey.isEmpty, let value = defaults.string(forKey: "debug_apiKey"), !value.isEmpty {
            apiKey = value
        }
        if label == "My Hermes", let value = defaults.string(forKey: "debug_label"), !value.isEmpty {
            label = value
        }
        #endif
    }
}
