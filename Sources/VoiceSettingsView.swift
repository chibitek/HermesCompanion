import SwiftUI
import AVFoundation

enum VoiceDefaults {
    static let voiceIdentifierKey = "voice_identifier"

    static func bestAvailableVoice(
        voices: [AVSpeechSynthesisVoice] = AVSpeechSynthesisVoice.speechVoices(),
        locale: Locale = .current
    ) -> AVSpeechSynthesisVoice? {
        let context = rankingContext(locale: locale)

        return voices.sorted { lhs, rhs in
            score(lhs, context: context) > score(rhs, context: context)
        }.first
    }

    static func ensureBestVoiceSelected() -> String {
        let defaults = UserDefaults.standard
        let existingIdentifier = defaults.string(forKey: voiceIdentifierKey) ?? ""
        let existingVoice = existingIdentifier.isEmpty ? nil : AVSpeechSynthesisVoice(identifier: existingIdentifier)
        guard let bestVoice = bestAvailableVoice() else {
            return existingVoice?.identifier ?? ""
        }

        if let existingVoice {
            let context = rankingContext()
            let existingScore = score(existingVoice, context: context)
            let bestScore = score(bestVoice, context: context)
            if existingScore >= bestScore {
                return existingVoice.identifier
            }
        }

        defaults.set(bestVoice.identifier, forKey: voiceIdentifierKey)
        return bestVoice.identifier
    }

    static func sortedVoices(_ voices: [AVSpeechSynthesisVoice] = AVSpeechSynthesisVoice.speechVoices()) -> [AVSpeechSynthesisVoice] {
        let context = rankingContext()
        return voices.sorted {
            let lhs = score($0, context: context)
            let rhs = score($1, context: context)
            if lhs != rhs { return lhs > rhs }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private static func rankingContext(locale: Locale = .current) -> (languageCode: String, preferredLanguage: String) {
        let languageCode = locale.language.languageCode?.identifier ?? "en"
        let preferredLanguage = locale.identifier.replacingOccurrences(of: "_", with: "-")
        return (languageCode, preferredLanguage)
    }

    private static func score(_ voice: AVSpeechSynthesisVoice, context: (languageCode: String, preferredLanguage: String)) -> Int {
        score(voice, languageCode: context.languageCode, preferredLanguage: context.preferredLanguage)
    }

    private static func score(_ voice: AVSpeechSynthesisVoice, languageCode: String, preferredLanguage: String) -> Int {
        var score = 0

        if voice.language == preferredLanguage { score += 250 }
        if voice.language.hasPrefix(languageCode) { score += 200 }
        if voice.language.hasPrefix("en") { score += 50 }

        switch voice.quality {
        case .premium:
            score += 1_000
        case .enhanced:
            score += 700
        default:
            score += 100
        }

        let lowerName = voice.name.lowercased()
        if lowerName.contains("siri") { score += 90 }
        if lowerName.contains("samantha") { score += 70 }
        if lowerName.contains("ava") { score += 65 }
        if lowerName.contains("allison") { score += 55 }
        if lowerName.contains("alex") { score += 45 }

        return score
    }
}

/// Voice settings page accessible from the main Settings.
/// Lets the user pick a system TTS voice, adjust speed and pitch,
/// and preview how it sounds.
struct VoiceSettingsView: View {
    @AppStorage("voice_speed") private var speed: Double = 0.5
    @AppStorage("voice_pitch") private var pitch: Double = 1.0
    @AppStorage(VoiceDefaults.voiceIdentifierKey) private var selectedVoiceId: String = ""
    @AppStorage("hey_hermes_enabled", store: SharedDefaults.shared) private var heyHermesEnabled = true

    @State private var availableVoices: [AVSpeechSynthesisVoice] = []
    @State private var filterQuality: Bool = true
    @State private var selectedProvider: TTSProvider = TTSProvider.selected
    @State private var keyInput = ""
    @State private var keyExistsForSelected = false
    @EnvironmentObject var appearance: AppearanceSettings

    private var accent: Color { appearance.accent }

    private func saveKey() {
        let key = keyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        TTSKeyStore.save(key, provider: selectedProvider)
        keyInput = ""
        keyExistsForSelected = true
    }

    var body: some View {
        Form {
            Section {
                ForEach(TTSProvider.allCases) { provider in
                    Button {
                        TTSProvider.selected = provider
                        selectedProvider = provider
                        keyExistsForSelected = TTSKeyStore.load(provider: provider) != nil
                    } label: {
                        HStack {
                            Circle()
                                .fill(provider.hasKey ? Color.green : Color.gray.opacity(0.4))
                                .frame(width: 8, height: 8)
                            Text(provider.displayName)
                                .foregroundStyle(.primary)
                            Spacer()
                            if !provider.isImplemented {
                                Text("soon")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            if selectedProvider == provider {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(accent)
                            }
                        }
                    }
                }

                if selectedProvider != .apple {
                    SecureField("API key for \(selectedProvider.displayName)", text: $keyInput)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onSubmit { saveKey() }
                    HStack {
                        Button(keyExistsForSelected ? "Update Key" : "Save Key") { saveKey() }
                            .disabled(keyInput.isEmpty)
                        if keyExistsForSelected {
                            Button("Remove Key", role: .destructive) {
                                TTSKeyStore.delete(provider: selectedProvider)
                                keyInput = ""
                                keyExistsForSelected = false
                            }
                        }
                    }
                }
            } header: {
                Text("Voice Provider")
            } footer: {
                Text("Green dot = key stored on this device (Apple needs none). Providers without a key or marked \"soon\" fall back to Apple voices. Keys stay in the iOS Keychain.")
            }

            Section {
                Toggle("Hey Hermes", isOn: $heyHermesEnabled)
            } header: {
                Text("Hands-Free Activation")
            } footer: {
                Text("When enabled, Hermes listens on-device for “Hey Hermes” while the app is open, then starts voice mode. iOS does not allow third-party wake phrases when the app is closed.")
            }

            Section {
                if let selectedVoice {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Current Voice")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(selectedVoice.name)
                                .font(.subheadline)
                        }
                        Spacer()
                        qualityBadge(selectedVoice.quality)
                    }
                }

                Button {
                    selectedVoiceId = VoiceDefaults.bestAvailableVoice(voices: availableVoices)?.identifier ?? selectedVoiceId
                } label: {
                    Label("Use Most Realistic Local Voice", systemImage: "sparkles")
                }

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
            selectedVoiceId = VoiceDefaults.ensureBestVoiceSelected()
            keyExistsForSelected = TTSKeyStore.load(provider: selectedProvider) != nil
        }
    }

    private var selectedVoice: AVSpeechSynthesisVoice? {
        AVSpeechSynthesisVoice(identifier: selectedVoiceId)
    }

    private var filteredVoices: [AVSpeechSynthesisVoice] {
        if filterQuality {
            return availableVoices.filter { $0.quality == .enhanced || $0.quality == .premium }
        }
        return availableVoices
    }

    private func refreshVoices() {
        availableVoices = VoiceDefaults.sortedVoices()
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

        // Don't hijack the shared session mid voice-conversation: switching
        // .playAndRecord to .playback kills the mic. Preview plays fine under
        // the conversation's existing session.
        let session = AVAudioSession.sharedInstance()
        if session.category != .playAndRecord {
            do {
                try session.setCategory(.playback, mode: .default)
                try session.setActive(true)
            } catch {
                FileLogger.shared.log("VoiceSettings: preview audio session failed: \(error.localizedDescription)")
            }
        }
        previewSynthesizer.speak(utterance)
    }
}
