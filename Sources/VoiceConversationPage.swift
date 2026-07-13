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
    var onVoiceTranscription: ((String) -> Void)? = nil
    var onClose: (() -> Void)? = nil

    @State private var preset: CyberpunkVoicePreset = .matrix
    @State private var showSettings = false

    // Rain intensity changes with conversation state
    private var rainIntensity: Double {
        if voiceConversation.isListening { return 1.0 }      // Fast rain
        if voiceConversation.isSpeaking { return 0.7 }       // Medium, glowing
        if voiceConversation.isThinking { return 0.5 }       // Steady rain — keep the visual alive
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
                visualizer
                Spacer()
                transcriptionDisplay
                bottomControls
            }
            .padding()
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSettings) {
            VoiceSettingsSheet(preset: preset)
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            // Sync voice settings from UserDefaults (Settings > Voice)
            voiceConversation.syncVoiceSettings()
            voiceConversation.conversationMode = .remote
            store?.isVoiceConversationActive = true
            startVoiceConversationIfNeeded()

            // Don't auto-pick a session. Use the active session from ChatView
            // (via the shared `store`). Auto-picking the most recent would
            // hijack whatever session the user is currently typing in.
            // If there's no active session, the first voice turn will create
            // one through store.sendMessage (which auto-creates when needed).
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            store?.isVoiceConversationActive = false
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
                AudioVisualizerBar(
                    color: preset.primary,
                    secondaryColor: preset.secondary,
                    audioLevel: Double(voiceConversation.audioLevel),
                    isActive: voiceConversation.isListening || voiceConversation.isSpeaking
                )
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

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        // Controls: center END (green, ends the voice session -> back to Chat)
        HStack(spacing: 26) {
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
                .accessibilityLabel("End conversation")
                Text("END")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(preset.primary)
                    .shadow(color: preset.primary.opacity(0.6), radius: 3)
            }
        }
        .padding(.bottom, 44)
    }

    private func startVoiceConversationIfNeeded() {
        guard !voiceConversation.isConversing else {
            FileLogger.shared.log("VoicePage: already conversing, not restarting")
            return
        }
        FileLogger.shared.log("VoicePage: starting conversation, mode=\(voiceConversation.conversationMode)")
        voiceConversation.conversationMode = .remote
        voiceConversation.startConversation(
            onTranscription: { text in
                FileLogger.shared.log("VoicePage: transcription callback fired with text: \(text)")
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
}

// MARK: - Audio Visualizer Bar (center wave)

struct AudioVisualizerBar: View {
    let color: Color
    let secondaryColor: Color
    let audioLevel: Double
    let isActive: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(0..<5, id: \.self) { index in
                let centerIndex = 2
                let dist = abs(Double(index - centerIndex)) / 2.0
                let minH: CGFloat = isActive ? 8 : 3
                let maxH: CGFloat = 44
                let height = minH + CGFloat(audioLevel * (1.0 - dist * 0.5) * Double(maxH - minH))
                let animatedHeight = isActive ? height * (0.85 + CGFloat.random(in: 0...0.3)) : height

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [secondaryColor, color],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(width: 5, height: animatedHeight)
                    .shadow(color: color.opacity(0.55), radius: 4)
                    .animation(.easeInOut(duration: 0.12).repeatForever(autoreverses: true), value: isActive)
            }
        }
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
@Environment(\.activeTheme) private var theme
@Environment(\.dismiss) private var dismiss

var body: some View {
    NavigationStack {
        ZStack {
            theme.backgroundView.ignoresSafeArea()
            ScrollView {
                VStack(spacing: theme.spacingM) {
                    speedSection
                    pitchSection
                    voiceSection
                    premiumVoiceSection
                }
                .padding(theme.spacingM)
            }
        }
        .navigationTitle("Voice Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
                    .foregroundStyle(theme.accent)
            }
        }
    }
    .onAppear {
        availableVoices = VoiceDefaults.sortedVoices()
            .filter { $0.quality == .enhanced || $0.quality == .premium }
        selectedVoiceId = VoiceDefaults.ensureBestVoiceSelected()
    }
}
    
private var cardBackground: some View {
    AnyView(theme.glassCard(cornerRadius: 12))
}
    
private var speedSection: some View {
    VStack(alignment: .leading, spacing: theme.spacingS) {
        Text("SPEED")
            .font(.system(size: 12, weight: .bold, design: .monospaced))
            .foregroundStyle(theme.accent)
        HStack {
            Slider(value: $speed, in: 0.1...1.0, step: 0.05)
                .tint(theme.accent)
            Text(String(format: "%.2f", speed))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(theme.textBody)
                .frame(width: 40)
        }
    }
    .padding(theme.spacingM)
    .background(cardBackground)
}

private var pitchSection: some View {
    VStack(alignment: .leading, spacing: theme.spacingS) {
        Text("PITCH")
            .font(.system(size: 12, weight: .bold, design: .monospaced))
            .foregroundStyle(theme.accentSecondary)
        HStack {
            Slider(value: $pitch, in: 0.5...2.0, step: 0.1)
                .tint(theme.accentSecondary)
            Text(String(format: "%.1f", pitch))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(theme.textBody)
                .frame(width: 40)
        }
    }
    .padding(theme.spacingM)
    .background(cardBackground)
}

private var voiceSection: some View {
    VStack(alignment: .leading, spacing: theme.spacingS) {
        Text("VOICE")
            .font(.system(size: 12, weight: .bold, design: .monospaced))
            .foregroundStyle(theme.accent)
        ForEach(availableVoices, id: \.identifier) { voice in
            voiceRow(voice)
        }
    }
    .padding(theme.spacingM)
    .background(cardBackground)
}
    
private var premiumVoiceSection: some View {
    VStack(alignment: .leading, spacing: theme.spacingS) {
        Text("PREMIUM VOICE")
            .font(.system(size: 12, weight: .bold, design: .monospaced))
            .foregroundStyle(theme.accentSecondary)
            
        let currentService = PremiumVoiceService(rawValue: premiumVoiceService) ?? .amazonPolly
            
        rowLabel("Service") {
            Picker("Service", selection: $premiumVoiceService) {
                ForEach(PremiumVoiceService.allCases, id: \.rawValue) { service in
                    Text(service.displayName).tag(service.rawValue)
                }
            }
            .pickerStyle(.menu)
            .tint(theme.accent)
        }
            
        rowLabel("Voice") {
            Picker("Voice", selection: $premiumVoiceName) {
                ForEach(currentService.availableVoices, id: \.self) { voice in
                    Text(voice).tag(voice)
                }
            }
            .pickerStyle(.menu)
            .tint(theme.accent)
        }
            
        sliderRow("Speed", value: $premiumVoiceSpeed, range: 0.25...2.0, step: 0.05)
        sliderRow("Pitch", value: $premiumVoicePitch, range: 0.5...2.0, step: 0.1)
    }
    .padding(theme.spacingM)
    .background(cardBackground)
}
    
private func sliderRow(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double) -> some View {
    VStack(alignment: .leading, spacing: theme.spacingXS) {
        HStack {
            Text(label)
                .foregroundStyle(theme.textBody)
            Spacer()
            Text(String(format: step < 0.1 ? "%.2f" : "%.1f", value.wrappedValue))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(theme.textSecondary)
        }
        Slider(value: value, in: range, step: step)
            .tint(theme.accent)
    }
}
    
private func rowLabel<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
    HStack {
        Text(label)
            .foregroundStyle(theme.textBody)
        Spacer()
        content()
    }
}

