import SwiftUI
import AVFoundation

// MARK: - Voice Conversation Page

/// Full-screen cyberpunk-themed voice conversation page.
/// Replaces the old overlay with a dedicated immersive experience
/// featuring real-time audio visualizer, neon styling, and voice settings.
struct VoiceConversationPage: View {
    @ObservedObject var voiceConversation: VoiceConversationManager
    var currentModel: String = ""
    var availableModels: [String] = []
    var onSelectModel: ((String) -> Void)? = nil
    var onRemoteTranscription: ((String) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appearance: AppearanceSettings

    // Voice settings
    @AppStorage("voiceSpeed") private var voiceSpeed: Double = 0.5
    @AppStorage("voicePitch") private var voicePitch: Double = 1.0
    @AppStorage("voiceIdentifier") private var voiceIdentifier: String = ""
    @State private var showSettings = false

    // Cyberpunk colors
    private let neonCyan = Color(red: 0.0, green: 0.941, blue: 1.0)
    private let neonMagenta = Color(red: 1.0, green: 0.0, blue: 0.898)
    private let darkBg = Color(red: 0.031, green: 0.031, blue: 0.059)

    var body: some View {
        ZStack {
            // Deep dark background
            darkBg
                .ignoresSafeArea()

            // Matrix grid background
            CyberGridBackground()
                .ignoresSafeArea()
                .opacity(0.15)

            VStack(spacing: 0) {
                topBar

                Spacer()

                // Center visualizer
                visualizerSection

                Spacer()

                // Status + text cards
                statusAndCards

                Spacer()

                // Bottom controls
                bottomControls
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSettings) {
            VoiceSettingsSheet(
                speed: $voiceSpeed,
                pitch: $voicePitch,
                voiceIdentifier: $voiceIdentifier
            )
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button {
                voiceConversation.stopConversation()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.title2)
                    .foregroundStyle(neonCyan)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(neonCyan.opacity(0.1)))
                    .overlay(Circle().stroke(neonCyan.opacity(0.4), lineWidth: 1))
            }
            .buttonStyle(.plain)

            Spacer()

            Text("HERMES VOICE")
                .font(.system(.headline, design: .monospaced).weight(.bold))
                .foregroundStyle(neonCyan)
                .shadow(color: neonCyan.opacity(0.6), radius: 8)

            Spacer()

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.title2)
                    .foregroundStyle(neonMagenta)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(neonMagenta.opacity(0.1)))
                    .overlay(Circle().stroke(neonMagenta.opacity(0.4), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 10)
    }

    // MARK: - Visualizer

