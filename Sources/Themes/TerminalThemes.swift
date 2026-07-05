import SwiftUI

// MARK: - CRT / Scanline Effects

/// Reusable CRT scanline overlay for terminal themes.
struct CRTScanlineOverlay: View {
    var opacity: Double = 0.15

    var body: some View {
        Canvas { context, size in
            let lineSpacing: CGFloat = 3
            var y: CGFloat = 0
            while y < size.height {
                context.fill(
                    Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                    with: .color(.black.opacity(opacity))
                )
                y += lineSpacing
            }
        }
        .allowsHitTesting(false)
    }
}

/// CRT screen glow / vignette effect
struct CRTGlowOverlay: View {
    var color: Color
    var intensity: Double = 0.08

    var body: some View {
        RadialGradient(
            colors: [color.opacity(intensity), .clear],
            center: .center,
            startRadius: 0,
            endRadius: 400
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// Subtle screen flicker animation
struct ScreenFlicker: ViewModifier {
    @State private var flicker = false
    var intensity: Double = 0.03

    func body(content: Content) -> some View {
        content
            .opacity(flicker ? 1.0 - intensity : 1.0)
            .animation(
                .easeInOut(duration: 0.15).repeatForever(autoreverses: true),
                value: flicker
            )
            .onAppear { flicker = true }
    }
}

/// Glitch text effect for headers
struct GlitchText: View {
    let text: String
    var color: Color = .green
    @State private var glitchOffset: CGFloat = 0
    @State private var showGlitch = false

    var body: some View {
        Text(text)
            .foregroundStyle(color)
            .shadow(color: Color.red.opacity(0.7), radius: 0, x: showGlitch ? -1 : 0, y: 0)
            .shadow(color: Color.blue.opacity(0.7), radius: 0, x: showGlitch ? 1 : 0, y: 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                    showGlitch.toggle()
                }
            }
    }
}

// MARK: - Theme Extensions for CRT

extension View {
    /// Apply CRT scanlines and glow for terminal themes
    func crtEffect(color: Color, scanlineOpacity: Double = 0.12) -> some View {
        self.overlay {
            ZStack {
                CRTGlowOverlay(color: color, intensity: 0.06)
                CRTScanlineOverlay(opacity: scanlineOpacity)
            }
        }
    }
}

// MARK: - Retro Amber Terminal Theme

struct RetroAmberTheme: HermesTheme {
    let id = "retro-amber"
    let displayName = "Retro Amber"
    let subtitle = "CRT amber phosphor, scanlines, glow"
    let usesGlass = false

    let accent = Color(red: 1.0, green: 0.647, blue: 0.0)  // #FFA500 amber
    let accentSecondary = Color(red: 0.804, green: 0.522, blue: 0.0)  // #CD8600 dim amber
    let danger = Color(red: 1.0, green: 0.298, blue: 0.0)  // #FF4C00
    let warning = Color(red: 1.0, green: 0.843, blue: 0.0)  // #FFD700

    var backgroundView: AnyView {
        AnyView(
            ZStack {
                Color(red: 0.059, green: 0.039, blue: 0.0)  // #0F0A00 near-black amber
                CRTGlowOverlay(color: accent, intensity: 0.05)
                CRTScanlineOverlay(opacity: 0.10)
            }
        )
    }

    let userBubbleBackground = Color(red: 1.0, green: 0.647, blue: 0.0).opacity(0.12)
    let assistantBubbleBackground: Color = .clear

    let assistantBubbleBorder: Color = Color(red: 1.0, green: 0.647, blue: 0.0).opacity(0.4)
    let assistantBubbleBorderWidth: CGFloat = 1.5

    let userMessageFont: Font = .system(.body, design: .monospaced)
    let assistantMessageFont: Font = .system(.body, design: .monospaced)

    let bubbleRadius: CGFloat = 3
    let cardRadius: CGFloat = 5
    let controlRadius: CGFloat = 3
    let spacingScale: CGFloat = 0.75

    let cursorCharacter: String = "█"
    let cursorColor: Color = Color(red: 1.0, green: 0.647, blue: 0.0)

    let toolChipsUseGlass: Bool = false
    let toolChipBackground: Color = Color(red: 0.059, green: 0.039, blue: 0.0)
    let toolChipBorder: Color = Color(red: 1.0, green: 0.647, blue: 0.0).opacity(0.3)

    var radiusS: CGFloat { 3 }
    var radiusM: CGFloat { 5 }
    var radiusL: CGFloat { 5 }
    var radiusXL: CGFloat { 6 }
}

// MARK: - Neon Terminal Theme

struct NeonTheme: HermesTheme {
    let id = "neon"
    let displayName = "Neon"
    let subtitle = "Electric neon, magenta+cyan glow, scanlines"
    let usesGlass = false

    let accent = Color(red: 1.0, green: 0.0, blue: 0.898)  // #FF00E5 magenta
    let accentSecondary = Color(red: 0.0, green: 0.941, blue: 1.0)  // #00F0FF cyan
    let danger = Color(red: 1.0, green: 0.078, blue: 0.235)  // #FF143C
    let warning = Color(red: 1.0, green: 0.722, blue: 0.0)  // #FFB800

    var backgroundView: AnyView {
        AnyView(
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.02, green: 0.0, blue: 0.05),
                        Color(red: 0.04, green: 0.0, blue: 0.08),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                CRTGlowOverlay(color: accent, intensity: 0.04)
                CRTScanlineOverlay(opacity: 0.08)
            }
        )
    }

