import Foundation

/// Resolves an existing profile connection without borrowing another profile's key.
enum BotChatAccess {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func expectedURL(root: ConnectionConfig, profile: String) throws -> URL {
        guard !profile.isEmpty, profile.utf8.allSatisfy({
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95
        }), var parts = URLComponents(string: root.normalizedBaseURL),
              ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
              parts.host?.isEmpty == false, parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil,
              !parts.path.split(separator: "/").contains("p") else {
            throw Failure(message: "Bot chat requires a root gateway URL and a valid Hermes profile name. Check the selected connection.")
        }
        if profile != "default" { parts.path += "/p/" + profile }
        guard let url = parts.url else { throw Failure(message: "Could not form the gateway route for profile \(profile).") }
        return url
    }

    static func connection(root: ConnectionConfig, profile: String, saved: [ConnectionConfig]) throws -> ConnectionConfig {
        let expected = try expectedURL(root: root, profile: profile)
        if profile == "default", root.isValid { return root }
        let matches = saved.filter { $0.isValid && equivalent($0.normalizedBaseURL, expected) }
        guard matches.count == 1, let match = matches.first else {
            throw Failure(message: matches.isEmpty
                ? "No saved connection for Bot \(profile). Add \(expected.absoluteString) in Settings with this profile's API key, then retry. The gateway must serve this profile route."
                : "Multiple saved connections match Bot \(profile) at \(expected.absoluteString). Keep one profile connection in Settings, then retry.")
        }
        return match
    }

    private static func equivalent(_ candidate: String, _ expected: URL) -> Bool {
        guard let url = URL(string: candidate), url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil else { return false }
        func port(_ url: URL) -> Int? { url.port ?? (url.scheme?.lowercased() == "https" ? 443 : 80) }
        return url.scheme?.lowercased() == expected.scheme?.lowercased()
            && url.host?.lowercased() == expected.host?.lowercased()
            && port(url) == port(expected) && url.path == expected.path
    }

    static func session(_ detail: SessionDetail, canonical: BotSession, profile: String) throws -> HermesSession {
        guard detail.id == canonical.id, detail.title == "Bot Chat", detail.isArchived != true else {
            throw Failure(message: "Bot \(profile) returned a different, renamed, or archived canonical conversation (requested \(canonical.id), received \(detail.id)). Refresh the Bot roster before sending.")
        }
        return HermesSession(id: detail.id, title: detail.title, source: detail.source,
                             model: detail.model, provider: detail.provider, startedAt: detail.startedAt,
                             lastActive: detail.lastActive, messageCount: detail.messageCount,
                             cwd: detail.cwd, gitRepoRoot: detail.gitRepoRoot)
    }
}
