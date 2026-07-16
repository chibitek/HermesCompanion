import Foundation
import WidgetKit

// MARK: - Shared Defaults (App Group)

/// Shared UserDefaults via App Group so the main app and Control Widget
/// extension can read/write the same settings.
enum SharedDefaults {
    static let suiteName = "group.com.chibitek.hermescompanion"
    static let shared: UserDefaults = {
        UserDefaults(suiteName: suiteName) ?? .standard
    }()
}

enum VoiceActivationControlConstants {
    static let kind = "com.chibitek.hermescompanion.voice-activation"
}