    let userBubbleBackground = Color(red: 1.0, green: 0.0, blue: 0.898).opacity(0.10)
    let assistantBubbleBackground: Color = .clear

    let assistantBubbleBorder: Color = Color(red: 0.0, green: 0.941, blue: 1.0).opacity(0.35)
    let assistantBubbleBorderWidth: CGFloat = 1.0

    let userMessageFont: Font = .system(.body, design: .monospaced)
    let assistantMessageFont: Font = .system(.body, design: .monospaced)

    let bubbleRadius: CGFloat = 6
    let cardRadius: CGFloat = 8
    let controlRadius: CGFloat = 5
    let spacingScale: CGFloat = 0.8

    let cursorCharacter: String = "▋"
    let cursorColor: Color = Color(red: 1.0, green: 0.0, blue: 0.898)

    let toolChipsUseGlass: Bool = false
    let toolChipBackground: Color = Color(red: 0.02, green: 0.0, blue: 0.05)
    let toolChipBorder: Color = Color(red: 1.0, green: 0.0, blue: 0.898).opacity(0.25)

    var radiusS: CGFloat { 5 }
    var radiusM: CGFloat { 8 }
    var radiusL: CGFloat { 8 }
    var radiusXL: CGFloat { 10 }
}

// MARK: - Blue Hacker Terminal Theme

struct BlueHackerTheme: HermesTheme {
    let id = "blue-hacker"
    let displayName = "Blue Hacker"
    let subtitle = "ICE blue terminal, phosphor glow, scanlines"
    let usesGlass = false

    let accent = Color(red: 0.0, green: 0.741, blue: 1.0)  // #00BDFF ice blue
    let accentSecondary = Color(red: 0.0, green: 0.467, blue: 0.741)  // #0077BC dim blue
    let danger = Color(red: 1.0, green: 0.231, blue: 0.188)  // #FF3B30
    let warning = Color(red: 1.0, green: 0.706, blue: 0.353)  // #FFB45A

    var backgroundView: AnyView {
        AnyView(
            ZStack {
                Color(red: 0.0, green: 0.02, blue: 0.05)  // #00050D near-black blue
                CRTGlowOverlay(color: accent, intensity: 0.05)
                CRTScanlineOverlay(opacity: 0.10)
            }
        )
    }

    let userBubbleBackground = Color(red: 0.0, green: 0.741, blue: 1.0).opacity(0.10)
    let assistantBubbleBackground: Color = .clear

    let assistantBubbleBorder: Color = Color(red: 0.0, green: 0.741, blue: 1.0).opacity(0.4)
    let assistantBubbleBorderWidth: CGFloat = 1.5

    let userMessageFont: Font = .system(.body, design: .monospaced)
    let assistantMessageFont: Font = .system(.body, design: .monospaced)

    let bubbleRadius: CGFloat = 3
    let cardRadius: CGFloat = 5
    let controlRadius: CGFloat = 3
    let spacingScale: CGFloat = 0.75

    let cursorCharacter: String = "█"
    let cursorColor: Color = Color(red: 0.0, green: 0.741, blue: 1.0)

    let toolChipsUseGlass: Bool = false
    let toolChipBackground: Color = Color(red: 0.0, green: 0.02, blue: 0.05)
    let toolChipBorder: Color = Color(red: 0.0, green: 0.741, blue: 1.0).opacity(0.3)

    var radiusS: CGFloat { 3 }
    var radiusM: CGFloat { 5 }
    var radiusL: CGFloat { 5 }
    var radiusXL: CGFloat { 6 }
}
