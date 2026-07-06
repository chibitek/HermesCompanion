import SwiftUI

/// First-run setup redesigned per the handoff spec.
/// Brand header, dark base (#0A0E16), glass card fields, teal primary accent.
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
        return "\(version) (\(build))"
    }
    
    @State private var testResult: TestResult?
    @State private var showChooseServer = false
    @State private var selectedServerIndex: Int? = nil
    @State private var addNewServer = false
    
    enum TestResult {
        case success(String)
        case failure(String)
        
        func isFailure() -> Bool {
            if case .failure = self { return true }
            return false
        }
    }
    
    private var isFormValid: Bool {
        !baseURL.isEmpty && !apiKey.isEmpty
    }
    
    private var isConnecting: Bool {
        isTesting || (initialConfig == nil && testResult == nil) // Only during first save+connect
    }

    var body: some View {
        NavigationStack {
            ZStack {
                appearance.activeTheme.backgroundView
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 28) {
                        brandHeader
                        
                        // Server picker section
                        if !store.savedConnections.isEmpty {
                            serverPickerSection
                        }
                        
                        VStack(spacing: 16) {
                            glassField(title: "Hermes URL", text: $baseURL, placeholder: "http://100.x.x.x:8642", icon: "globe", keyboardType: .URL)
                            glassField(title: "API Key", text: $apiKey, placeholder: "API_SERVER_KEY", icon: "key.fill", isSecure: true)
                            glassField(title: "Label", text: $label, placeholder: "My Hermes", icon: "tag")
                        }
                        
                        // "Add New Server" divider when servers exist
                        if !store.savedConnections.isEmpty {
                            addNewDivider
                        }
                        
                        if let result = testResult {
                            testResultView(result)
                                .padding(.horizontal, 6)
                        }
                        
                        actionButtons
                        
                        tipsSection
                        
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 24)
                }
            }
            .navigationTitle(initialConfig == nil ? "Connect" : "Edit Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if initialConfig != nil {
                        Button("Done") {
                            // Let user dismiss if editing
                        }
                        .foregroundStyle(appearance.accent)
                    }
                }
            }
            .onAppear {
                prefillDebugConnectionIfAvailable()
                prefillExistingConnectionIfAvailable()
            }
            .sheet(isPresented: $showChooseServer) {
                serverPickerSheet
            }
        }
    }
    
    // MARK: - Brand Header
    
    private var brandHeader: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(colors: [appearance.accent, appearance.accentSecondary],
                                         startPoint: .topLeading,
                                         endPoint: .bottomTrailing))
                    .frame(width: 64, height: 64)
                    .shadow(color: appearance.accent.opacity(0.45), radius: 18, x: 0, y: 6)
                
                Text("H")
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(red: 0.039, green: 0.055, blue: 0.086))
            }
            
            VStack(spacing: 4) {
                Text("Hermes Companion")
                    .font(.system(size: 22, weight: .bold, design: .default))
                    .foregroundStyle(Color(red: 0.949, green: 0.965, blue: 0.988))
                
                Text(initialConfig == nil ? "Connect to your Hermes Agent" : "Edit Server Connection")
                    .font(.subheadline)
                    .foregroundStyle(Color(red: 0.494, green: 0.557, blue: 0.651))
                
                Text(versionString)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(red: 0.361, green: 0.420, blue: 0.518))
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
    }
    
    // MARK: - Glass Field
    
    private func glassField(
        title: String,
        text: Binding<String>,
        placeholder: String,
        icon: String,
        isSecure: Bool = false,
        keyboardType: UIKeyboardType = .default
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(red: 0.494, green: 0.557, blue: 0.651))
            
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(red: 0.118, green: 0.164, blue: 0.250).opacity(0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.07), lineWidth: 1)
                    )
                
                Group {
                    if isSecure {
                        SecureField(placeholder, text: text)
                            .textContentType(.password)
                    } else {
                        TextField(placeholder, text: text)
                            .keyboardType(keyboardType)
                    }
                }
                .font(.body)
                .foregroundStyle(Color(red: 0.859, green: 0.894, blue: 0.945))
                .tint(appearance.accent)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
            }
            .frame(height: 50)
        }
    }
    
    // MARK: - Test Result
    
    @ViewBuilder
    private func testResultView(_ result: TestResult) -> some View {
        HStack(spacing: 10) {
            switch result {
            case .success(let msg):
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(appearance.accent)
                Text(msg)
                    .font(.subheadline)
                    .foregroundStyle(Color(red: 0.859, green: 0.894, blue: 0.945))
                Spacer()
            case .failure(let msg):
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(appearance.danger)
                Text(msg)
                    .font(.subheadline)
                    .foregroundStyle(Color(red: 0.859, green: 0.894, blue: 0.945))
                    .multilineTextAlignment(.leading)
                Spacer()
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 0.043, green: 0.063, blue: 0.094).opacity(0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.07), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        VStack(spacing: 12) {
            if let testResult = testResult, testResult.isFailure() {
                // Show recovery options after a failure
                recoveryButtons
            } else {
                // Normal state: save/connect and test buttons
                VStack(spacing: 12) {
                    Button {
                        Task { await saveAndConnect() }
                    } label: {
                        HStack(spacing: 8) {
                            Spacer()
                            Text(initialConfig == nil ? "Save & Connect" : "Update Connection")
                                .font(.system(size: 16, weight: .semibold))
                            Spacer()
                        }
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(colors: [appearance.accent, appearance.accentSecondary],
                                           startPoint: .leading,
                                           endPoint: .trailing)
                        )
                        .foregroundStyle(Color(red: 0.039, green: 0.055, blue: 0.086))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .shadow(color: appearance.accent.opacity(0.35), radius: 14, x: 0, y: 6)
                    }
                    .disabled(!isFormValid || isConnecting)
                    .opacity(isFormValid && !isConnecting ? 1.0 : 0.5)
                    
                    Button {
                        Task { await testConnection() }
                    } label: {
                        HStack(spacing: 6) {
                            if isTesting {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(appearance.accent)
                            }
                            Text(isTesting ? "Testing..." : "Test Connection")
                                .font(.system(size: 15, weight: .medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(red: 0.118, green: 0.164, blue: 0.250).opacity(0.5))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(Color.white.opacity(0.07), lineWidth: 1)
                                )
                        )
                        .foregroundStyle(appearance.accent)
                    }
                    .disabled(isTesting || !isFormValid)
                }
            }
        }
    }
    
    // MARK: - Recovery Buttons
    private var recoveryButtons: some View {
        VStack(spacing: 12) {
            Text("Connection failed. Choose an option:")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(red: 0.753, green: 0.271, blue: 0.125))
            
            Button {
                // Try again with same connection
                Task { await saveAndConnect() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                    Text("Try Again")
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(colors: [appearance.accent, appearance.accentSecondary],
                                   startPoint: .leading,
                                   endPoint: .trailing)
                )
                .foregroundStyle(Color(red: 0.039, green: 0.055, blue: 0.086))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: appearance.accent.opacity(0.35), radius: 14, x: 0, y: 6)
            }
            
            Button {
                // Go back to the list of servers to choose another
                showChooseServer = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "server.badge.plus")
                    Text("Choose Another Server")
                        .font(.system(size: 15, weight: .medium))
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(red: 0.118, green: 0.164, blue: 0.250).opacity(0.5))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.white.opacity(0.07), lineWidth: 1)
                        )
                )
                .foregroundStyle(appearance.accent)
            }
        }
    }
    
    // MARK: - Server Picker Sheet
    private var serverPickerSheet: some View {
        NavigationStack {
            ZStack {
                appearance.activeTheme.backgroundView
                    .ignoresSafeArea()
                
                VStack(spacing: 16) {
                    Text("Select a saved server")
                        .font(.headline)
                        .foregroundStyle(Color(red: 0.949, green: 0.965, blue: 0.988))
                    
                    if store.savedConnections.isEmpty {
                        Text("No saved servers. Tap \"Add Server\" in Settings to add one.")
                            .font(.subheadline)
                            .foregroundStyle(Color(red: 0.494, green: 0.557, blue: 0.651))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    } else {
                        ScrollView {
                            VStack(spacing: 10) {
                                ForEach(store.savedConnections) { config in
                                    Button {
                                        // Populate form with selected server
                                        baseURL = config.baseURL
                                        apiKey = config.apiKey
                                        label = config.label
                                        testResult = nil
                                        showChooseServer = false
                                    } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(config.label)
                                                    .font(.system(size: 15, weight: .semibold))
                                                    .foregroundStyle(Color(red: 0.949, green: 0.965, blue: 0.988))
                                                Text(config.baseURL)
                                                    .font(.system(size: 12))
                                                    .foregroundStyle(Color(red: 0.494, green: 0.557, blue: 0.651))
                                            }
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .foregroundStyle(Color(red: 0.494, green: 0.557, blue: 0.651))
                                        }
                                        .padding()
                                        .background(
                                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                .fill(Color(red: 0.118, green: 0.164, blue: 0.250).opacity(0.6))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                        .stroke(Color.white.opacity(0.07), lineWidth: 1)
                                                )
                                        )
                                    }
                                }
                            }
                            .padding(.horizontal, 4)
                        }
                    }
                    
                    Button("Cancel") {
                        showChooseServer = false
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(red: 0.118, green: 0.164, blue: 0.250).opacity(0.5))
                    )
                    .foregroundStyle(appearance.accent)
                }
                .padding(20)
            }
            .navigationTitle("Choose Server")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    // MARK: - Server Picker Section
    
    private var serverPickerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Saved Servers")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(red: 0.494, green: 0.557, blue: 0.651))
                
                Spacer()
                
                Text("\(store.savedConnections.count) server\(store.savedConnections.count != 1 ? "s" : "")")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(red: 0.361, green: 0.420, blue: 0.518))
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(store.savedConnections) { config in
                        Button {
                            baseURL = config.baseURL
                            apiKey = config.apiKey
                            label = config.label
                            testResult = nil
                            selectedServerIndex = nil
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(config.label)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color(red: 0.859, green: 0.894, blue: 0.945))
                                Text(config.baseURL)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color(red: 0.494, green: 0.557, blue: 0.651))
                                    .lineLimit(1)
                            }
                            .padding(12)
                            .frame(width: 180, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(red: 0.118, green: 0.164, blue: 0.250).opacity(0.6))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(appearance.accent.opacity(0.3), lineWidth: 1)
                                    )
                            )
                        }
                    }
                    
                    // Add New button
                    Button {
                        baseURL = ""
                        apiKey = ""
                        label = "My Hermes"
                        testResult = nil
                    } label: {
                        VStack(alignment: .center, spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundStyle(appearance.accent)
                            Text("Add New")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(appearance.accent)
                        }
                        .frame(width: 80)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(red: 0.118, green: 0.164, blue: 0.250).opacity(0.4))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Color(red: 0.494, green: 0.557, blue: 0.651).opacity(0.3), lineWidth: 1)
                                )
                        )
                    }
                }
                .padding(.bottom, 2)
            }
        }
    }
    
    // MARK: - Add New Divider
    
    private var addNewDivider: some View {
        VStack(spacing: 16) {
            Divider()
                .overlay(Color(red: 0.118, green: 0.164, blue: 0.250))
            
            HStack(spacing: 8) {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(red: 0.494, green: 0.557, blue: 0.651))
                Text("Or add a new server below")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(red: 0.494, green: 0.557, blue: 0.651))
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(red: 0.494, green: 0.557, blue: 0.651))
            }
        }
    }
    
    // MARK: - Tips
    
    private var tipsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tips")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(red: 0.494, green: 0.557, blue: 0.651))
                .padding(.leading, 4)
            
            VStack(alignment: .leading, spacing: 12) {
                tipRow(icon: "network", text: "Tailscale IP (100.x.x.x) + port 8642")
                tipRow(icon: "wifi", text: "LAN IP (192.168.x.x) if on same network")
                tipRow(icon: "lock", text: "API key is in your Hermes .env file")
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(red: 0.118, green: 0.164, blue: 0.250).opacity(0.4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    )
            )
        }
    }
    
    private func tipRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(appearance.accent)
                .frame(width: 22)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Color(red: 0.494, green: 0.557, blue: 0.651))
            Spacer()
        }
    }

    // MARK: - Actions

    private func testConnection() async {
        isTesting = true
        testResult = nil
        let config = ConnectionConfig(baseURL: baseURL, apiKey: apiKey, label: label)
        let client = HermesAPIClient(config: config)
        do {
            let result: (HealthResponse, CapabilitiesResponse)
            result = try await Self.runWithTimeout(seconds: 10) {
                let health = try await client.checkHealth()
                let caps = try await client.getCapabilities()
                return (health, caps)
            }
            testResult = .success("Connected — Hermes v\(result.0.version ?? "unknown")")
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
        isTesting = true
        testResult = nil
        let config = ConnectionConfig(baseURL: baseURL, apiKey: apiKey, label: label)
        
        // If we're editing an existing connection with the same baseURL, update it
        if let initialConfig = initialConfig, initialConfig.baseURL == baseURL {
            do {
                try KeychainManager.shared.addOrUpdate(config)
                store.savedConnections = KeychainManager.shared.loadAll()
                if store.connectionConfig?.baseURL == baseURL {
                    let success = try await Self.runWithTimeout(seconds: 15) {
                        await store.connect(config: config)
                    }
                    if success {
                        testResult = .success("Connected — \(label)")
                    } else {
                        testResult = .failure(store.error?.message ?? "Connection failed")
                    }
                    isTesting = false
                    return
                }
            } catch let error as APIError {
                testResult = .failure(error.errorDescription ?? "Failed to update connection")
            } catch {
                testResult = .failure("Failed to update connection: \(error.localizedDescription)")
            }
        } else {
            do {
                try KeychainManager.shared.addOrUpdate(config)
                store.savedConnections = KeychainManager.shared.loadAll()
            } catch {
                testResult = .failure("Failed to save connection: \(error.localizedDescription)")
                return
            }
        }
        
        var success = false
        do {
            success = try await Self.runWithTimeout(seconds: 15) {
                await store.connect(config: config)
            }
        } catch {
            success = false
        }
        
        if success {
            testResult = .success("Connected — \(label)")
        } else {
            testResult = .failure(store.error?.message ?? "Connection timed out or failed")
        }
        isTesting = false
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
