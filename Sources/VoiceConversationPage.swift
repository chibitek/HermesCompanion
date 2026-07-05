import SwiftUI
import AVFoundation

// MARK: - Cyberpunk Voice Conversation Page

struct VoiceConversationPage: View {
    @ObservedObject var voiceManager: VoiceConversationManager
    var currentModel: String = ""
    var availableModels: [String] = []
    var onSelectModel: ((String) -> Void)? = nil
    var onRemoteTranscription: ((String) -> Void)? = nil
    var onSpeakResponse: ((String) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var showSettings = false
    @State private var audioLevels: [CGFloat] = Array(repeating: 0.1, count: 24)
    @State private var showModelPicker = false
    @AppStorage("voice_speed") private var voiceSpeed: Double = 1.0
    @AppStorage("voice_pitch") private var voicePitch: Double = 1.0
    @AppStorage("voice_identifier") private var identifier: String = ""

    private let neonCyan = Color(red: 0, green: 0.94, blue: 1)
    private let neonMagenta = Color(red: 1, green: 0, blue: 0.9)

    var body: some View {
        ZStack {
            Color(red: 0.03, green: 0.03, blue: 0.06).ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer()
                visualizer
                statusLabel
                textCards
                Spacer()
                controls
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            voiceManager.requestAuthorization()
            voiceManager.updateVoiceSettings(speed: Float(voiceSpeed), pitch: Float(voicePitch), identifier: voiceIdentifier)
            startAnimation()
        }
        .onDisappear { voiceManager.stopConversation() }
        .sheet(isPresented: $showSettings) {
            VoiceSettingsSheet(speed: $voiceSpeed, pitch: $voicePitch, identifier: $voiceIdentifier)
        }
    }

    // Top bar
    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.title3).foregroundStyle(neonCyan)
            }
            Spacer()
            Text("HERMES VOICE")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(neonCyan)
                .shadow(color: neonCyan.opacity(0.6), radius: 4)
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "gearshape").font(.title3).foregroundStyle(neonCyan)
            }
        }
        .padding(.top, 16)
        .padding(.bottom, 24)
    }

    // Visualizer
    private var visualizer: some View {
        ZStack {
            Circle()
                .stroke(statusColor.opacity(0.3), lineWidth: 2)
                .frame(width: 200, height: 200)
                .shadow(color: statusColor.opacity(0.5), radius: 10)

            HStack(spacing: 3) {
                ForEach(0..<24, id: \.self) { i in
                    bar(i)
                }
            }
        }
        .frame(height: 220)
    }

    private func bar(_ i: Int) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(LinearGradient(colors: [neonCyan, neonMagenta], startPoint: .bottom, endPoint: .top))
            .frame(width: 6, height: max(4, 80 * audioLevels[i]))
            .shadow(color: neonCyan.opacity(0.4), radius: 2)
    }

    // Status
    private var statusLabel: some View {
        Text(label)
            .font(.system(size: 13, weight: .medium, design: .monospaced))
            .foregroundStyle(statusColor)
            .shadow(color: statusColor.opacity(0.5), radius: 3)
            .padding(.top, 16)
    }

    private var label: String {
        if voiceManager.isSpeaking { return "SPEAKING..." }
        if voiceManager.isThinking { return "THINKING..." }
        if voiceManager.isListening { return "LISTENING..." }
        return "SAY SOMETHING..."
    }

    private var statusColor: Color {
        if voiceManager.isSpeaking { return neonMagenta }
        if voiceManager.isThinking { return .yellow }
        return neonCyan
    }

    // Text cards
    private var textCards: some View {
        VStack(spacing: 12) {
            if !voiceManager.transcribedText.isEmpty {
                card(voiceManager.transcribedText, neonCyan, "YOU")
            }
            if !voiceManager.spokenResponse.isEmpty {
                card(voiceManager.spokenResponse, neonMagenta, "HERMES")
            }
        }
        .padding(.top, 24)
    }

    private func card(_ text: String, _ color: Color, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
            Text(text)
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(.white)
                .lineLimit(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(color.opacity(0.05))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.3), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // Controls
    private var controls: some View {
        VStack(spacing: 16) {
            // Mode toggle
            HStack(spacing: 12) {
                modeBtn("LOCAL", voiceManager.conversationMode == .local) {
                    voiceManager.conversationMode = .local
                }
                modeBtn("REMOTE", voiceManager.conversationMode == .remote) {
                    voiceManager.conversationMode = .remote
                }
            }

            // Model picker
            if !currentModel.isEmpty {
                Menu {
                    ForEach(availableModels, id: \.self) { m in
                        Button(m) { onSelectModel?(m) }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(shortModel(currentModel)).font(.system(size: 11, design: .monospaced))
                        Image(systemName: "chevron.down").font(.system(size: 9))
                    }
                    .foregroundStyle(neonCyan)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(neonCyan.opacity(0.1))
                    .clipShape(Capsule())
                }
            }

            // Mic button
            Button { toggle() } label: {
                ZStack {
                    Circle()
                        .stroke(statusColor.opacity(0.4), lineWidth: 3)
                        .frame(width: 72, height: 72)
                        .shadow(color: statusColor.opacity(0.5), radius: 8)
                    Circle()
                        .fill(voiceManager.isConversing ? statusColor : Color.white.opacity(0.1))
                        .frame(width: 56, height: 56)
                    Image(systemName: voiceManager.isConversing ? "stop.fill" : "mic.fill")
                        .font(.title2)
                        .foregroundStyle(voiceManager.isConversing ? .black : .white)
                }
            }
        }
    }

    private func modeBtn(_ text: String, _ active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(active ? .black : neonCyan)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(active ? neonCyan : neonCyan.opacity(0.1))
                .clipShape(Capsule())
        }
    }

    private func shortModel(_ m: String) -> String {
        if m.contains("/") { return m.split(separator: "/").last.map { String($0) } ?? m }
        return m
    }

    private func toggle() {
        if voiceManager.isConversing {
            voiceManager.stopConversation()
        } else {
            voiceManager.startConversation(
                onTranscription: { text in
                    if voiceManager.conversationMode == .remote { onRemoteTranscription?(text) }
                },
                onLocalResponse: { response in
                    onSpeakResponse?(response)
                }
            )
        }
    }

    private func startAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in
            if voiceManager.isListening || voiceManager.isSpeaking {
                audioLevels = (0..<24).map { i in
                    let c = 12.0
                    let d = abs(Double(i) - c) / c
                    return CGFloat(min(1.0, 0.2 + (1.0 - d) * 0.3 + Double.random(in: 0...0.4)))
                }
            } else {
                audioLevels = Array(repeating: 0.08, count: 24)
            }
        }
    }
}

