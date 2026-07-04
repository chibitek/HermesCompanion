import SwiftUI

/// First-run setup with Liquid Glass design.
struct ConnectionSetupView: View {
    @ObservedObject var store: AppStore
    @EnvironmentObject var appearance: AppearanceSettings
    @State private var baseURL = ""
    @State private var apiKey = ""
    @State private var label = "My Hermes"
    @State private var isTesting = false
    @State private var testResult: TestResult?

    enum TestResult {
        case success(String)
        case failure(String)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                appearance.activeTheme.backgroundView
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: GlassTheme.spacingXL) {
                        // Header
                        VStack(spacing: GlassTheme.spacingM) {
                            // App icon hero
                            VStack(spacing: GlassTheme.spacingS) {
                                Image(systemName: "bubble.left.and.exclamationmark.bubble.right.fill")
                                    .font(.system(size: 36, weight: .medium))
                                    .foregroundStyle(GlassTheme.accent)
                                    .frame(width: 72, height: 72)
                                    .glassEffect(.regular.tint(GlassTheme.accent.opacity(0.15)))
                                    .clipShape(RoundedRectangle(cornerRadius: GlassTheme.radiusXL, style: .continuous))

                                Text("Hermes Companion")
                                    .font(.title2)
                                    .fontWeight(.semibold)

                                Text("Connect to your Hermes Agent")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.top, GlassTheme.spacingXL)
                        }

                        // Form fields in a glass card
                        VStack(alignment: .leading, spacing: GlassTheme.spacingM) {
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
                        .padding(GlassTheme.spacingL)
                        .glassEffect(.regular)
                        .clipShape(RoundedRectangle(cornerRadius: GlassTheme.radiusXL, style: .continuous))
                        .padding(.horizontal, GlassTheme.spacingL)

                        // Test result
                        if let result = testResult {
                            testResultView(result)
                        }

                        // Buttons
                        VStack(spacing: GlassTheme.spacingM) {
                            GlassButton("Test Connection", tint: .blue) {
                                Task { await testConnection() }
                            }
                            .disabled(isTesting || baseURL.isEmpty || apiKey.isEmpty)
                            .opacity(baseURL.isEmpty || apiKey.isEmpty ? 0.5 : 1)

                            if isTesting {
                                ProgressView()
                                    .scaleEffect(0.9)
                            }

                            Button {
                                Task { await saveAndConnect() }
                            } label: {
                                Text("Save & Connect")
                                    .font(.body)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, GlassTheme.spacingM)
                                    .background(GlassTheme.accent)
                                    .clipShape(RoundedRectangle(cornerRadius: GlassTheme.radiusM, style: .continuous))
                            }
                            .disabled(baseURL.isEmpty || apiKey.isEmpty)
                            .opacity(baseURL.isEmpty || apiKey.isEmpty ? 0.5 : 1)
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, GlassTheme.spacingL)

                        // Help text
                        VStack(alignment: .leading, spacing: GlassTheme.spacingS) {
                            Label("Tailscale IP (100.x.x.x) + port 8642", systemImage: "network")
                            Label("LAN IP (192.168.x.x) if on same network", systemImage: "wifi")
                            Label("API key is in your Hermes .env file", systemImage: "lock")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(GlassTheme.spacingL)
                        .glassEffect(.regular)
                        .clipShape(RoundedRectangle(cornerRadius: GlassTheme.radiusL, style: .continuous))
                        .padding(.horizontal, GlassTheme.spacingL)
                    }
                    .padding(.bottom, GlassTheme.spacingXL)
                }
            }
            .navigationTitle("Setup")
            .navigationBarTitleDisplayMode(.inline)
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
        VStack(alignment: .leading, spacing: GlassTheme.spacingXS) {
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
            .padding(GlassTheme.spacingM)
            .glassEffect(.regular)
            .clipShape(RoundedRectangle(cornerRadius: GlassTheme.radiusS, style: .continuous))
        }
    }

    // MARK: - Test Result

    @ViewBuilder
    private func testResultView(_ result: TestResult) -> some View {
        switch result {
        case .success(let version):
            HStack(spacing: GlassTheme.spacingS) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(version)
                    .font(.subheadline)
            }
            .padding(GlassTheme.spacingM)
            .glassEffect(.regular.tint(.green.opacity(0.1)))
            .clipShape(RoundedRectangle(cornerRadius: GlassTheme.radiusM, style: .continuous))
            .padding(.horizontal, GlassTheme.spacingL)

        case .failure(let msg):
            HStack(spacing: GlassTheme.spacingS) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(GlassTheme.danger)
                Text(msg)
                    .font(.subheadline)
            }
            .padding(GlassTheme.spacingM)
            .glassEffect(.regular.tint(GlassTheme.danger.opacity(0.1)))
            .clipShape(RoundedRectangle(cornerRadius: GlassTheme.radiusM, style: .continuous))
            .padding(.horizontal, GlassTheme.spacingL)
        }
    }

    // MARK: - Actions

    private func testConnection() async {
        isTesting = true
        testResult = nil
        let config = ConnectionConfig(baseURL: baseURL, apiKey: apiKey, label: label)
        let client = HermesAPIClient(config: config)
        do {
            let health = try await client.checkHealth()
            testResult = .success("Connected — Hermes v\(health.version ?? "unknown")")
        } catch {
            testResult = .failure(error.localizedDescription)
        }
        isTesting = false
    }

    private func saveAndConnect() async {
        let config = ConnectionConfig(baseURL: baseURL, apiKey: apiKey, label: label)
        let success = await store.connect(config: config)
        if !success {
            testResult = .failure(store.error?.message ?? "Connection failed")
        }
    }
}