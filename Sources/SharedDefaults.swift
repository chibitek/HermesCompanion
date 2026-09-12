import Foundation
import WidgetKit

// MARK: - Shared Defaults (App Group)

/// Shared UserDefaults via App Group so the main app and Control Widget
/// extension can read/write the same settings.
enum SharedDefaults {
    static let suiteName = "group.com.chibitek.hermescompanion"
    static let shared: UserDefaults = {
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        migrateWakeListeningConsent(in: defaults)
        return defaults
    }()

    static func migrateWakeListeningConsent(in defaults: UserDefaults) {
        // Previous releases enabled recording by default. Require a fresh opt-in.
        guard !defaults.bool(forKey: "wake_listening_explicit_consent_v1") else { return }
        defaults.set(false, forKey: "hey_hermes_enabled")
        defaults.set(true, forKey: "wake_listening_explicit_consent_v1")
    }
}

enum VoiceActivationControlConstants {
    static let kind = "com.chibitek.hermescompanion.voice-activation"
}

extension Notification.Name {
    static let openVoiceMode = Notification.Name("com.chibitek.hermescompanion.openVoiceMode")
}
