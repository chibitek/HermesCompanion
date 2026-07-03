import SwiftUI

/// Main chat view with streaming, tool events, and approval flow.
struct ChatView: View {
    @ObservedObject var store: AppStore
    @State private var inputText = ""
    @State private var showSessionPicker = false
    @State private var showSettings = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Message list
                messageList

                // Tool events (when streaming)
                if store.isStreaming || !store.toolEvents.isEmpty {
                    toolEventsPanel
                }

                // Pending approval
                if let approval = store.pendingApproval {
                    approvalCard(approval)
                }

                // Input bar
                inputBar
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
                LazyVStack(spacing: 12) {
                    if store.messages.isEmpty && store.streamingText.isEmpty {
                        emptyState
                    }

                    ForEach(store.messages) { msg in
                        MessageBubble(message: msg)
                            .id(msg.id)
                    }

                    // Streaming text (not yet committed)
                    if store.isStreaming && !store.streamingText.isEmpty {
                        StreamingBubble(text: store.streamingText)
                            .id("streaming")
                    }

                    // Streaming indicator
                    if store.isStreaming && store.streamingText.isEmpty {
                        ThinkingIndicator()
                            .id("thinking")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .onChange(of: store.messages.count) { _, _ in
                withAnimation {
                    proxy.scrollTo(store.messages.last?.id ?? "streaming", anchor: .bottom)
                }
            }
            .onChange(of: store.streamingText) { _, _ in
                withAnimation {
                    proxy.scrollTo("streaming", anchor: .bottom)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Start a conversation")
                .font(.headline)

            Text("Send a message to your Hermes agent. Responses stream in real time with tool progress visibility.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 80)
    }

    // MARK: - Tool Events Panel

    private var toolEventsPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Tool Activity")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(store.toolEvents.suffix(10)) { evt in
                        ToolEventChip(event: evt)
                    }
                }
                .padding(.horizontal, 12)
            }
        }
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
    }

    // MARK: - Approval Card

    private func approvalCard(_ approval: PendingApproval) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.shield.fill")
                    .foregroundStyle(.orange)
                Text("Approval Required")
                    .font(.headline)
            }

            Text(approval.command)
                .font(.system(.body, design: .monospaced))
                .padding(8)
                .background(Color(.systemGray6))
                .cornerRadius(6)

            HStack(spacing: 12) {
                Button("Allow Once") { Task { await store.resolveApproval(choice: "once") } }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)

                Button("Allow Session") { Task { await store.resolveApproval(choice: "session") } }
                    .buttonStyle(.bordered)

                Button("Deny") { Task { await store.resolveApproval(choice: "deny") } }
                    .buttonStyle(.bordered)
                    .tint(.red)
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 4)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 8) {
            // Camera button (phase 1: placeholder, phase 2: full camera)
            Button {
                // TODO: Camera input
            } label: {
                Image(systemName: "camera")
                    .font(.title3)
            }
            .disabled(true)
            .foregroundStyle(.secondary)

            TextField("Message", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .focused($inputFocused)
                .submitLabel(.send)
                .onSubmit(sendMessage)

            if store.isStreaming {
                Button {
                    store.stopStreaming()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.title3)
                        .foregroundStyle(.red)
                }
            } else {
                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        inputText = ""
        Task { await store.sendMessage(text) }
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ChatDisplayMessage

    var body: some View {
        HStack {
            if message.isUser { Spacer(minLength: 40) }

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .textSelection(.enabled)
                    .font(.body)

                if !message.images.isEmpty {
                    // Image attachments (phase 2)
                    EmptyView()
                }
            }
            .padding(12)
            .background(message.isUser ? Color.blue.opacity(0.12) : Color(.systemGray6))
            .cornerRadius(16)

            if !message.isUser { Spacer(minLength: 40) }
        }
    }
}

// MARK: - Streaming Bubble

struct StreamingBubble: View {
    let text: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(text)
                    .font(.body)
                    .textSelection(.enabled)
            }
            .padding(12)
            .background(Color(.systemGray6))
            .cornerRadius(16)
            .overlay(alignment: .bottomTrailing) {
                // Blinking cursor
                Text("▋")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 8)
                    .padding(.bottom, 4)
            }

            Spacer(minLength: 40)
        }
    }
}

// MARK: - Thinking Indicator

struct ThinkingIndicator: View {
    @State private var animate = false

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(.secondary)
                    .frame(width: 8, height: 8)
                    .scaleEffect(animate ? 1.0 : 0.5)
                    .animation(
                        .easeInOut(duration: 0.6)
                            .repeatForever()
                            .delay(Double(i) * 0.2),
                        value: animate
                    )
            }
        }
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(16)
        .onAppear { animate = true }
    }
}

// MARK: - Tool Event Chip

struct ToolEventChip: View {
    let event: ToolEvent

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)

            Text(event.toolName)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.15))
        .cornerRadius(8)
    }

    private var icon: String {
        switch event.type {
        case .progress: return "brain"
        case .started: return "play.circle"
        case .completed: return "checkmark.circle"
        case .failed: return "xmark.circle"
        }
    }

    private var color: Color {
        switch event.type {
        case .progress: return .purple
        case .started: return .blue
        case .completed: return .green
        case .failed: return .red
        }
    }
}