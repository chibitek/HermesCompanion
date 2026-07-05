import SwiftUI

// MARK: - Cyberpunk Voice Preset

/// Four terminal-inspired color presets for the cyberpunk voice page.
/// Cycled by tapping the preset pill in the top bar.
struct CyberpunkVoicePreset: Identifiable, CaseIterable, Equatable {
    let id: String
    let name: String
    let primary: Color
    let secondary: Color
    let background: Color

    /// Glow color for text shadows and borders
    var glowColor: Color { primary }

    static let matrix = CyberpunkVoicePreset(
        id: "matrix",
        name: "MATRIX",
        primary: Color(red: 0.0, green: 1.0, blue: 0.254),   // #00FF41
        secondary: Color(red: 0.0, green: 0.561, blue: 0.067), // #008F11
        background: Color.black
    )

    static let retroAmber = CyberpunkVoicePreset(
        id: "retro_amber",
        name: "AMBER",
        primary: Color(red: 1.0, green: 0.690, blue: 0.0),   // #FFB000
        secondary: Color(red: 0.804, green: 0.522, blue: 0.0),
        background: Color.black
    )

    static let neon = CyberpunkVoicePreset(
        id: "neon",
        name: "NEON",
        primary: Color(red: 0.0, green: 0.941, blue: 1.0),   // #00F0FF cyan
        secondary: Color(red: 1.0, green: 0.0, blue: 1.0),     // #FF00FF magenta
        background: Color.black
    )

    static let blueHacker = CyberpunkVoicePreset(
        id: "blue_hacker",
        name: "BLUE",
        primary: Color(red: 0.0, green: 0.502, blue: 1.0),   // #0080FF
        secondary: Color(red: 0.0, green: 0.294, blue: 0.6),
        background: Color.black
    )

    static var allCases: [CyberpunkVoicePreset] {
        [.matrix, .retroAmber, .neon, .blueHacker]
    }

    /// Cycle to the next preset
    var next: CyberpunkVoicePreset {
        let all = CyberpunkVoicePreset.allCases
        guard let idx = all.firstIndex(of: self) else { return .matrix }
        return all[(idx + 1) % all.count]
    }
}

// MARK: - Scanline Overlay

/// Reusable scan-line overlay: alternating semi-transparent horizontal lines
/// that cover the entire screen to produce a CRT-monitor effect.
struct ScanlineOverlay: View {
    var lineSpacing: CGFloat = 3
    var lineOpacity: Double = 0.07
    var lineColor: Color = .white

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

/// Applies a multi-layer shadow glow effect in the preset color.
/// Used on all text and borders throughout the cyberpunk voice page.
struct CRTGlow: ViewModifier {
    let color: Color
    var radius: CGFloat = 6
    var opacity: Double = 0.8

    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(opacity), radius: radius)
            .shadow(color: color.opacity(opacity * 0.5), radius: radius * 2)
    }
}

extension View {
    func crtGlow(_ color: Color, radius: CGFloat = 6, opacity: Double = 0.8) -> some View {
        modifier(CRTGlow(color: color, radius: radius, opacity: opacity))
    }
}

// MARK: - Subtle Grid Background

/// Very low-opacity grid pattern for the background.
struct GridPattern: View {
    var color: Color = .gray
    var spacing: CGFloat = 40
    var opacity: Double = 0.04

    var body: some View {
        Canvas { context, size in
            // Vertical lines
            var x: CGFloat = 0
            while x < size.width {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(color.opacity(opacity)), lineWidth: 0.5)
                x += spacing
            }
            // Horizontal lines
            var y: CGFloat = 0
            while y < size.height {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(color.opacity(opacity)), lineWidth: 0.5)
                y += spacing
            }
        }
        .allowsHitTesting(false)
    }
}
