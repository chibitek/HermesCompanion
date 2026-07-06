import SwiftUI
import AVFoundation

// MARK: - Cyberpunk Voice Presets

struct CyberpunkVoicePreset: Identifiable, CaseIterable, Equatable {
    let id: String
    let name: String
    let primary: Color
    let secondary: Color
    let background: Color

    static let matrix = CyberpunkVoicePreset(
        id: "matrix", 
        name: "MATRIX", 
        primary: Color(red: 0, green: 1, blue: 0.25), // #00FF41
        secondary: Color(red: 0, green: 0.56, blue: 0.07), 
        background: .black
    )
    
    static let retroAmber = CyberpunkVoicePreset(
        id: "amber", 
        name: "AMBER", 
        primary: Color(red: 1, green: 0.65, blue: 0), // #F2A900
        secondary: Color(red: 0.8, green: 0.52, blue: 0), 
        background: .black
    )
    
    static let neon = CyberpunkVoicePreset(
        id: "neon", 
        name: "NEON", 
        primary: Color(red: 1, green: 0, blue: 0.9), // #FF00E6
        secondary: Color(red: 0, green: 0.94, blue: 1), 
        background: .black
    )
    
    static let blueHacker = CyberpunkVoicePreset(
        id: "blue", 
        name: "BLUE", 
        primary: Color(red: 0, green: 0.74, blue: 1), // #00BDFF
        secondary: Color(red: 0, green: 0.47, blue: 0.74), 
        background: .black
    )

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
    var store: AppStore? = nil
    var currentModel: String = ""
    var availableModels: [String] = []
    var onSelectModel: ((String) -> Void)? = nil
    var onVoiceTranscription: ((String) -> Void)? = nil
    var onClose: (() -> Void)? = nil

    @State private var preset: CyberpunkVoicePreset = .matrix
    @State private var showSettings = false
    @State private var showSessionPicker = false
    @State private var micPulse = false

    // Rain intensity changes with conversation state
    private var rainIntensity: Double {
        if voiceConversation.isListening { return 1.0 }      // Fast rain
        if voiceConversation.isSpeaking { return 0.7 }       // Medium, glowing
        if voiceConversation.isThinking { return 0.3 }       // Slow
        return 0.5                                            // Idle
    }

