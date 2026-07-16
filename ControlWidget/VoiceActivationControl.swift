import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Value Provider

struct VoiceActivationValueProvider: ControlValueProvider {
    let previewValue = true

    func currentValue() async throws -> Bool {
        SharedDefaults.shared.bool(forKey: "hey_hermes_enabled")
    }
}

// MARK: - Toggle Intent

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

// MARK: - Control Widget

struct VoiceActivationControlWidget: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: VoiceActivationControlConstants.kind,
            provider: VoiceActivationValueProvider()
        ) { isEnabled in
            ControlWidgetToggle(
                "Voice Activated",
                isOn: isEnabled,
                action: ToggleVoiceActivationIntent()
            ) { isOn in
                Label(
                    isOn ? "On" : "Off",
                    systemImage: isOn ? "mic.fill" : "mic.slash"
                )
            }
            .tint(.green)
        }
        .displayName("Voice Activated")
        .description("Toggle Hey Hermes voice activation")
    }
}
