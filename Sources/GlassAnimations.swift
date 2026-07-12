import SwiftUI

// MARK: - Pulsing Animation Modifier

struct PulsingAnimation: ViewModifier {
    @State private var pulsing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(pulsing ? 1.3 : 0.8)
            .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: pulsing)
            .onAppear { pulsing = true }
    }
}

// MARK: - Speaking Bar Animation (for live conversation TTS)

struct SpeakingBarAnimation: ViewModifier {
    let delay: Double
    @State private var animating = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(y: animating ? 1.0 : 0.3)
            .animation(
                .easeInOut(duration: 0.3)
                    .repeatForever(autoreverses: true)
                    .delay(delay),
                value: animating
            )
            .onAppear { animating = true }
    }
}
