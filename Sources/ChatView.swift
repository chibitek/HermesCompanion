import SwiftUI

/// Main chat view with Liquid Glass design.
/// Uses .glassEffect() throughout for translucent, depth-heavy UI.
struct ChatView: View {
    @ObservedObject var store: AppStore
    @State private var inputText = ""
    @State private var showSessionPicker = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ZStack {
                // Base gradient background for depth
                LinearGradient(
                    colors: [
                        Color(.systemBackground),
                        Color(.systemBackground).opacity(0.95),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    messageList

                    if store.isStreaming || !store.toolEvents.isEmpty {
                        toolEventsPanel
                    }

                    if let approval = store.pendingApproval {
                        GlassApprovalCard(approval: approval) { choice in
                            Task { await store.resolveApproval(choice: choice) }
                        }
                    }

                    GlassInputBar(
                        text: $inputText,
                        isStreaming: store.isStreaming,
                        onSend: sendMessage,
                        onStop: { store.stopStreaming() },
                        onCamera: { /* phase 2 */ }
                    )
                }
            }
            .navigationTitle(store.activeSession?.title ?? "New Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSessionPicker = true
                    } label: {
                        Image(systemName: "sidebar.left")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSessionPicker) {
                SessionPickerView(store: store)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(store: store)
            }
            .alert("Error", isPresented: .init(
                get: { store.error != nil },
                set: { if !$0 { store.clearError() } }
            )) {
                Button("OK") { store.clearError() }
            } message: {
                Text(store.error?.message ?? "")
            }
        }
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: GlassTheme.spacingM) {
                    if store.messages.isEmpty && store.streamingText.isEmpty {
                        emptyState
                    }

                    ForEach(store.messages) { msg in
                        GlassBubble(content: msg.content, isUser: msg.isUser)
                            .id(msg.id)
                    }

                    if store.isStreaming && !store.streamingText.isEmpty {
                        GlassBubble(content: store.streamingText, isUser: false, isStreaming: true)
                            .id("streaming")
                    }

                    if store.isStreaming && store.streamingText.isEmpty {
                        GlassThinkingIndicator()
                            .id("thinking")
                    }
                }
                .padding(.horizontal, GlassTheme.spacingL)
                .padding(.vertical, GlassTheme.spacingM)
            }
            .onChange(of: store.messages.count) { _, _ in
                withAnimation(.smooth) {
                    proxy.scrollTo(store.messages.last?.id ?? "streaming", anchor: .bottom)
                }
            }
            .onChange(of: store.streamingText) { _, _ in
                withAnimation(.smooth) {
                    proxy.scrollTo("streaming", anchor: .bottom)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: GlassTheme.spacingXL) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
                .glassEffect(.regular)
                .clipShape(RoundedRectangle(cornerRadius: GlassTheme.radiusXL, style: .continuous))
                .frame(width: 88, height: 88)

            VStack(spacing: GlassTheme.spacingS) {
                Text("Start a conversation")
                    .font(.title3)
                    .fontWeight(.medium)
                Text("Send a message to your Hermes agent.\nResponses stream in real time.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Tool Events Panel

    private var toolEventsPanel: some View {
        VStack(alignment: .leading, spacing: GlassTheme.spacingXS) {
            Text("Tool Activity")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, GlassTheme.spacingM)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: GlassTheme.spacingS) {
                    ForEach(store.toolEvents.suffix(12)) { evt in
                        GlassToolChip(event: evt)
                    }
                }
                .padding(.horizontal, GlassTheme.spacingM)
            }
        }
        .padding(.vertical, GlassTheme.spacingS)
    }

    // MARK: - Send

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        inputText = ""
        Task { await store.sendMessage(text) }
    }
}