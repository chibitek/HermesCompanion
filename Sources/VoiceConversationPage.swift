import SwiftUI
import AVFoundation

// MARK: - Cyberpunk Voice Presets

struct CyberpunkVoicePreset: Identifiable, CaseIterable, Equatable {
    let id: String
    let name: String
    let primary: Color
    let secondary: Color
    let background: Color

    static let matrix = CyberpunkVoicePreset(id: "matrix", name: "MATRIX", primary: Color(red: 0, green: 1, blue: 0.25), secondary: Color(red: 0, green: 0.56, blue: 0.07), background: .black)
    static let retroAmber = CyberpunkVoicePreset(id: "amber", name: "AMBER", primary: Color(red: 1, green: 0.65, blue: 0), secondary: Color(red: 0.8, green: 0.52, blue: 0), background: .black)
    static let neon = CyberpunkVoicePreset(id: "neon", name: "NEON", primary: Color(red: 1, green: 0, blue: 0.9), secondary: Color(red: 0, green: 0.94, blue: 1), background: .black)
    static let blueHacker = CyberpunkVoicePreset(id: "blue", name: "BLUE", primary: Color(red: 0, green: 0.74, blue: 1), secondary: Color(red: 0, green: 0.47, blue: 0.74), background: .black)

    static var allCases: [CyberpunkVoicePreset] = [.matrix, .retroAmber, .neon, .blueHacker]

    var next: CyberpunkVoicePreset {
        let all = CyberpunkVoicePreset.allCases
        let idx = all.firstIndex(of: self) ?? 0
        return all[(idx + 1) % all.count]
    }
}

// MARK: - Voice Conversation Page

struct VoiceConversationPage: View {
    @ObservedObject var voiceConversation: VoiceConversationManager
    var currentModel: String = ""
    var availableModels: [String] = []
    var onSelectModel: ((String) -> Void)? = nil
    var onVoiceTranscription: ((String) -> Void)? = nil
    var onClose: (() -> Void)? = nil

    @State private var preset: CyberpunkVoicePreset = .matrix
    @State private var showSettings = false
    @State private var micPulse = false

    var body: some View {
        ZStack {
            preset.background.ignoresSafeArea()
            ScanlineOverlay(lineColor: preset.primary)

            VStack(spacing: 0) {
                topBar
                Spacer()
                visualizer
                Spacer()
                transcriptionCards
                bottomControls
            }
            .padding()
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSettings) {
            VoiceSettingsSheet(preset: preset)
        }
        .onAppear {
            // Auto-start conversation when page opens
            voiceConversation.startConversation(
                onTranscription: { text in
                    onVoiceTranscription?(text)
                },
                onLocalResponse: { response in
                    voiceConversation.speakResponse(response)
                }
            )
        }
        .onDisappear {
            voiceConversation.stopConversation()
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button { onClose?() } label: {
                Image(systemName: "xmark")
                    .font(.title3)
                    .foregroundStyle(preset.primary)
            }

            Spacer()

            Text("HERMES VOICE")
                .font(.system(.headline, design: .monospaced).weight(.bold))
                .foregroundStyle(preset.primary)
                .shadow(color: preset.primary.opacity(0.6), radius: 4)

            Spacer()

            Button { preset = preset.next } label: {
                Text(preset.name)
                    .font(.system(.caption, design: .monospaced).weight(.bold))
                    .foregroundStyle(preset.background)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(preset.primary)
                    .clipShape(Capsule())
            }

            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.title3)
                    .foregroundStyle(preset.primary)
            }
        }
    }

    // MARK: - Visualizer

    private var visualizer: some View {
        VStack(spacing: 8) {
            // Large central orb that reacts to audio
            ZStack {
                // Outer glow ring
                Circle()
                    .stroke(preset.primary.opacity(0.2), lineWidth: 2)
                    .frame(width: 140, height: 140)
                    .scaleEffect(voiceConversation.isListening || voiceConversation.isSpeaking ? 1.15 : 1.0)
                    .animation(.easeInOut(duration: 0.3).repeatForever(autoreverses: true), value: voiceConversation.isListening)

                // Middle ring
                Circle()
                    .stroke(preset.primary.opacity(0.4), lineWidth: 2)
                    .frame(width: 110, height: 110)
                    .scaleEffect(voiceConversation.isSpeaking ? 1.1 : 0.95)
                    .animation(.easeInOut(duration: 0.4).repeatForever(autoreverses: true), value: voiceConversation.isSpeaking)

                // Inner orb
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [preset.primary.opacity(0.3), preset.primary.opacity(0.05)],
                            center: .center,
                            startRadius: 10,
                            endRadius: 45
                        )
                    )
                    .frame(width: 90, height: 90)

                // Audio level bars inside the orb
                AudioVisualizerBar(
                    color: preset.primary,
                    isActive: voiceConversation.isListening || voiceConversation.isSpeaking
                )
                .frame(width: 60, height: 40)
            }

            // Status label below the orb
            Text(statusLabel)
                .font(.system(.title3, design: .monospaced).weight(.bold))
                .foregroundStyle(preset.primary)
                .shadow(color: preset.primary.opacity(0.5), radius: 3)
        }
    }

    private var statusLabel: String {
        if voiceConversation.isThinking { return "THINKING..." }
        if voiceConversation.isSpeaking { return "SPEAKING..." }
        if voiceConversation.isListening { return "LISTENING..." }
        if voiceConversation.isConversing { return "TAP TO TALK" }
        return "SAY SOMETHING"
    }

    // MARK: - Transcription Cards

    private var transcriptionCards: some View {
        VStack(spacing: 8) {
            if !voiceConversation.transcribedText.isEmpty {
                cardView(label: "YOU", text: voiceConversation.transcribedText, color: preset.secondary)
            }
            if !voiceConversation.spokenResponse.isEmpty {
                cardView(label: "HERMES", text: voiceConversation.spokenResponse, color: preset.primary)
            }
        }
    }

    private func cardView(label: String, text: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
            Text(text)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(color.opacity(0.9))
                .lineLimit(5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(color.opacity(0.05))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(color.opacity(0.3), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        VStack(spacing: 12) {
            // Mode toggle
            HStack(spacing: 8) {
                ForEach(ConversationMode.allCases, id: \.self) { mode in
                    Button {
                        voiceConversation.conversationMode = mode
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: mode.icon)
                            Text(mode.rawValue)
                        }
                        .font(.system(.caption, design: .monospaced).weight(.bold))
                        .foregroundStyle(voiceConversation.conversationMode == mode ? preset.background : preset.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(voiceConversation.conversationMode == mode ? preset.primary : Color.clear)
                        .overlay(Capsule().stroke(preset.primary.opacity(0.4), lineWidth: 1))
                        .clipShape(Capsule())
                    }
                }
            }

            // Mic button
            Button {
                if voiceConversation.isConversing {
                    if voiceConversation.isListening {
                        voiceConversation.stopListening()
                    } else {
                        voiceConversation.startListening()
                    }
                } else {
                    voiceConversation.startConversation(
                        onTranscription: { text in
                            // Handle transcription in remote mode
                        },
                        onLocalResponse: { _ in }
                    )
                }
            } label: {
                ZStack {
                    Circle()
                        .stroke(preset.primary, lineWidth: 3)
                        .frame(width: 72, height: 72)
                    Circle()
                        .fill(voiceConversation.isListening ? preset.primary.opacity(0.2) : .clear)
                        .frame(width: 64, height: 64)
                    Image(systemName: voiceConversation.isListening ? "stop.fill" : "mic.fill")
                        .font(.title)
                        .foregroundStyle(preset.primary)
                }
            }
        }
    }
}

