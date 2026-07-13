import AppIntents
import SwiftUI
import WidgetKit

struct VoiceActivationControlWidget: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: "com.chibitek.hermescompanion.voice-activation"
        ) {
            ControlWidgetToggle(
                action: ToggleVoiceActivationIntent(),
                label: Text("Voice Activated"),
                isOn: VoiceActivationProvider()
            )
            .tint(.green)
        }
        .displayName(Text("Voice Activated"))
        .description(Text("Toggle Hey Hermes voice activation"))
    }
}

struct ToggleVoiceActivationIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Voice Activated"
    static let description = IntentDescription("Toggle Hey Hermes voice activation in Hermes Companion.")

    @Parameter(title: "Enabled")
    var value: Bool

    init() {
        value = false
    }

    init(value: Bool) {
        self.value = value
    }

    func perform() async throws -> some IntentResult {
        SharedDefaults.shared.set(value, forKey: "hey_hermes_enabled")
        return .result()
    }
}

struct VoiceActivationProvider: DynamicValueProvider {
    func current() -> Bool {
        SharedDefaults.shared.bool(forKey: "hey_hermes_enabled")
    }
}

/// Shared UserDefaults via App Group so the main app and Control Widget
/// extension can read/write the same settings.
enum SharedDefaults {
    static let suiteName = "group.com.chibitek.hermescompanion"
    static let shared: UserDefaults = {
        UserDefaults(suiteName: suiteName) ?? .standard
    }()
}
