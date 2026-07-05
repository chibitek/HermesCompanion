import SwiftUI
import AVFoundation

// MARK: - Voice Conversation Page

/// Full-screen cyberpunk voice conversation page with scan lines, CRT glow,
/// glitch text, equalizer bars, and 4 switchable presets.
struct VoiceConversationPage: View {
    @ObservedObject var voiceConversation: VoiceConversationManager
    var currentModel: String = ""
    var availableModels: [String] = []
    var onSelectModel: ((String) -> Void)? = nil
    var onVoiceTranscription: ((String) -> Void)? = nil
    var onClose: (() -> Void)? = nil

    @State private var preset: CyberpunkVoicePreset = .matrix
    @State private var showSettings = false
    @State private var showModelPicker = false
    @State private var micPulse = false

    // Voice settings persisted via @AppStorage
    @AppStorage("voiceSpeed") private var voiceSpeed: Double = 0.5
    @AppStorage("voicePitch") private var voicePitch: Double = 1.0
    @AppStorage("voiceIdentifier") private var voiceIdentifier: String = ""

    var body: some View {
        ZStack {
            // 1. Deep black background
            preset.background.ignoresSafeArea()

            // 2. Subtle grid pattern
            GridPattern(color: preset.primary, spacing: 36, opacity: 0.03)
                .ignoresSafeArea()

            // 3. Main content
            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 16)

                visualizerSection
                    .frame(height: 220)

                Spacer(minLength: 12)

                statusText

                cardsSection
                    .padding(.horizontal, 24)
                    .padding(.top, 12)

                Spacer(minLength: 12)

                bottomControls
                    .padding(.bottom, 40)
            }
            .padding(.top, 8)