    private var visualizerSection: some View {
        VStack(spacing: 16) {
            // Glowing ring + waveform bars
            ZStack {
                // Outer neon ring
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [neonCyan.opacity(0.6), neonMagenta.opacity(0.4)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 2
                    )
                    .frame(width: 200, height: 200)
                    .shadow(color: neonCyan.opacity(0.3), radius: 12)
                    .scaleEffect(voiceConversation.isSpeaking ? 1.05 : 1.0)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                               value: voiceConversation.isSpeaking)

                // Inner pulsing ring when listening
                if voiceConversation.isListening {
                    Circle()
                        .stroke(neonCyan.opacity(0.3), lineWidth: 1)
                        .frame(width: 160, height: 160)
                        .scaleEffect(voiceConversation.isListening ? 1.1 : 0.9)
                        .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                                   value: voiceConversation.isListening)
                }

                // Cyberpunk waveform bars
                CyberpunkVisualizer(
                    audioLevel: voiceConversation.audioLevel,
                    isActive: voiceConversation.isListening || voiceConversation.isSpeaking || voiceConversation.isThinking,
                    isListening: voiceConversation.isListening,
                    isSpeaking: voiceConversation.isSpeaking,
                    isThinking: voiceConversation.isThinking
                )
                .frame(width: 140, height: 80)
            }
        }
    }

    // MARK: - Status + Cards

    private var statusAndCards: some View {
        VStack(spacing: 16) {
            // Status text
            Text(statusText)
                .font(.system(.title2, design: .monospaced).weight(.bold))
                .foregroundStyle(statusColor)
                .shadow(color: statusColor.opacity(0.6), radius: 6)
                .modifier(GlitchEffect(active: voiceConversation.isListening))

            // Transcribed text card
            if !voiceConversation.transcribedText.isEmpty &&
                (voiceConversation.isListening || voiceConversation.isThinking) {
                NeonCard(
                    title: "YOU",
                    text: voiceConversation.transcribedText,
                    borderColor: neonCyan,
                    bgColor: neonCyan
                )
                .transition(.asymmetric(
                    insertion: .scale.combined(with: .opacity),
                    removal: .opacity
                ))
            }

            // Response text card
            if !voiceConversation.spokenResponse.isEmpty &&
                (voiceConversation.isSpeaking || voiceConversation.isListening) {
                NeonCard(
                    title: "HERMES",
                    text: voiceConversation.spokenResponse,
                    borderColor: neonMagenta,
                    bgColor: neonMagenta
                )
                .transition(.asymmetric(
                    insertion: .scale.combined(with: .opacity),
                    removal: .opacity
                ))
            }
        }
        .animation(.spring(duration: 0.4), value: voiceConversation.transcribedText)
        .animation(.spring(duration: 0.4), value: voiceConversation.spokenResponse)
    }

    private var statusText: String {
        if voiceConversation.isThinking {
            return "THINKING..."
        } else if voiceConversation.isSpeaking {
            return "SPEAKING..."
        } else if voiceConversation.isListening {
            return "LISTENING..."
        } else if voiceConversation.isConversing {
            return "STARTING..."
        } else {
            return "SAY SOMETHING..."
        }
    }

    private var statusColor: Color {
        if voiceConversation.isThinking {
            return neonMagenta
        } else if voiceConversation.isSpeaking {
            return neonMagenta
        } else if voiceConversation.isListening {
            return neonCyan
        } else {
            return neonCyan.opacity(0.7)
        }
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        VStack(spacing: 20) {
            // Mode toggle
            HStack(spacing: 4) {
                ForEach(ConversationMode.allCases, id: \.self) { mode in
                    Button {
                        if voiceConversation.conversationMode != mode {
                            voiceConversation.toggleMode()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: mode.icon)
                                .font(.caption)
                            Text(mode.rawValue.uppercased())
                                .font(.system(.caption, design: .monospaced).weight(.bold))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .foregroundStyle(voiceConversation.conversationMode == mode ? .black : neonCyan)
                        .background {
                            if voiceConversation.conversationMode == mode {
                                Capsule().fill(neonCyan)
                            } else {
                                Capsule().fill(neonCyan.opacity(0.08))
                            }
                        }
                        .overlay(
                            Capsule().stroke(neonCyan.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(voiceConversation.isSpeaking || voiceConversation.isThinking)
                }
            }

            // Model selector pill
            if !currentModel.isEmpty {
                Button {
                    // Cycle through models
                    if let idx = availableModels.firstIndex(of: currentModel),
                       idx + 1 < availableModels.count {
                        onSelectModel?(availableModels[idx + 1])
                    } else if let first = availableModels.first {
                        onSelectModel?(first)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(neonMagenta)
                            .frame(width: 6, height: 6)
                        Text(shortModel(currentModel))
                            .font(.system(.caption, design: .monospaced))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.black.opacity(0.6)))
                    .overlay(Capsule().stroke(neonMagenta.opacity(0.5), lineWidth: 1))
                    .foregroundStyle(neonMagenta)
                }
                .buttonStyle(.plain)
            }

            // Large mic button
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
                            onRemoteTranscription?(text)
                        },
                        onLocalResponse: { _ in }
                    )
                }
            } label: {
                ZStack {
                    // Outer ring
                    Circle()
                        .strokeBorder(
                            voiceConversation.isListening ? neonCyan : neonCyan.opacity(0.3),
                            lineWidth: 3
                        )
                        .frame(width: 80, height: 80)
                        .shadow(
                            color: voiceConversation.isListening ? neonCyan.opacity(0.6) : .clear,
                            radius: 12
                        )
                        .scaleEffect(voiceConversation.isListening ? 1.1 : 1.0)
                        .animation(
                            .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                            value: voiceConversation.isListening
                        )

                    // Inner circle
                    Circle()
                        .fill(
                            voiceConversation.isConversing
                                ? neonCyan.opacity(0.15)
                                : Color.white.opacity(0.05)
                        )
                        .frame(width: 64, height: 64)

                    // Icon
                    Image(systemName: micIcon)
                        .font(.title)
                        .foregroundStyle(neonCyan)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var micIcon: String {
        if voiceConversation.isConversing {
            if voiceConversation.isListening {
                return "stop.fill"
            } else if voiceConversation.isSpeaking {
                return "waveform"
            } else if voiceConversation.isThinking {
                return "brain"
            }
            return "waveform"
        }
        return "mic.fill"
    }

    private func shortModel(_ model: String) -> String {
        if model.contains("/") {
            return String(model.split(separator: "/").last ?? "")
        }
        return model
    }
}

// MARK: - Neon Card

/// A card with neon border for displaying transcribed/response text.
struct NeonCard: View {
    let title: String
    let text: String
    let borderColor: Color
    let bgColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(.caption, design: .monospaced).weight(.bold))
                .foregroundStyle(borderColor)

            Text(text)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(4)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.black.opacity(0.5))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderColor.opacity(0.6), lineWidth: 1.5)
        )
        .shadow(color: bgColor.opacity(0.2), radius: 6)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Cyberpunk Visualizer