// MARK: - Audio Visualizer Bar

struct AudioVisualizerBar: View {
    let color: Color
    var secondaryColor: Color = .gray
    let isActive: Bool
    @State private var levels: [CGFloat] = Array(repeating: 0.3, count: 24)

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 3) {
                ForEach(0..<levels.count, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(i % 3 == 2 ? secondaryColor : color)
                        .frame(width: max(3, geo.size.width / CGFloat(levels.count) - 3))
                        .frame(height: max(4, geo.size.height * levels[i]))
                        .animation(.easeInOut(duration: 0.1), value: levels[i])
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .onAppear {
            if isActive { startAnimation() }
        }
    }

    private func startAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            for i in 0..<levels.count {
                levels[i] = CGFloat.random(in: 0.1...1.0)
            }
        }
    }
}

// MARK: - Scanline Overlay

struct ScanlineOverlay: View {
    var lineColor: Color = .white
    var lineSpacing: CGFloat = 3
    var lineOpacity: Double = 0.07

    var body: some View {
        Canvas { context, size in
            var y: CGFloat = 0
            while y < size.height {
                context.fill(
                    Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                    with: .color(lineColor.opacity(lineOpacity))
                )
                y += lineSpacing
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - CRT Glow Modifier

struct CRTGlow: ViewModifier {
    let color: Color
    var radius: CGFloat = 6
    var opacity: Double = 0.8

    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(opacity), radius: radius)
    }
}

extension View {
    func crtGlow(_ color: Color, radius: CGFloat = 6, opacity: Double = 0.8) -> some View {
        modifier(CRTGlow(color: color, radius: radius, opacity: opacity))
    }
}

// MARK: - Voice Settings Sheet

struct VoiceSettingsSheet: View {
    var preset: CyberpunkVoicePreset = .neon
    @State private var speed: Double = 0.5
    @State private var pitch: Double = 1.0
    @State private var selectedVoiceId: String = ""
    @State private var availableVoices: [AVSpeechSynthesisVoice] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 24) {
                        speedSection
                        pitchSection
                        voiceSection
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
                }
            }
        }
        .onAppear {
            availableVoices = AVSpeechSynthesisVoice.speechVoices()
                .filter { $0.quality == .enhanced }
                .sorted { $0.name < $1.name }
            if selectedVoiceId.isEmpty {
                selectedVoiceId = AVSpeechSynthesisVoice.speechVoices().first?.identifier ?? ""
            }
        }
    }

    private var speedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SPEED")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(preset.primary)
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
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var pitchSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PITCH")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(preset.secondary)
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
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var voiceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("VOICE")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(preset.primary)
            ForEach(availableVoices, id: \.identifier) { voice in
                voiceRow(voice)
            }
        }
        .padding(16)
        .background(preset.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func voiceRow(_ voice: AVSpeechSynthesisVoice) -> some View {
        let isSelected = voice.identifier == selectedVoiceId
        return Button {
            selectedVoiceId = voice.identifier
        } label: {
            HStack {
                Text(voice.name)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(isSelected ? preset.primary : .gray)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(preset.primary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? preset.primary.opacity(0.1) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }
}
