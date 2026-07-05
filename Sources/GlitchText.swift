import SwiftUI

// MARK: - Glitch Text

/// Text view with a monospaced font that randomly substitutes characters
/// for 1-2 frames every second, producing a cyberpunk glitch effect.
///
/// The original text is always readable most of the time; substitutions
/// are brief and visually striking.
struct GlitchText: View {
    let text: String
    var font: Font = .system(size: 24, weight: .bold, design: .monospaced)
    var color: Color = .green
    var glitchIntensity: Int = 2  // number of characters to glitch at once

    @State private var displayText: String
    @State private var glitchTimer: Timer?
    @State private var isGlitching = false

    private static let glitchChars = Array("!@#$%^&*()_+-=[]{}|;:,.<>?/~`░▒▓█▀▄║╔╗╚╝▲▼◄►")

    init(text: String, font: Font = .system(size: 24, weight: .bold, design: .monospaced),
         color: Color = .green, glitchIntensity: Int = 2) {
        self.text = text
        self.font = font
        self.color = color
        self.glitchIntensity = glitchIntensity
        self._displayText = State(initialValue: text)
    }

    var body: some View {
        Text(displayText)
            .font(font)
            .foregroundStyle(color)
            .crtGlow(color, radius: 8, opacity: 0.7)
            .onAppear { startGlitching() }
            .onDisappear { glitchTimer?.invalidate() }
            .onChange(of: text) { _, newValue in
                displayText = newValue
            }
    }

    private func startGlitching() {
        glitchTimer?.invalidate()
        glitchTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in
            // Only glitch roughly once per second cycle, for ~2 frames
            if isGlitching {
                // Restore
                displayText = text
                isGlitching = false
                return
            }

            // ~12% chance to start a glitch frame
            if Int.random(in: 0...100) < 12 {
                triggerGlitch()
            }
        }
    }

    private func triggerGlitch() {
        isGlitching = true
        var chars = Array(text)
        guard chars.count > 0 else { return }
        let count = min(glitchIntensity, chars.count)
        for _ in 0..<count {
            let idx = Int.random(in: 0..<chars.count)
            // Don't glitch spaces
            if chars[idx] != " " {
                chars[idx] = Self.glitchChars.randomElement() ?? chars[idx]
            }
        }
        displayText = String(chars)
    }
}
