import SwiftUI
import AVFoundation

/// Voice settings page accessible from the main Settings.
/// Lets the user pick a system TTS voice, adjust speed and pitch,
/// and preview how it sounds.
struct VoiceSettingsView: View {
    @AppStorage("voice_speed") private var speed: Double = 0.5
    @AppStorage("voice_pitch") private var pitch: Double = 1.0
    @AppStorage("voice_identifier") private var selectedVoiceId: String = ""

    @State private var availableVoices: [AVSpeechSynthesisVoice] = []
    @State private var filterQuality: Bool = true
    @EnvironmentObject var appearance: AppearanceSettings

    private var accent: Color { appearance.accent }

    var body: some View {
        Form {
            Section {
                Toggle("Prefer enhanced quality", isOn: $filterQuality)
                    .onChange(of: filterQuality) { _, _ in
                        refreshVoices()
                    }

                if filteredVoices.isEmpty {
                    Text("No voices available. Download voices from Settings > Accessibility > Spoken Content > Voices.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filteredVoices, id: \.identifier) { voice in
                        voiceRow(voice)
                    }
                }
            } header: {
                Text("Voice")
            } footer: {
                Text("Enhanced and premium voices sound more natural. Download additional voices in iOS Settings under Accessibility > Spoken Content.")
            }

            Section {
                HStack {
                    Text("Speed")
                    Spacer()
                    Text(String(format: "%.2f", speed))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Slider(value: $speed, in: 0.1...1.0, step: 0.05)
                    .tint(accent)
            } header: {
                Text("Speed")
            } footer: {
                Text("Lower values are slower, higher values are faster. Default is 0.5.")
            }

            Section {
                HStack {
                    Text("Pitch")
                    Spacer()
                    Text(String(format: "%.1f", pitch))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Slider(value: $pitch, in: 0.5...2.0, step: 0.1)
                    .tint(accent)
            } header: {
                Text("Pitch")
            } footer: {
                Text("Default is 1.0. Lower values are deeper, higher values are higher pitched.")
            }

            Section {
                Button {
                    previewVoice()
                } label: {
                    HStack {
                        Image(systemName: "speaker.wave.2")
                        Text("Preview Voice")
                    }
                }
            }
        }
        .navigationTitle("Voice")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            refreshVoices()
            if selectedVoiceId.isEmpty {
                let defaultVoice = availableVoices.first(where: {
                    $0.quality == .enhanced && $0.language.hasPrefix("en")
                }) ?? availableVoices.first
                selectedVoiceId = defaultVoice?.identifier ?? ""
            }
        }
    }

    private var filteredVoices: [AVSpeechSynthesisVoice] {
        if filterQuality {
            return availableVoices.filter { $0.quality == .enhanced || $0.quality == .premium }
        }
        return availableVoices
    }

    private func refreshVoices() {
        let langCode = Locale.current.language.languageCode?.identifier ?? "en"
        availableVoices = AVSpeechSynthesisVoice.speechVoices().sorted { a, b in
            let aEn = a.language.hasPrefix(langCode) ? 0 : 1
            let bEn = b.language.hasPrefix(langCode) ? 0 : 1
            if aEn != bEn { return aEn < bEn }
            if a.quality != b.quality {
                return a.quality.rawValue > b.quality.rawValue
            }
            return a.name < b.name
        }
    }

    private func voiceRow(_ voice: AVSpeechSynthesisVoice) -> some View {
        let isSelected = voice.identifier == selectedVoiceId
        return Button {
            selectedVoiceId = voice.identifier
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(voice.name)
                        .font(.subheadline)
                    HStack(spacing: 6) {
                        Text(voice.language)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        qualityBadge(voice.quality)
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(accent)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func qualityBadge(_ quality: AVSpeechSynthesisVoiceQuality) -> some View {
        let label: String
        let color: Color
        switch quality {
        case .premium: label = "Premium"; color = .purple
        case .enhanced: label = "Enhanced"; color = .blue
        default: label = "Default"; color = .secondary
        }
        return Text(label)
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
            .foregroundStyle(color)
    }

    private let previewSynthesizer = AVSpeechSynthesizer()

    private func previewVoice() {
        previewSynthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: "Hello, this is how your Hermes voice sounds.")
        if !selectedVoiceId.isEmpty,
           let voice = AVSpeechSynthesisVoice(identifier: selectedVoiceId) {
            utterance.voice = voice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.identifier)
        }
        utterance.rate = max(AVSpeechUtteranceMinimumSpeechRate,
                            min(AVSpeechUtteranceMaximumSpeechRate, Float(speed)))
        utterance.pitchMultiplier = Float(pitch)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {}
        previewSynthesizer.speak(utterance)
    }
}