/// Cyberpunk waveform bars that react to mic audio levels.
struct CyberpunkVisualizer: View {
    let audioLevel: Float
    let isActive: Bool
    let isListening: Bool
    let isSpeaking: Bool
    let isThinking: Bool

    @State private var phase: Double = 0

    private let barCount = 24
    private let neonCyan = Color(red: 0.0, green: 0.941, blue: 1.0)
    private let neonMagenta = Color(red: 1.0, green: 0.0, blue: 0.898)

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 3) {
                ForEach(0..<barCount, id: \.self) { i in
                    let center = Double(barCount) / 2.0
                    let distFromCenter = abs(Double(i) - center) / center
                    let baseHeight = 1.0 - distFromCenter * 0.6

                    let audioBoost = isActive ? CGFloat(audioLevel * 2.0) : 0
                    let randomNoise = isActive ? CGFloat.random(in: 0.1...0.3) : 0
                    let finalHeight = max(0.05, baseHeight + Double(audioBoost) + Double(randomNoise))

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [neonCyan, neonMagenta],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(width: 4, height: geo.size.height * finalHeight)
                        .opacity(isActive ? 1.0 : 0.3)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .onAppear {
                if isActive {
                    withAnimation(.linear(duration: 0.1).repeatForever(autoreverses: false)) {
                        phase = 1
                    }
                }
            }
            .onChange(of: isActive) { _, active in
                if active {
                    withAnimation(.linear(duration: 0.1).repeatForever(autoreverses: false)) {
                        phase = 1
                    }
                } else {
                    phase = 0
                }
            }
        }
    }
}

// MARK: - Cyberpunk Grid Background

/// Subtle animated grid/matrix background.
struct CyberGridBackground: View {
    private let neonCyan = Color(red: 0.0, green: 0.941, blue: 1.0)

    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 30
            let cols = Int(size.width / spacing) + 1
            let rows = Int(size.height / spacing) + 1

            // Vertical lines
            for i in 0..<cols {
                let x = CGFloat(i) * spacing
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(neonCyan.opacity(0.06)), lineWidth: 0.5)
            }

            // Horizontal lines
            for i in 0..<rows {
                let y = CGFloat(i) * spacing
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(neonCyan.opacity(0.06)), lineWidth: 0.5)
            }
        }
    }
}

// MARK: - Glitch Effect

/// Subtle glitch animation for text.
struct GlitchEffect: ViewModifier {
    let active: Bool
    @State private var offset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .offset(x: active ? offset : 0)
            .onAppear {
                guard active else { return }
                withAnimation(.easeInOut(duration: 0.08).repeatForever(autoreverses: true)) {
                    offset = CGFloat.random(in: -1.5...1.5)
                }
            }
    }
}

// MARK: - Voice Settings Sheet