    var body: some View {
        ZStack {
            // Background layers (bottom→top)
            // 1. Matrix digital rain background
            MatrixRainView(
                color: preset.primary,
                secondaryColor: preset.secondary,
                intensity: rainIntensity
            )
            .ignoresSafeArea()

            // 2. Scanlines
            ScanlineOverlay(lineColor: preset.primary, lineOpacity: 0.05)

            // 3. Vignette + CRT glow
            VoiceCRTGlowOverlay(color: preset.primary, intensity: 0.06)

            // Content
            VStack(spacing: 0) {
                topBar
                Spacer()
                transcriptionDisplay
                Spacer()
                audioWaveform
                bottomControls
            }
            .padding()
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSettings) {
            VoiceSettingsSheet(preset: preset)
        }
        .sheet(isPresented: $showSessionPicker) {
            if let store = store {
                SessionPickerView(store: store)
            }
        }
        .onAppear {
            // Sync voice settings from UserDefaults (Settings > Voice)
            voiceConversation.syncVoiceSettings()
            voiceConversation.conversationMode = .remote
            startVoiceConversationIfNeeded()

            // Don't auto-pick a session. Use the active session from ChatView
            // (via the shared `store`). Auto-picking the most recent would
            // hijack whatever session the user is currently typing in.
            // If there's no active session, the first voice turn will create
            // one through store.sendMessage (which auto-creates when needed).
        }
        .onDisappear {
            voiceConversation.stopConversation()
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            // Top bar: ◉ VOICE_MODE (green, mono, subtle glitch animation) + ✕ close
            Text("◉ VOICE_MODE")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(preset.primary)
                .shadow(color: preset.primary.opacity(0.6), radius: 4)
                .modifier(GlitchAnimation())
            
            Spacer()
            
            Button { onClose?() } label: {
                Text("✕")
                    .font(.title2)
                    .foregroundStyle(preset.primary)
                    .padding(8)
                    .background(
                        Circle()
                            .fill(preset.background)
                            .stroke(preset.primary.opacity(0.4), lineWidth: 1)
                    )
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

                // Audio level bars inside the orb -- react to real mic input
                ZStack {
                    // Only show the visualizer when there's audio activity
                    if voiceConversation.isListening || voiceConversation.isSpeaking || voiceConversation.audioLevel > 0.01 {
                        // Audio level bars - 5 vertical bars that animate with audio level
                        ForEach(0..<5, id: \.self) { index in
                            Rectangle()
                                .fill(preset.primary)
                                .frame(width: 4, height: 20 + CGFloat(voiceConversation.audioLevel) * 30)
                                .offset(x: CGFloat(index - 2) * 8, y: 0)
                                .opacity(0.7 + Double(voiceConversation.audioLevel) * 0.3)
                        }
                    }
                }
                .frame(width: 80, height: 50)
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
        if voiceConversation.voiceError != nil { return "MIC NEEDS ATTENTION" }
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
            if let voiceError = voiceConversation.voiceError,
               !voiceError.isEmpty,
               !voiceConversation.isSpeaking,
               !voiceConversation.isThinking {
                cardView(label: "MIC", text: voiceError, color: preset.primary)
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
        // Controls: MUTE (toggle mic), center END (green, ends the voice session → back to Chat), LOCAL (toggle local/remote or device mode)
        HStack(spacing: 26) {
            // MUTE button
            VStack(spacing: 7) {
                Button {
                    // Toggle mute functionality
                } label: {
                    Text("􀊱")
                        .font(.title2)
                        .foregroundStyle(preset.primary)
                        .frame(width: 54, height: 54)
                        .background(
                            Circle()
                                .fill(preset.background)
                                .stroke(preset.primary.opacity(0.35), lineWidth: 1)
                        )
                }
                Text("MUTE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(preset.secondary.opacity(0.8))
            }
            
            // END button
            VStack(spacing: 7) {
                Button {
                    voiceConversation.stopConversation()
                    onClose?()
                } label: {
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [preset.primary, preset.secondary],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 41
                                )
                            )
                            .shadow(color: preset.primary.opacity(0.6), radius: 20)
                        Circle()
                            .fill(Color(red: 0.01, green: 0.13, blue: 0.04)) // #03210a
                            .frame(width: 26, height: 26)
                    }
                    .frame(width: 82, height: 82)
                }
                Text("END")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(preset.primary)
                    .shadow(color: preset.primary.opacity(0.6), radius: 3)
            }
            
            // LOCAL button
            VStack(spacing: 7) {
                Button {
                    // Toggle local/remote mode
                } label: {
                    Text("⇄")
                        .font(.title2)
                        .foregroundStyle(preset.primary)
                        .frame(width: 54, height: 54)
                        .background(
                            Circle()
                                .fill(preset.background)
                                .stroke(preset.primary.opacity(0.35), lineWidth: 1)
                        )
                }
                Text("LOCAL")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(preset.secondary.opacity(0.8))
            }
        }
        .padding(.bottom, 44)
    }

    private func startVoiceConversationIfNeeded() {
        guard !voiceConversation.isConversing else { return }
        // Set to premium mode if that's what the user has selected
        let preferredMode = voiceConversation.conversationMode
        voiceConversation.conversationMode = preferredMode
        voiceConversation.startConversation(
            onTranscription: { text in
                // Forward to ChatView so it sends through the active Hermes
                // session. Only fires in remote mode.
                onVoiceTranscription?(text)
            },
            onLocalResponse: { _ in }
        )
    }
    
    // MARK: - Transcription Display

    private var transcriptionDisplay: some View {
        VStack(spacing: 22) {
            // > YOU line (dim green) and > HERMES line (bright green with glow)
            if !voiceConversation.transcribedText.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("> YOU")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(preset.secondary)
                        .opacity(0.8)
                    Text(voiceConversation.transcribedText)
                        .font(.system(size: 16, design: .monospaced))
                        .foregroundStyle(preset.secondary.opacity(0.9))
                        .lineLimit(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            if !voiceConversation.spokenResponse.isEmpty || voiceConversation.isSpeaking {
                VStack(alignment: .leading, spacing: 6) {
                    Text("> HERMES")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(preset.primary)
                        .shadow(color: preset.primary.opacity(0.6), radius: 4)
                    Text(voiceConversation.spokenResponse + (voiceConversation.isSpeaking ? "█" : ""))
                        .font(.system(size: 17, design: .monospaced))
                        .foregroundStyle(preset.primary)
                        .shadow(color: preset.primary.opacity(0.55), radius: 6)
                        .lineLimit(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    
    // MARK: - Audio Waveform

    private var audioWaveform: some View {
        // Audio waveform: row of vertical bars animating with amplitude
        HStack(spacing: 4) {
            ForEach(0..<34, id: \.self) { index in
                waveformBar(index: index)
            }
        }
        .frame(height: 96)
        .padding(.horizontal, 30)
    }

    private func waveformBar(index: Int) -> some View {
        let barCount = 34
        let center = Double(barCount) / 2.0
        let dist = abs(Double(index) - center) / center
        let baseHeight = 8.0 + (1.0 - dist) * 20.0 // Vary height based on position
        
        return Rectangle()
            .fill(LinearGradient(
                colors: [preset.secondary, preset.primary],
                startPoint: .top,
                endPoint: .bottom
            ))
            .shadow(color: preset.primary.opacity(0.55), radius: 4)
            .frame(width: 5, height: CGFloat(baseHeight))
            .animation(.easeInOut(duration: 0.09), value: voiceConversation.audioLevel)
    }
}

// MARK: - Voice Settings Sheet

struct VoiceSettingsSheet: View {
    var preset: CyberpunkVoicePreset = .neon
    @AppStorage("voice_speed") private var speed: Double = 0.5
    @AppStorage("voice_pitch") private var pitch: Double = 1.0
    @AppStorage(VoiceDefaults.voiceIdentifierKey) private var selectedVoiceId: String = ""
    @AppStorage("premium_voice_service") private var premiumVoiceService: String = PremiumVoiceService.amazonPolly.rawValue
    @AppStorage("premium_voice_name") private var premiumVoiceName: String = "Joanna"
    @AppStorage("premium_voice_speed") private var premiumVoiceSpeed: Double = 1.0
    @AppStorage("premium_voice_pitch") private var premiumVoicePitch: Double = 1.0
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
                        premiumVoiceSection
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
            availableVoices = VoiceDefaults.sortedVoices()
                .filter { $0.quality == .enhanced || $0.quality == .premium }
            selectedVoiceId = VoiceDefaults.ensureBestVoiceSelected()
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
    
    private var premiumVoiceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PREMIUM VOICE")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(preset.secondary)
            
            Picker("Service", selection: $premiumVoiceService) {
                ForEach(PremiumVoiceService.allCases, id: \.rawValue) { service in
                    Text(service.displayName).tag(service.rawValue)
                }
            }
            .pickerStyle(.menu)
            .tint(preset.secondary)
            
            let currentService = PremiumVoiceService(rawValue: premiumVoiceService) ?? .amazonPolly
            Picker("Voice", selection: $premiumVoiceName) {
                ForEach(currentService.availableVoices, id: \.self) { voice in
                    Text(voice).tag(voice)
                }
            }
            .pickerStyle(.menu)
            .tint(preset.secondary)
            
            HStack {
                Text("Speed")
                Spacer()
                Text(String(format: "%.2f", premiumVoiceSpeed))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(preset.secondary)
            }
            Slider(value: $premiumVoiceSpeed, in: 0.25...2.0, step: 0.05)
                .tint(preset.secondary)
                
            HStack {
                Text("Pitch")
                Spacer()
                Text(String(format: "%.1f", premiumVoicePitch))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(preset.secondary)
            }
            Slider(value: $premiumVoicePitch, in: 0.5...2.0, step: 0.1)
                .tint(preset.secondary)
        }
        .padding(16)
        .background(preset.secondary.opacity(0.03))
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

// MARK: - Voice CRT Glow Overlay

struct VoiceCRTGlowOverlay: View {
    var color: Color = .white
    var intensity: Double = 0.06
    
    var body: some View {
        Canvas { context, size in
            // Vignette effect
            _ = RadialGradient(
                colors: [.clear, .black.opacity(0.7)],
                center: .center,
                startRadius: 0,
                endRadius: min(size.width, size.height) * 0.7
            )
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black.opacity(0.15)))
            
            // CRT glow effect
            _ = RadialGradient(
                colors: [color.opacity(intensity * 0.3), color.opacity(intensity * 0.1), .clear],
                center: .center,
                startRadius: 0,
                endRadius: min(size.width, size.height) * 0.8
            )
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(color.opacity(intensity)))
        }
        .allowsHitTesting(false)
        .blendMode(.screen)
    }
}

// MARK: - Glitch Animation Modifier

struct GlitchAnimation: ViewModifier {
    @State private var glitch = false
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(glitch ? 1.02 : 1.0)
            .offset(x: glitch ? 2 : 0)
            .animation(.easeInOut(duration: 0.1).repeatForever(autoreverses: true), value: glitch)
            .onAppear { 
                // Randomly trigger glitch effect
                DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: 2...8)) {
                    withAnimation {
                        glitch = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        glitch = false
                    }
                }
            }
    }
}

// MARK: - Matrix Digital Rain

struct MatrixRainView: View {
    let color: Color
    let secondaryColor: Color
    let intensity: Double  // 0.0 to 1.0, controls speed and brightness