private func voiceRow(_ voice: AVSpeechSynthesisVoice) -> some View {
    let isSelected = voice.identifier == selectedVoiceId
    return Button {
        selectedVoiceId = voice.identifier
    } label: {
        HStack {
            Text(voice.name)
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(isSelected ? theme.accent : theme.textBody)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(theme.accent)
            }
        }
        .padding(.horizontal, theme.spacingS)
        .padding(.vertical, theme.spacingXS)
        .background(isSelected ? theme.accent.opacity(0.12) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
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

    private let columns = 24
    private let charset: [Character] = Array("あいうえおかきくけこさしすせそたちつてとなにぬねのはひふへほまみむめもやゆよらりるれろわをんアイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワヲン0123456789@#$%&*<>ABCDEF+=-/")

    // Precompute resolved colors to avoid per-frame Color.opacity() calls
    private var leadColor: Color { Color.white.opacity(min(0.9 * intensity + 0.3, 1.0)) }
    private var brightColor: Color { color.opacity(min(0.85 * intensity + 0.2, 1.0)) }
    private var midColor: Color { color.opacity(0.6 * intensity + 0.1) }
    private var dimColor: Color { color.opacity(0.35 * intensity + 0.05) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.04)) { timeline in  // 25fps — sustainable
            Canvas { context, size in
                let columnWidth = size.width / CGFloat(columns)
                let t = timeline.date.timeIntervalSinceReferenceDate
                let speed = 60.0 + intensity * 120.0
                let charSize: CGFloat = 14

                for col in 0..<columns {
                    let xPos = CGFloat(col) * columnWidth
                    let seed = Double(col) * 7.3
                    let colSpeed = speed * (0.7 + abs(sin(seed)) * 0.6)
                    let offset = (t * colSpeed * (0.5 + Double(intensity)) + seed * 100).truncatingRemainder(dividingBy: size.height + 200)
                    let trailLength = 10
                    let start = Int(offset / charSize)

                    var i = 0
                    while i < trailLength {
                        let y = CGFloat(start - i) * charSize
                        guard y >= -charSize && y <= size.height else { i += 1; continue }

                        let charIdx = abs(Int((t * 3 + seed + Double(i) * 1.7))) % charset.count
                        let char = charset[charIdx]
                        let pos = CGPoint(x: xPos + columnWidth / 2, y: y + charSize / 2)

                        // Pick precomputed color — no per-frame opacity math
                        let drawColor: Color
                        if i == 0 { drawColor = leadColor }
                        else if i < 2 { drawColor = brightColor }
                        else if i < 5 { drawColor = midColor }
                        else { drawColor = dimColor }

                        context.draw(Text(String(char))
                            .font(.system(size: charSize, weight: .medium, design: .monospaced))
                            .foregroundColor(drawColor), at: pos)
                        
                        i += 1
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}