/// Settings sheet for voice speed, pitch, and voice picker.
struct VoiceSettingsSheet: View {
    @Binding var speed: Double
    @Binding var pitch: Double
    @Binding var voiceIdentifier: String

    @Environment(\.dismiss) private var dismiss
    @State private var availableVoices: [AVSpeechSynthesisVoice] = []

    private let neonCyan = Color(red: 0.0, green: 0.941, blue: 1.0)
    private let neonMagenta = Color(red: 1.0, green: 0.0, blue: 0.898)
    private let darkBg = Color(red: 0.031, green: 0.031, blue: 0.059)

    var body: some View {
        NavigationStack {
            ZStack {
                darkBg.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 28) {
                        // Voice speed
                        VStack(alignment: .leading, spacing: 12) {
                            Label("SPEED", systemImage: "gauge")
                                .font(.system(.headline, design: .monospaced).weight(.bold))
                                .foregroundStyle(neonCyan)

                            HStack {
                                Text("0.1")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                Slider(value: $speed, in: 0.1...1.0, step: 0.05)
                                    .tint(neonCyan)
                                Text("1.0")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }

                            Text(String(format: "%.2fx", speed))
                                .font(.system(.body, design: .monospaced).weight(.bold))
                                .foregroundStyle(neonCyan)
                        }
                        .padding(16)
                        .background(Color.black.opacity(0.5))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(neonCyan.opacity(0.4), lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        // Pitch
                        VStack(alignment: .leading, spacing: 12) {
                            Label("PITCH", systemImage: "waveform.path.ecg")
                                .font(.system(.headline, design: .monospaced).weight(.bold))
                                .foregroundStyle(neonMagenta)

                            HStack {
                                Text("0.5")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                Slider(value: $pitch, in: 0.5...2.0, step: 0.1)
                                    .tint(neonMagenta)
                                Text("2.0")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }

                            Text(String(format: "%.1f", pitch))
                                .font(.system(.body, design: .monospaced).weight(.bold))
                                .foregroundStyle(neonMagenta)
                        }
                        .padding(16)
                        .background(Color.black.opacity(0.5))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(neonMagenta.opacity(0.4), lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        // Voice picker
                        VStack(alignment: .leading, spacing: 12) {
                            Label("VOICE", systemImage: "person.wave.2")
                                .font(.system(.headline, design: .monospaced).weight(.bold))
                                .foregroundStyle(neonCyan)

                            if availableVoices.isEmpty {
                                Text("No enhanced voices available")
                                    .font(.system(.subheadline, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .padding(.vertical, 8)
                            } else {
                                ForEach(availableVoices, id: \.identifier) { voice in
                                    Button {
                                        voiceIdentifier = voice.identifier
                                    } label: {
                                        HStack {
                                            Text(voice.name)
                                                .font(.system(.body, design: .monospaced))
                                                .foregroundStyle(.white)
                                            Spacer()
                                            Text("(\(voice.quality == 2 ? "enhanced" : "default"))")
                                                .font(.system(.caption2, design: .monospaced))
                                                .foregroundStyle(.secondary)
                                            if voice.identifier == voiceIdentifier {
                                                Image(systemName: "checkmark")
                                                    .foregroundStyle(neonCyan)
                                            }
                                        }
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 12)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(voice.identifier == voiceIdentifier
                                                      ? neonCyan.opacity(0.15)
                                                      : Color.clear)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(voice.identifier == voiceIdentifier
                                                        ? neonCyan.opacity(0.5)
                                                        : Color.clear,
                                                        lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(16)
                        .background(Color.black.opacity(0.5))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(neonCyan.opacity(0.4), lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(20)
                }
            }
            .navigationTitle("VOICE SETTINGS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(neonCyan)
                        .font(.system(.body, design: .monospaced).weight(.bold))
                }
            }
        }
        .onAppear {
            availableVoices = AVSpeechSynthesisVoice.speechVoices()
                .filter { $0.quality == .enhanced }
                .sorted { $0.name < $1.name }

            // If no voice selected, pick default
            if voiceIdentifier.isEmpty {
                voiceIdentifier = AVSpeechSynthesisVoice.currentIdentifier()
            }
        }
    }
}