    private let columns = 18
    private let charset: [Character] = Array("あいうえおかきくけこさしすせそたちつてとなにぬねのはひふへほまみむめもやゆよらりるれろわをんぁぃぅぇぉゃゅょっアイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワヲンｱｲｳｴｵｶｷｸｹｺ0123456789@#$%&*<>")

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.04)) { timeline in  // ~25fps, lighter than .animation
            Canvas { context, size in
                let columnWidth = size.width / CGFloat(columns)
                let t = timeline.date.timeIntervalSinceReferenceDate
                let speed = 50.0 + intensity * 150.0  // pixels per second
                let charSize: CGFloat = 14

                for col in 0..<columns {
                    let xPos = CGFloat(col) * columnWidth
                    let seed = Double(col) * 7.3
                    let offset = (t * speed * (0.5 + Double(intensity)) + seed * 100).truncatingRemainder(dividingBy: size.height + 200)
                    let trailLength = Int(6 + Int(intensity * 6))
                    let start = Int(offset / charSize)

                    for i in 0..<trailLength {
                        let y = CGFloat(start - i) * charSize
                        guard y >= -charSize && y <= size.height else { continue }

                        let charIdx = abs(Int((t * 3 + seed + Double(i) * 1.7))) % charset.count
                        let char = charset[charIdx]

                        let fade = 1.0 - Double(i) / Double(trailLength)
                        let brightness = fade * (0.3 + intensity * 0.7)

                        let opacity: Double
                        if i == 0 { opacity = brightness }
                        else if i < 3 { opacity = brightness }
                        else { opacity = brightness * 0.6 }

                        let charColor: Color
                        if i == 0 { charColor = Color.white.opacity(opacity) }
                        else { charColor = color.opacity(opacity) }

                        let pos = CGPoint(x: xPos + columnWidth / 2, y: y + charSize / 2)
                        let text = Text(String(char))
                            .font(.system(size: charSize, weight: .medium, design: .monospaced))
                            .foregroundColor(charColor)
                        context.draw(text, at: pos)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}