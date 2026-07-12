import Foundation

/// Provides the one-time "What's New" notification shown after an app update.
enum ReleaseNotes {
    static let lastPresentedVersionKey = "last_presented_release_notes_version"

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }

    static func shouldPresent(currentVersion: String, lastPresentedVersion: String) -> Bool {
        !currentVersion.isEmpty && currentVersion != "Unknown" && currentVersion != lastPresentedVersion
    }

    static func changes(for version: String) -> [String] {
        switch version {
        case "1.8.34":
            return [
                "Restored the complete scrollable skills list in the chat composer.",
                "Skills now remain readable instead of collapsing to the header."
            ]
        case "1.8.33":
            return [
                "Hermes now restores your last active chat after the app is relaunched.",
                "Active chats remain isolated per server connection."
            ]
        case "1.8.32":
            return [
                "Fixed a crash when switching to another app while Hey Hermes is listening.",
                "Type / in chat to browse and search available Hermes skills.",
                "Queue your next message while Hermes is still responding.",
                "Organize chat history into persistent projects with long-press move controls."
            ]
        case "1.8.29":
            return [
                "Say “Hey Hermes” to open voice mode while the app is active.",
                "Voice endpoint detection responds faster when you finish speaking.",
                "A new What's New popup highlights changes after every update."
            ]
        default:
            return ["Hermes Companion has been updated with improvements and fixes."]
        }
    }

    static func message(for version: String) -> String {
        changes(for: version)
            .map { "• \($0)" }
            .joined(separator: "\n\n")
    }
}
