import SwiftUI
import AVKit

// MARK: - Models

struct VideoRun: Codable, Identifiable {
    let id: String
    let topic: String?
    let stage: String?
    let createdAt: String?
    let updatedAt: String?
    let detail: String?
    let finalUrl: String?
    let error: String?

    var isDone: Bool { stage == "done" }
    var isFailed: Bool { stage == "failed" }
    var isActive: Bool { !isDone && !isFailed }

    var stageLabel: String {
        Self.stageNames[stage ?? ""] ?? (stage ?? "Queued")
    }

    static let stageNames: [String: String] = [
        "script": "Writing script",
        "voice": "Cloning voice",
        "avatar": "Rendering presenter",
        "broll": "Generating b-roll",
        "assemble": "Assembling edit",
        "render": "Rendering video",
        "done": "Done",
        "failed": "Failed",
    ]
}

struct HeyGenAvatar: Codable, Identifiable {
    let avatar_id: String
    let avatar_name: String?
    let preview_image_url: String?

    var id: String { avatar_id }
    var displayName: String { avatar_name ?? avatar_id }
}

struct AgentOSError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

// MARK: - Store

@MainActor
final class VideoStore: ObservableObject {
    static let defaultServer = "http://100.81.23.33:3738"
    /// Preferred avatar ("Erick Casual Cafe") when present in the list.
    static let defaultAvatarId = "39d235f1d53142e8869b8acc6df495d1"

    @AppStorage("agent_os_server_url") var serverURL = VideoStore.defaultServer

    @Published var topic = ""
    @Published var durationSec = 40
    @Published var avatars: [HeyGenAvatar] = []
    @Published var selectedAvatarId: String?
    @Published var runs: [VideoRun] = []
    @Published var isStarting = false
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var pollTask: Task<Void, Never>?
    private let session = URLSession.shared

    var baseURL: URL? {
        var s = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        return URL(string: s)
    }

    func absoluteURL(_ relative: String) -> URL? {
        guard let base = baseURL else { return nil }
        return URL(string: relative, relativeTo: base)?.absoluteURL
    }

    // MARK: Networking

    private func get(_ path: String) async throws -> Data {
        guard let base = baseURL else { throw AgentOSError(message: "Invalid Agent OS server URL. Set it in Settings.") }
        let (data, response) = try await session.data(from: base.appending(path: path))
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw AgentOSError(message: "Server returned HTTP \(http.statusCode)")
        }
        return data
    }

    private func post(_ path: String, _ body: [String: Any]) async throws -> Data {
        guard let base = baseURL else { throw AgentOSError(message: "Invalid Agent OS server URL. Set it in Settings.") }
        var req = URLRequest(url: base.appending(path: path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let text = String(data: data, encoding: .utf8)?.prefix(300) ?? ""
            throw AgentOSError(message: "Server returned HTTP \(http.statusCode): \(text)")
        }
        return data
    }

    // MARK: Actions

    func loadInitial() async {
        isLoading = true
        defer { isLoading = false }
        // Load both, but surface each failure separately rather than losing both.
        do {
            let data = try await get("/api/video/heygen/avatars?limit=500")
            struct Envelope: Decodable { let ok: Bool?; let avatars: [HeyGenAvatar]? }
            let env = try JSONDecoder().decode(Envelope.self, from: data)
            avatars = env.avatars ?? []
            if selectedAvatarId == nil {
                if avatars.contains(where: { $0.avatar_id == Self.defaultAvatarId }) {
                    selectedAvatarId = Self.defaultAvatarId
                } else {
                    selectedAvatarId = avatars.first?.avatar_id
                }
            }
        } catch {
            errorMessage = "Couldn't load avatars: \(error.localizedDescription)"
        }
        await refreshRuns()
    }

    func refreshRuns() async {
        do {
            let data = try await get("/api/video/auto/run")
            struct Envelope: Decodable { let ok: Bool?; let runs: [VideoRun]?; let error: String? }
            let env = try JSONDecoder().decode(Envelope.self, from: data)
            if env.ok == false { throw AgentOSError(message: env.error ?? "Server reported failure") }
            runs = env.runs ?? []
        } catch {
            errorMessage = "Couldn't load runs: \(error.localizedDescription)"
        }
    }

    func startRun() async {
        let trimmed = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Enter a topic first."
            return
        }
        isStarting = true
        defer { isStarting = false }
        do {
            var body: [String: Any] = ["topic": trimmed, "durationSec": durationSec]
            if let avatar = selectedAvatarId { body["avatarId"] = avatar }
            let data = try await post("/api/video/auto/run", body)
            struct Envelope: Decodable { let ok: Bool?; let run: VideoRun?; let error: String? }
            let env = try JSONDecoder().decode(Envelope.self, from: data)
            guard env.ok != false, let run = env.run else {
                throw AgentOSError(message: env.error ?? "Server rejected the run")
            }
            runs.insert(run, at: 0)
            topic = ""
            startPollingIfNeeded()
        } catch {
            errorMessage = "Couldn't start run: \(error.localizedDescription)"
        }
    }

    /// Polls every 5s while any run is active. Runs can take 5-20 minutes.
    func startPollingIfNeeded() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refreshRuns()
                if !self.runs.contains(where: \.isActive) { break }
                try? await Task.sleep(for: .seconds(5))
            }
            self?.pollTask = nil
        }
    }
}

