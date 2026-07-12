import SwiftUI
import AVFoundation

enum PremiumVoiceService: String, CaseIterable {
    case amazonPolly = "Amazon Polly"
    case googleCloudTTS = "Google Cloud TTS"
    
    var displayName: String {
        switch self {
        case .amazonPolly: return "Amazon Polly"
        case .googleCloudTTS: return "Google Cloud Text-to-Speech"
        }
    }
    
    var availableVoices: [String] {
        switch self {
        case .amazonPolly:
            return ["Joanna", "Matthew", "Salli", "Kevin", "Ivy", "Kendra", "Kimberly", "Justin"]
        case .googleCloudTTS:
            return ["en-US-Standard-A", "en-US-Standard-B", "en-US-Standard-C", "en-US-Standard-D", "en-US-Standard-E", "en-US-Standard-F", "en-US-Standard-G", "en-US-Standard-H", "en-US-Standard-I", "en-US-Standard-J"]
        }
    }
    
    var defaultVoice: String {
        switch self {
        case .amazonPolly: return "Joanna"
        case .googleCloudTTS: return "en-US-Standard-A"
        }
    }
}

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
    @AppStorage("premium_voice_service") private var premiumVoiceService: String = PremiumVoiceService.amazonPolly.rawValue
    @AppStorage("premium_voice_name") private var premiumVoiceName: String = "Joanna"
    @AppStorage("premium_voice_speed") private var premiumVoiceSpeed: Double = 1.0
    @AppStorage("premium_voice_pitch") private var premiumVoicePitch: Double = 1.0
    @AppStorage("hey_hermes_enabled") private var heyHermesEnabled = true

    @State private var availableVoices: [AVSpeechSynthesisVoice] = []
    @State private var filterQuality: Bool = true
    @EnvironmentObject var appearance: AppearanceSettings

    private var accent: Color { appearance.accent }

    var body: some View {
        Form {
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

            // Premium Voice Service Settings
            Section {
                Picker("Service", selection: $premiumVoiceService) {
                    ForEach(PremiumVoiceService.allCases, id: \.rawValue) { service in
                        Text(service.displayName).tag(service.rawValue)
                    }
                }
                .pickerStyle(.menu)
                
                let currentService = PremiumVoiceService(rawValue: premiumVoiceService) ?? .amazonPolly
                Picker("Voice", selection: $premiumVoiceName) {
                    ForEach(currentService.availableVoices, id: \.self) { voice in
                        Text(voice).tag(voice)
                    }
                }
                .pickerStyle(.menu)
                
                HStack {
                    Text("Speed")
                    Spacer()
                    Text(String(format: "%.2f", premiumVoiceSpeed))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Slider(value: $premiumVoiceSpeed, in: 0.25...2.0, step: 0.05)
                    .tint(accent)
                    
                HStack {
                    Text("Pitch")
                    Spacer()
                    Text(String(format: "%.1f", premiumVoicePitch))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Slider(value: $premiumVoicePitch, in: 0.5...2.0, step: 0.1)
                    .tint(accent)
            } header: {
                Text("Premium Voice Service")
            } footer: {
                Text("Premium voice services offer higher quality synthetic voices. Requires internet connection.")
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
        
        // Check if we're using premium voice settings
        let currentService = PremiumVoiceService(rawValue: premiumVoiceService) ?? .amazonPolly
        let usePremiumSettings = currentService.availableVoices.contains(premiumVoiceName)
        
        if usePremiumSettings {
            // Use premium voice settings for preview
            // Map premium speed (0.25...2.0) to AVSpeechUtterance rate range (0...1, default 0.5)
            let mappedSpeed = Float(premiumVoiceSpeed * 0.5) // Scale to fit within system TTS range
            utterance.rate = max(AVSpeechUtteranceMinimumSpeechRate,
                                min(AVSpeechUtteranceMaximumSpeechRate, mappedSpeed))
            utterance.pitchMultiplier = Float(premiumVoicePitch)
            
            // Try to find a premium-quality voice if available
            if let voice = findPremiumQualityVoice() {
                utterance.voice = voice
            } else {
                // Fallback to system voice
                if !selectedVoiceId.isEmpty,
                   let voice = AVSpeechSynthesisVoice(identifier: selectedVoiceId) {
                    utterance.voice = voice
                } else {
                    utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.identifier)
                }
            }
        } else {
            // Use regular system voice settings
            if !selectedVoiceId.isEmpty,
               let voice = AVSpeechSynthesisVoice(identifier: selectedVoiceId) {
                utterance.voice = voice
            } else {
                utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.identifier)
            }
            utterance.rate = max(AVSpeechUtteranceMinimumSpeechRate,
                                min(AVSpeechUtteranceMaximumSpeechRate, Float(speed)))
            utterance.pitchMultiplier = Float(pitch)
        }
        
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {}
        previewSynthesizer.speak(utterance)
    }
    
    /// Find a premium-quality voice that matches the selected service
    private func findPremiumQualityVoice() -> AVSpeechSynthesisVoice? {
        let allVoices = AVSpeechSynthesisVoice.speechVoices()
        
        // Filter for premium quality voices
        let premiumVoices = allVoices.filter { $0.quality == .premium }
        
        // If we have premium voices, try to find one that matches our settings
        if !premiumVoices.isEmpty {
            // Try to find a voice with a name that matches our premium voice name
            if let matchingVoice = premiumVoices.first(where: { 
                $0.name.localizedCaseInsensitiveContains(premiumVoiceName) 
            }) {
                return matchingVoice
            }
            
            // Fallback to the first premium voice
            return premiumVoices.first
        }
        
        // No premium voices available, return nil to use fallback
        return nil
    }
}