// MARK: - Voice Settings Sheet

struct VoiceSettingsSheet: View {
    @Binding var speed: Double
    @Binding var pitch: Double
    @Binding var identifier: String
    @Environment(\.dismiss) private var dismiss

    private let neonCyan = Color(red: 0, green: 0.94, blue: 1)
    @State private var voices: [AVSpeechSynthesisVoice] = []

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.03, green: 0.03, blue: 0.06).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 24) {
                        sliderSection("SPEED", value: $speed, range: 0.5...2.0, format: "%.1fx")
                        sliderSection("PITCH", value: $pitch, range: 0.5...2.0, format: "%.1f")
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
                        .foregroundStyle(neonCyan)
                        .font(.system(.body, design: .monospaced).weight(.bold))
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            voices = AVSpeechSynthesisVoice.speechVoices()
                .filter { $0.quality == .enhanced }
                .sorted { $0.name < $1.name }
            if voiceIdentifier.isEmpty { voiceIdentifier = AVSpeechSynthesisVoice.defaultVoice.identifier }
        }
    }

    private func sliderSection(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, format: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(neonCyan)
            Slider(value: value, in: range, step: 0.1).tint(neonCyan)
            Text(String(format: format, value.wrappedValue))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.gray)
        }
    }

    private var voiceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("VOICE")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(neonCyan)
            ForEach(voices, id: \.identifier) { v in
                voiceRow(v)
            }
        }
    }

    private func voiceRow(_ v: AVSpeechSynthesisVoice) -> some View {
        let sel = v.identifier == voiceIdentifier
        return Button {
            voiceIdentifier = v.identifier
        } label: {
            HStack {
                Text("\(v.name) (\(v.language))")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(sel ? neonCyan : .gray)
                Spacer()
                if sel { Image(systemName: "checkmark").foregroundStyle(neonCyan) }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}
