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
        case "1.8.77":
            return [
                "The composer shows a guidance arrow while Hermes is working and an up arrow when idle.",
                "An empty tap focuses the composer. Touch and hold the arrow to stop an active response or open voice conversation when idle.",
                "The blinking cursor at the end of the latest response remains the busy indicator."
            ]
        case "1.8.76":
            return [
                "Create and edit Kanban boards from your iPhone.",
                "Choose the active Hermes board or archive a board while retaining its tasks on the server.",
                "Board editing requires Companion bridge 0.1.10; older servers continue to support existing board views.",
                "Connection recovery stays on your selected server and preserves the current conversation."
            ]
        case "1.8.65":
            return [
                "Chat shows gateway reachability, response activity, and sync status.",
                "Open conversations refresh automatically; bridge 0.1.7 adds live workspace change notifications.",
                "Stream failures show the server's reason and no longer count as successful replies.",
                "History pagination, model selection for new chats, and duplicate image uploads are fixed."
            ]
        case "1.8.62":
            return [
                "Projects now browse server-owned folders through the Companion workspace bridge.",
                "Bots now show the Hermes profile roster and configured models.",
                "Bot conversation history reads the canonical server conversation with pagination.",
                "Kanban now browses server boards, columns, and task details.",
                "Workspace views refresh while open and reset when the connection changes.",
                "Bot chat across profiles and Kanban editing are not included in this release."
            ]
        case "1.8.61":
            return [
                "History now groups pinned chats into their own section.",
                "Pinned sessions now surface directly in Platform Hub and History.",
                "Model provider and catalog sync now refresh live from Hermes.",
                "Voice replies use the local iOS voice path only.",
                "Platform Hub now exposes the live Hermes endpoints.",
                "Streaming watchdog timing is now more stable."
            ]
        case "1.8.60":
            return [
                "Platform Hub now exposes the full Hermes capability surface."
            ]
        case "1.8.59":
            return [
                "Chat details now show the exact Hermes provider and workspace."
            ]
        case "1.8.58":
            return [
                "Session rows and Platform Hub now show the live model provider.",
                "Session details expose the exact Hermes provider and workspace path."
            ]
        case "1.8.57":
            return [
                "Project folders now prefer Hermes-managed workspaces.",
                "Session grouping stays stable while chats are added or archived."
            ]
        case "1.8.56":
            return [
                "Session models now show the actual Hermes provider."
            ]
        case "1.8.55":
            return [
                "Projects now show Hermes-managed workspaces and their live chat counts.",
                "Model pills use the active runtime provider instead of a stale session label."
            ]
        case "1.8.54":
            return [
                "Platform Hub now syncs the full Hermes history and project workspaces.",
                "Scheduled jobs can be created and edited directly from the iPhone.",
                "Model display now follows the active Hermes runtime and session lock."
            ]
        case "1.8.53":
            return [
                "Platform Hub adds native artifact uploads when browser control is enabled.",
                "Artifact uploads now show a provenance receipt with ID, hash, and expiry."
            ]
        case "1.8.52":
            return [
                "Scheduled jobs can now be paused, resumed, run immediately, or deleted from the iPhone.",
                "Platform Hub controls refresh job state after every action."
            ]
        case "1.8.51":
            return [
                "New Hermes Platform hub syncs gateway status, history, models, jobs, messaging, artifacts, Kanban, and bots.",
                "Scheduled jobs now show status, schedule, delivery target, and errors.",
                "The gateway view exposes readiness and connected platform health."
            ]
        case "1.8.50":
            return [
                "Model display now follows the active session and gateway runtime.",
                "Model picker adds a one-tap Use Gateway Default action.",
                "Model switching no longer overrides an existing Hermes session automatically."
            ]
        case "1.8.49":
            return [
                "Chats now support server-backed pinning, archiving, and state details.",
                "History keeps archived chats separate and pins stay at the top.",
                "Chat details show model, lineage state, activity, and token usage."
            ]
        case "1.8.48":
            return [
                "Model selection now locks to the active session and follows the real Hermes runtime.",
                "Model and provider lists load directly from the configured Hermes gateway.",
                "Project folders are now isolated per server and clean up deleted chats."
            ]
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
