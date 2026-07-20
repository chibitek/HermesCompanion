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

// MARK: - Toggle Intent (enable/disable Hey Hermes)

struct ToggleVoiceActivationIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Voice Activated"
    static let description = IntentDescription("Toggle Hey Hermes voice activation in Hermes Companion.")

    @Parameter(title: "Enabled")
    var value: Bool

    init() { value = false }
    init(value: Bool) { self.value = value }

    func perform() async throws -> some IntentResult {
        SharedDefaults.shared.set(value, forKey: "hey_hermes_enabled")
        return .result()
    }
}

// MARK: - Open Voice Mode Intent

struct OpenVoiceModeIntent: AppIntent {
    static let title: LocalizedStringResource = "Voice Mode"
    static let description = IntentDescription("Open Hermes Companion voice mode.")
    static let openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        SharedDefaults.shared.set(true, forKey: "open_voice_page")
        NotificationCenter.default.post(name: .openVoiceMode, object: nil)
        return .result()
    }
}

// MARK: - Control Widgets

struct VoiceActivationControlWidget: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: VoiceActivationControlConstants.kind,
            provider: VoiceActivationValueProvider()
        ) { isEnabled in
            ControlWidgetToggle(
                "Hey Hermes",
                isOn: isEnabled,
                action: ToggleVoiceActivationIntent()
            ) { isOn in
                Label(
                    isOn ? "Listening" : "Off",
                    systemImage: isOn ? "waveform.badge.plus" : "waveform"
                )
            }
            .tint(Color(red: 0.0, green: 0.702, blue: 0.596))
        }
        .displayName("Voice Activated")
        .description("Toggle Hey Hermes voice activation")
    }
}

struct VoiceModeControlWidget: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: "com.chibitek.hermescompanion.voice-mode"
        ) {
            ControlWidgetButton(action: OpenVoiceModeIntent()) {
                Label("Voice Mode", systemImage: "waveform.badge.plus")
            }
            .tint(Color(red: 0.0, green: 0.702, blue: 0.596))
        }
        .displayName("Voice Mode")
        .description("Open Hermes Companion voice mode")
    }
}