            // 4. Scanline overlay (top-most)
            ScanlineOverlay(lineSpacing: 3, lineOpacity: 0.05, lineColor: .white)
                .ignoresSafeArea()
        }
        .preferredColorScheme(.dark)
        .onAppear {
            syncVoiceSettings()
            // Start conversation if not already running
            if !voiceConversation.isConversing {
                voiceConversation.startConversation(
                    onTranscription: { text in onVoiceTranscription?(text) },
                    onLocalResponse: { _ in }
                )
            }
        }
        .onChange(of: voiceSpeed) { _, _ in syncVoiceSettings() }
        .onChange(of: voicePitch) { _, _ in syncVoiceSettings() }
        .onChange(of: voiceIdentifier) { _, _ in syncVoiceSettings() }
        .onChange(of: voiceConversation.isConversing) { _, active in
            if active {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    micPulse = true
                }
            } else {
                micPulse = false
            }
        }
        .sheet(isPresented: $showSettings) {
            VoiceSettingsSheet(speed: $voiceSpeed, pitch: $voicePitch, voiceIdentifier: $voiceIdentifier, preset: preset)
        }
        .confirmationDialog("SELECT MODEL", isPresented: $showModelPicker, titleVisibility: .visible) {
            ForEach(availableModels, id: \.self) { model in
                Button(model) { onSelectModel?(model) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func syncVoiceSettings() {
        voiceConversation.updateVoiceSettings(
            speed: Float(voiceSpeed),
            pitch: Float(voicePitch),
            identifier: voiceIdentifier
        )
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 16) {
            // Close
            Button {
                voiceConversation.stopConversation()
                onClose?()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(preset.primary)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(preset.primary.opacity(0.1)))
                    .overlay(Circle().stroke(preset.primary.opacity(0.4), lineWidth: 1))
                    .crtGlow(preset.primary, radius: 5)
            }
            .buttonStyle(.plain)

            // Title
            Text("HERMES VOICE")
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(preset.primary)
                .crtGlow(preset.primary, radius: 8)

            Spacer()

            // Settings gear
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 16, design: .monospaced))
                    .foregroundStyle(preset.secondary)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(preset.secondary.opacity(0.1)))
                    .overlay(Circle().stroke(preset.secondary.opacity(0.4), lineWidth: 1))
                    .crtGlow(preset.secondary, radius: 5)
            }
            .buttonStyle(.plain)

            // Preset selector pill
            Button {
                withAnimation(.easeInOut(duration: 0.3)) {
                    preset = preset.next
                }
            } label: {
                Text(preset.name)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(preset.background)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(preset.primary)
                    .clipShape(Capsule())
                    .crtGlow(preset.primary, radius: 5)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }

    // MARK: - Visualizer

    private var visualizerSection: some View {
        VStack(spacing: 12) {
            ZStack {
                // Outer neon ring
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [preset.primary.opacity(0.5), preset.secondary.opacity(0.3)],
                            startPoint: .top, endPoint: .bottom
                        ),
                        lineWidth: 2
                    )
                    .frame(width: 200, height: 200)
                    .crtGlow(preset.primary, radius: 10, opacity: 0.4)

                // Pulsing inner ring when listening
                if voiceConversation.isListening {
                    Circle()
                        .stroke(preset.primary.opacity(0.2), lineWidth: 1)
                        .frame(width: 160, height: 160)
                        .scaleEffect(micPulse ? 1.1 : 0.9)
                }

                // Equalizer bars
                EqualizerVisualizer(
                    audioLevel: voiceConversation.audioLevel,
                    preset: preset,
                    isActive: voiceConversation.isListening || voiceConversation.isSpeaking || voiceConversation.isThinking,
                    isSpeaking: voiceConversation.isSpeaking
                )
                .frame(width: 150, height: 80)
            }
        }
    }

    // MARK: - Status Text

    private var statusText: some View {
        GlitchText(
            text: statusLabel,
            font: .system(size: 26, weight: .bold, design: .monospaced),
            color: preset.primary,
            glitchIntensity: 2
        )
    }

    private var statusLabel: String {
        if voiceConversation.isThinking { return "THINKING..." }
        if voiceConversation.isSpeaking { return "SPEAKING..." }
        if voiceConversation.isListening { return "LISTENING..." }
        if voiceConversation.isConversing { return "STARTING..." }
        return "STANDBY"
    }

    // MARK: - Cards

    @ViewBuilder
    private var cardsSection: some View {
        VStack(spacing: 10) {
            if !voiceConversation.transcribedText.isEmpty && voiceConversation.isListening {
                NeonCard(label: "> INPUT", text: voiceConversation.transcribedText, color: preset.primary)
            }
            if !voiceConversation.spokenResponse.isEmpty && voiceConversation.isSpeaking {
                NeonCard(label: "> OUTPUT", text: voiceConversation.spokenResponse, color: preset.secondary)
            }
            if voiceConversation.isThinking {
                NeonCard(label: "> PROCESS", text: "Processing request...", color: preset.primary)
            }
        }
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        VStack(spacing: 20) {
            // Mode toggle + model selector
            HStack(spacing: 12) {
                Button {
                    voiceConversation.toggleMode()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: voiceConversation.conversationMode.icon)
                            .font(.system(size: 11, design: .monospaced))
                        Text(voiceConversation.conversationMode.rawValue.uppercased())
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                    }
                    .foregroundStyle(voiceConversation.conversationMode == .local ? preset.primary : preset.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .overlay(Capsule().stroke(voiceConversation.conversationMode == .local ? preset.primary : preset.secondary, lineWidth: 1))
                    .clipShape(Capsule())
                    .crtGlow(voiceConversation.conversationMode == .local ? preset.primary : preset.secondary, radius: 3, opacity: 0.4)
                }
                .buttonStyle(.plain)
                .disabled(voiceConversation.isSpeaking || voiceConversation.isThinking)

                Spacer()

                if !currentModel.isEmpty {
                    Button {
                        showModelPicker = true
                    } label: {
                        HStack(spacing: 4) {
                            Text(shortModel(currentModel))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(preset.primary)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(preset.primary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .overlay(Capsule().stroke(preset.primary.opacity(0.4), lineWidth: 1))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)

            // Large mic button
            Button {
                if voiceConversation.isConversing {
                    voiceConversation.stopConversation()
                    onClose?()
                } else {
                    voiceConversation.startConversation(
                        onTranscription: { text in onVoiceTranscription?(text) },
                        onLocalResponse: { _ in }
                    )
                }
            } label: {
                ZStack {
                    // Outer pulsing ring
                    Circle()
                        .stroke(preset.primary.opacity(0.3), lineWidth: 2)
                        .frame(width: 88, height: 88)
                        .scaleEffect(micPulse ? 1.15 : 0.9)
                        .opacity(micPulse ? 0 : 1)

                    // Main ring
                    Circle()
                        .stroke(preset.primary, lineWidth: 2.5)
                        .frame(width: 72, height: 72)
                        .crtGlow(preset.primary, radius: 10, opacity: 0.8)

                    // Icon
                    Image(systemName: micIcon)
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .foregroundStyle(preset.primary)
                        .crtGlow(preset.primary, radius: 6)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var micIcon: String {
        if voiceConversation.isListening { return "stop.fill" }
        if voiceConversation.isSpeaking { return "waveform" }
        if voiceConversation.isThinking { return "brain" }
        if voiceConversation.isConversing { return "waveform" }
        return "mic.fill"
    }

    private func shortModel(_ model: String) -> String {
        if model.contains("/") {
            return model.split(separator: "/").last.map { String($0) } ?? model
        }
        return model
    }
}

// MARK: - Equalizer Visualizer

/// 24 vertical bars that react to mic audio level.
struct EqualizerVisualizer: View {
    let audioLevel: Float
    let preset: CyberpunkVoicePreset
    let isActive: Bool
    let isSpeaking: Bool

    private let barCount = 24

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 3) {
                ForEach(0..<barCount, id: \.self) { i in
                    let center = Double(barCount) / 2.0
                    let dist = abs(Double(i) - center) / center
                    let base = 1.0 - dist * 0.5
                    let boost = isActive ? Double(audioLevel) * 1.5 : 0
                    let noise = isActive ? Double.random(in: 0.05...0.2) : 0
                    let h = max(0.05, min(1.0, base + boost + noise))

                    RoundedRectangle(cornerRadius: 2)
                        .fill(i % 3 == 2 ? preset.secondary : preset.primary)
                        .frame(width: 4, height: geo.size.height * h)
                        .opacity(isActive ? 1.0 : 0.25)
                        .crtGlow(i % 3 == 2 ? preset.secondary : preset.primary, radius: 3, opacity: 0.5)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
        }
    }
}

// MARK: - Neon Card

struct NeonCard: View {
    let label: String
    let text: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .crtGlow(color, radius: 3, opacity: 0.5)
            Text(text)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(color.opacity(0.9))
                .lineLimit(5)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(color.opacity(0.05))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(color, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .crtGlow(color, radius: 5, opacity: 0.3)
    }
}

// MARK: - Voice Settings Sheet

struct VoiceSettingsSheet: View {
    @Binding var speed: Double
    @Binding var pitch: Double
    @Binding var voiceIdentifier: String
    var preset: CyberpunkVoicePreset = .neon

    @Environment(\.dismiss) private var dismiss
    @State private var availableVoices: [AVSpeechSynthesisVoice] = []

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Speed
                        VStack(alignment: .leading, spacing: 8) {
                            Text("SPEED")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(preset.primary)
                                .crtGlow(preset.primary, radius: 3)
                            HStack {
                                Slider(value: $speed, in: 0.1...1.0, step: 0.05)
                                    .tint(preset.primary)
                                Text(String(format: "%.2f", speed))
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(preset.primary)
                            }
                        }
                        .padding(16)
                        .background(preset.primary.opacity(0.05))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(preset.primary.opacity(0.3), lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                        // Pitch
                        VStack(alignment: .leading, spacing: 8) {
                            Text("PITCH")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(preset.secondary)
                                .crtGlow(preset.secondary, radius: 3)
                            HStack {
                                Slider(value: $pitch, in: 0.5...2.0, step: 0.1)
                                    .tint(preset.secondary)
                                Text(String(format: "%.1f", pitch))
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(preset.secondary)
                            }
                        }
                        .padding(16)
                        .background(preset.secondary.opacity(0.05))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(preset.secondary.opacity(0.3), lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                        // Voice picker
                        VStack(alignment: .leading, spacing: 8) {
                            Text("VOICE")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(preset.primary)
                                .crtGlow(preset.primary, radius: 3)

                            ForEach(availableVoices, id: \.identifier) { voice in
                                let isSelected = voice.identifier == voiceIdentifier
                                Button {
                                    voiceIdentifier = voice.identifier
                                } label: {
                                    voiceRow(voice: voice, isSelected: isSelected)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(16)
                        .background(preset.primary.opacity(0.03))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(preset.primary.opacity(0.2), lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .padding(20)
                }
            }
            .navigationTitle("VOICE_CONFIG")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(preset.primary)
                        .font(.system(.body, design: .monospaced).weight(.bold))
                }
            }
        }
        .onAppear {
            availableVoices = AVSpeechSynthesisVoice.speechVoices()
                .filter { $0.quality == .enhanced }
                .sorted { $0.name < $1.name }
            if voiceIdentifier.isEmpty {
                voiceIdentifier = AVSpeechSynthesisVoice.currentIdentifier()
            }
        }
    }
}