// MARK: - View

struct VideoView: View {
    @StateObject private var video = VideoStore()
    @EnvironmentObject var appearance: AppearanceSettings
    @Environment(\.dismiss) private var dismiss

    private var theme: any HermesTheme { appearance.activeTheme }

    var body: some View {
        NavigationStack {
            ZStack {
                theme.backgroundView
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: theme.spacingM) {
                        if let error = video.errorMessage {
                            errorBanner(error)
                        }
                        newVideoCard
                        runsCard
                    }
                    .padding(.horizontal, theme.spacingM)
                    .padding(.vertical, theme.spacingM)
                }
            }
            .navigationTitle("Video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(theme.accent)
                }
            }
            .task {
                await video.loadInitial()
                video.startPollingIfNeeded()
            }
        }
    }

    // MARK: Cards

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: theme.spacingS) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(theme.textPrimary)
            Spacer()
            Button {
                video.errorMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(theme.textSecondary)
            }
        }
        .padding(theme.spacingM)
        .background { AnyView(theme.glassCard(cornerRadius: theme.cardRadius)) }
    }

    private var newVideoCard: some View {
        VStack(alignment: .leading, spacing: theme.spacingM) {
            cardHeader("New Video", icon: "film")

            TextField("What should the video be about?", text: $video.topic, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.plain)
                .foregroundStyle(theme.textPrimary)

            Picker("Duration", selection: $video.durationSec) {
                Text("20s").tag(20)
                Text("40s").tag(40)
                Text("60s").tag(60)
                Text("90s").tag(90)
            }
            .pickerStyle(.segmented)

            Text("Presenter")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.textSecondary)

            if video.avatars.isEmpty {
                HStack(spacing: theme.spacingS) {
                    ProgressView()
                    Text("Loading avatars…")
                        .font(.subheadline)
                        .foregroundStyle(theme.textSecondary)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: theme.spacingS) {
                        ForEach(video.avatars) { avatar in
                            avatarCell(avatar)
                        }
                    }
                }
            }

            Button {
                Task { await video.startRun() }
            } label: {
                HStack {
                    Spacer()
                    if video.isStarting {
                        ProgressView()
                    } else {
                        Label("Generate Video", systemImage: "play.fill")
                    }
                    Spacer()
                }
                .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.accent)
            .disabled(video.isStarting || video.topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(theme.spacingL)
        .background { AnyView(theme.glassCard(cornerRadius: theme.cardRadius)) }
    }

    private func avatarCell(_ avatar: HeyGenAvatar) -> some View {
        let selected = video.selectedAvatarId == avatar.avatar_id
        return Button {
            video.selectedAvatarId = avatar.avatar_id
        } label: {
            VStack(spacing: 4) {
                AsyncImage(url: URL(string: avatar.preview_image_url ?? "")) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Image(systemName: "person.crop.rectangle")
                        .resizable().scaledToFit()
                        .padding(18)
                        .foregroundStyle(theme.textSecondary)
                }
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(selected ? theme.accent : Color.clear, lineWidth: 3)
                }
                Text(avatar.displayName)
                    .font(.caption2)
                    .lineLimit(1)
                    .frame(width: 72)
                    .foregroundStyle(selected ? theme.accent : theme.textSecondary)
            }
        }
        .buttonStyle(.plain)
    }

    private var runsCard: some View {
        VStack(alignment: .leading, spacing: theme.spacingM) {
            HStack {
                cardHeader("Runs", icon: "list.bullet")
                Spacer()
                Button {
                    Task { await video.refreshRuns() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(theme.accent)
                }
            }

            if video.runs.isEmpty {
                Text("No runs yet. Generate your first video above.")
                    .font(.subheadline)
                    .foregroundStyle(theme.textSecondary)
            } else {
                ForEach(video.runs) { run in
                    runRow(run)
                    if run.id != video.runs.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding(theme.spacingL)
        .background { AnyView(theme.glassCard(cornerRadius: theme.cardRadius)) }
    }

    private func runRow(_ run: VideoRun) -> some View {
        VStack(alignment: .leading, spacing: theme.spacingS) {
            Text(run.topic ?? "Untitled")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.textPrimary)
                .lineLimit(2)

            HStack(spacing: theme.spacingS) {
                if run.isActive {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(run.stageLabel)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(run.isFailed ? .red : (run.isDone ? .green : theme.accent))
            }

            if let detail = run.detail, !detail.isEmpty, !run.isDone {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(3)
            }

            if run.isFailed, let error = run.error, !error.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if run.isDone, let final = run.finalUrl, let url = video.absoluteURL(final) {
                VideoPlayer(player: AVPlayer(url: url))
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                ShareLink(item: url) {
                    Label("Share Video", systemImage: "square.and.arrow.up")
                        .font(.subheadline)
                }
                .foregroundStyle(theme.accent)
            }
        }
        .padding(.vertical, theme.spacingS)
    }

    private func cardHeader(_ title: String, icon: String? = nil) -> some View {
        HStack(spacing: theme.spacingS) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.accent)
            }
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.textSecondary)
            Spacer()
        }
    }
}
