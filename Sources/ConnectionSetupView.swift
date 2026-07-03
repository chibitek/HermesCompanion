import SwiftUI

/// First-run setup: configure Hermes connection URL and API key.
struct ConnectionSetupView: View {
    @ObservedObject var store: AppStore
    @State private var baseURL = ""
    @State private var apiKey = ""
    @State private var label = "My Hermes"
    @State private var isTesting = false
    @State private var testResult: TestResult?
    @State private var showSavedConfigs = false

    enum TestResult {
        case success(String)
        case failure(String)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Hermes URL", text: $baseURL, prompt: Text("http://100.x.x.x:8642"))
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    SecureField("API Key", text: $apiKey, prompt: Text("API_SERVER_KEY"))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    TextField("Label", text: $label, prompt: Text("My Hermes"))
                } header: {
                    Text("Connection")
                } footer: {
                    Text("Enter the URL of your Hermes gateway API server. With Tailscale, use the Tailscale IP (100.x.x.x). On local network, use the machine IP (192.168.x.x). The API key is set as API_SERVER_KEY in your Hermes .env file.")
                }

                Section {
                    Button {
                        Task { await testConnection() }
                    } label: {
                        HStack {
                            if isTesting {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                            Text(isTesting ? "Testing..." : "Test Connection")
                        }
                    }
                    .disabled(isTesting || baseURL.isEmpty || apiKey.isEmpty)

                    if let result = testResult {
                        switch result {
                        case .success(let version):
                            Label(version, systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        case .failure(let msg):
                            Label(msg, systemImage: "xmark.circle.fill")
                                .foregroundStyle(.red)
                        }
                    }
                }

                Section {
                    Button {
                        Task { await saveAndConnect() }
                    } label: {
                        Text("Save & Connect")
                            .bold()
                    }
                    .disabled(baseURL.isEmpty || apiKey.isEmpty)
                }
            }
            .navigationTitle("Setup")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func testConnection() async {
        isTesting = true
        testResult = nil
        let config = ConnectionConfig(baseURL: baseURL, apiKey: apiKey, label: label)
        let client = HermesAPIClient(config: config)
        do {
            let health = try await client.checkHealth()
            testResult = .success("Connected — Hermes v\(health.version)")
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