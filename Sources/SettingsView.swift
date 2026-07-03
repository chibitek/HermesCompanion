import SwiftUI

/// Settings: connection info, capabilities, skills, disconnect.
struct SettingsView: View {
    @ObservedObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // Connection
                Section {
                    if let config = store.connectionConfig {
                        LabeledContent("Label", value: config.label)
                        LabeledContent("URL", value: config.normalizedBaseURL)
                        LabeledContent("API Key", value: String(repeating: "*", count: min(config.apiKey.count, 20)) + "...")
                    }
                } header: {
                    Text("Connection")
                }

                // Server Info
                if let caps = store.capabilities {
                    Section {
                        LabeledContent("Model", value: caps.model)
                        LabeledContent("Auth", value: caps.auth.type)

                        if let version = caps.object as String? {
                            LabeledContent("API Type", value: version)
                        }
                    } header: {
                        Text("Server")
                    }

                    // Features
                    Section {
                        FeatureRow("Streaming Chat", enabled: caps.features.sessionChatStreaming)
                        FeatureRow("Async Runs", enabled: caps.features.runSubmission)
                        FeatureRow("Run Events SSE", enabled: caps.features.runEventsSSE)
                        FeatureRow("Tool Approvals", enabled: caps.features.runApprovalResponse)
                        FeatureRow("Tool Progress", enabled: caps.features.toolProgressEvents)
                        FeatureRow("Session Forking", enabled: caps.features.sessionFork)
                        FeatureRow("Skills API", enabled: caps.features.skillsAPI)
                    } header: {
                        Text("Features")
                    }
                }

                // Skills
                Section {
                    if store.skills.isEmpty {
                        Text("No skills loaded")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.skills.prefix(20)) { skill in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(skill.name)
                                    .font(.body)
                                if let desc = skill.description {
                                    Text(desc)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                        if store.skills.count > 20 {
                            Text("... and \(store.skills.count - 20) more")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Skills")
                } footer: {
                    Button("Refresh Skills") {
                        Task { await store.refreshSkills() }
                    }
                }

                // Actions
                Section {
                    Button(role: .destructive) {
                        store.disconnect()
                        dismiss()
                    } label: {
                        Label("Disconnect", systemImage: "wifi.slash")
                    }
                }

                // About
                Section {
                    LabeledContent("Version", value: appVersion)
                    Link("Hermes Docs", destination: URL(string: AppConfig.hermesDocsURL)!)
                    Link("GitHub", destination: URL(string: AppConfig.repoURL)!)
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                Task { await store.refreshSkills() }
            }
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}

struct FeatureRow: View {
    let label: String
    let enabled: Bool

    init(_ label: String, enabled: Bool) {
        self.label = label
        self.enabled = enabled
    }

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Image(systemName: enabled ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(enabled ? .green : .secondary)
        }
    }
}