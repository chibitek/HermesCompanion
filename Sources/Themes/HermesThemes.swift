import SwiftUI

// MARK: - Theme Protocol

/// A theme defines the full visual identity of the app: colors, fonts,
/// backgrounds, bubble styles, corner radii, and whether to use glass effects.
///
/// Conform to this protocol to create a new theme. Register it in
/// ThemeRegistry.allThemes to make it selectable in Appearance settings.
protocol HermesTheme: Identifiable {
    /// Stable identifier stored in @AppStorage (e.g., "hermes", "matrix", "cyberpunk")
    var id: String { get }

    /// Human-readable name shown in the theme picker
    var displayName: String { get }

    /// Short description shown under the name
    var subtitle: String { get }

    /// Whether this theme uses iOS 26 Liquid Glass effects.
    /// When false, components fall back to flat/opaque backgrounds.
    var usesGlass: Bool { get }

    // MARK: Colors

    /// Primary accent color (send button, active states, user bubble tint)
    var accent: Color { get }

    /// Secondary accent (used for highlights, secondary buttons)
    var accentSecondary: Color { get }

    /// Danger / destructive actions
    var danger: Color { get }

    /// Warning / approval prompts
    var warning: Color { get }

    // MARK: Background

    /// Background view for the entire screen (gradient, solid color, overlay)
    var backgroundView: AnyView { get }

    // MARK: Bubbles

    /// Background color/style for user message bubbles
    var userBubbleBackground: Color { get }

    /// Background color/style for assistant message bubbles.
    /// Use .clear if the theme relies on glass or borders for assistant bubbles.
    var assistantBubbleBackground: Color { get }

    /// Border color for assistant bubbles (use .clear for no border)
    var assistantBubbleBorder: Color { get }

    /// Border width for assistant bubbles (0 = no border)
    var assistantBubbleBorderWidth: CGFloat { get }

    // MARK: Typography

    /// Font for user messages. Use .body for system default.
    var userMessageFont: Font { get }

    /// Font for assistant messages. Use .body for system, .system(.body, design: .monospaced) for terminal themes.
    var assistantMessageFont: Font { get }

    /// Font for UI chrome (labels, captions, tool chips, etc.)
    var uiFont: Font { get }

    // MARK: Geometry

    /// Corner radius for message bubbles
    var bubbleRadius: CGFloat { get }

    /// Corner radius for cards and input bar
    var cardRadius: CGFloat { get }

    /// Corner radius for buttons and small controls
    var controlRadius: CGFloat { get }

    /// Spacing scale multiplier (1.0 = default, 0.75 = dense)
    var spacingScale: CGFloat { get }

    // MARK: Streaming Cursor

    /// The character shown as a blinking cursor during streaming
    var cursorCharacter: String { get }

    /// Color of the streaming cursor
    var cursorColor: Color { get }

    // MARK: Tool Chip

    /// Whether tool chips use glass or flat style
    var toolChipsUseGlass: Bool { get }

    /// Background color for tool chips when not using glass
    var toolChipBackground: Color { get }

    /// Border color for tool chips
    var toolChipBorder: Color { get }

    // MARK: Helper Properties

    /// Scaled spacing values
    var spacingXS: CGFloat { get }
    var spacingS: CGFloat { get }
    var spacingM: CGFloat { get }
    var spacingL: CGFloat { get }
    var spacingXL: CGFloat { get }

    /// Radii
    var radiusS: CGFloat { get }
    var radiusM: CGFloat { get }
    var radiusL: CGFloat { get }
    var radiusXL: CGFloat { get }
}

// MARK: - Default Implementations

extension HermesTheme {
    // Default spacing scale (1.0 = standard)
    var spacingXS: CGFloat { 4 * spacingScale }
    var spacingS: CGFloat { 8 * spacingScale }
    var spacingM: CGFloat { 12 * spacingScale }
    var spacingL: CGFloat { 16 * spacingScale }
    var spacingXL: CGFloat { 24 * spacingScale }

    // Default radii
    var radiusS: CGFloat { 10 }
    var radiusM: CGFloat { 16 }
    var radiusL: CGFloat { 22 }
    var radiusXL: CGFloat { 28 }

    // Default cursor
    var cursorCharacter: String { "▋" }
    var cursorColor: Color { .secondary }

    // Default tool chip
    var toolChipsUseGlass: Bool { usesGlass }
    var toolChipBackground: Color { Color(.tertiarySystemFill) }
    var toolChipBorder: Color { .clear }

    // Default fonts
    var uiFont: Font { .body }

    // Default borders
    var assistantBubbleBorder: Color { .clear }
    var assistantBubbleBorderWidth: CGFloat { 0 }
}

// MARK: - Theme Registry

/// Manages available themes and the active theme selection.
/// The active theme ID is persisted in @AppStorage("activeThemeId").
enum ThemeRegistry {
    /// All registered themes, in the order they appear in the picker.
    static let allThemes: [any HermesTheme] = [
        HermesDefaultTheme(),
        MatrixTheme(),
        RetroAmberTheme(),
        NeonTheme(),
        BlueHackerTheme(),
        CyberpunkTheme(),
    ]

    /// Default theme ID when none is saved
    static let defaultThemeId = "hermes"

    /// Look up a theme by ID. Falls back to the default theme.
    static func theme(for id: String) -> any HermesTheme {
        allThemes.first { $0.id == id } ?? allThemes.first { $0.id == defaultThemeId }!
    }

    /// The currently active theme, resolved from the stored ID.
    /// Use this in views via @AppStorage("activeThemeId") + theme(for:).
    static func activeTheme(id: String) -> any HermesTheme {
        theme(for: id)
    }
}

// MARK: - Hermes (Default Liquid Glass Theme)

/// The default theme. Matches the original GlassTheme statics exactly.
/// This is the safe fallback that always works.
struct HermesDefaultTheme: HermesTheme {
    let id = "hermes"
    let displayName = "Hermes"
    let subtitle = "Liquid Glass, frosted and translucent"
    let usesGlass = true

    let accent = Color(red: 0.176, green: 0.831, blue: 0.749)  // #2DD4BF teal
    let accentSecondary = Color(red: 0.0, green: 0.702, blue: 0.596)  // #00B398
    let danger = Color(red: 0.811, green: 0.271, blue: 0.125)  // #CF4520
    let warning = Color(red: 0.961, green: 0.620, blue: 0.043)  // #F59E0B

    var backgroundView: AnyView {
        AnyView(
            LinearGradient(
                colors: [
                    Color(.systemBackground),
                    Color(.systemBackground).opacity(0.95),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    let userBubbleBackground = Color(red: 0.176, green: 0.831, blue: 0.749)  // accent at 0.25 opacity applied by components
    let assistantBubbleBackground: Color = .clear  // glass effect provides the visual
    let userMessageFont: Font = .body
    let assistantMessageFont: Font = .body

    let bubbleRadius: CGFloat = 22
    let cardRadius: CGFloat = 28
    let controlRadius: CGFloat = 10
    let spacingScale: CGFloat = 1.0
}

// MARK: - Matrix Terminal Theme

/// Pure black background, matrix green text, monospaced fonts, flat opaque
/// bubbles, sharp corners, maximum information density. The "terminal on
/// your phone" theme.
struct MatrixTheme: HermesTheme {
    let id = "matrix"
    let displayName = "Matrix"
    let subtitle = "Terminal green on black, monospaced, dense"
    let usesGlass = false

    let accent = Color(red: 0.0, green: 1.0, blue: 0.254)  // #00FF41 matrix green
    let accentSecondary = Color(red: 0.0, green: 0.561, blue: 0.067)  // #008F11 dim green
    let danger = Color(red: 1.0, green: 0.271, blue: 0.0)  // #FF4520 orange-red
    let warning = Color(red: 1.0, green: 0.804, blue: 0.0)  // #FFCC00

    var backgroundView: AnyView {
        AnyView(
            ZStack {
                Color.black
                CRTGlowOverlay(color: accent, intensity: 0.04)
                CRTScanlineOverlay(opacity: 0.10)
            }
        )
    }

    let userBubbleBackground = Color(red: 0.0, green: 1.0, blue: 0.254).opacity(0.12)  // dim green tint
    let assistantBubbleBackground: Color = .clear  // uses left border instead

    let assistantBubbleBorder: Color = Color(red: 0.0, green: 1.0, blue: 0.254).opacity(0.5)
    let assistantBubbleBorderWidth: CGFloat = 1.5

    let userMessageFont: Font = .system(.body, design: .monospaced)
    let assistantMessageFont: Font = .system(.body, design: .monospaced)

    let bubbleRadius: CGFloat = 4
    let cardRadius: CGFloat = 6
    let controlRadius: CGFloat = 4
    let spacingScale: CGFloat = 0.75

    let cursorCharacter: String = "█"
    let cursorColor: Color = Color(red: 0.0, green: 1.0, blue: 0.254)

    let toolChipsUseGlass: Bool = false
    let toolChipBackground: Color = Color.black
    let toolChipBorder: Color = Color(red: 0.0, green: 1.0, blue: 0.254).opacity(0.3)

    // Override radii for sharper look
    var radiusS: CGFloat { 4 }
    var radiusM: CGFloat { 6 }
    var radiusL: CGFloat { 6 }
    var radiusXL: CGFloat { 8 }
}

// MARK: - Cyberpunk Theme

/// Dark base with neon accent gradients. Cyan primary, magenta secondary.
/// Glass effect with neon tint on bubbles. Sharper corners, monospaced
/// assistant text. Inspired by Hermes Agent's cyberpunk aesthetic.
struct CyberpunkTheme: HermesTheme {
    let id = "cyberpunk"
    let displayName = "Cyberpunk"
    let subtitle = "Neon cyan and magenta, dark glass"
    let usesGlass = true

    let accent = Color(red: 0.0, green: 0.941, blue: 1.0)  // #00F0FF cyan
    let accentSecondary = Color(red: 1.0, green: 0.0, blue: 0.898)  // #FF00E5 magenta
    let danger = Color(red: 1.0, green: 0.298, blue: 0.298)  // #FF4C4C red
    let warning = Color(red: 1.0, green: 0.722, blue: 0.0)  // #FFB800

    var backgroundView: AnyView {
        AnyView(
            LinearGradient(
                colors: [
                    Color(red: 0.031, green: 0.031, blue: 0.059),  // #08080F near-black
                    Color(red: 0.051, green: 0.039, blue: 0.09),   // #0D0A17 slightly purple
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    let userBubbleBackground = Color(red: 0.0, green: 0.941, blue: 1.0).opacity(0.15)  // cyan tint
    let assistantBubbleBackground: Color = .clear  // glass with neon tint

    let userMessageFont: Font = .body
    let assistantMessageFont: Font = .system(.body, design: .monospaced)

    let bubbleRadius: CGFloat = 10
    let cardRadius: CGFloat = 14
    let controlRadius: CGFloat = 8
    let spacingScale: CGFloat = 0.85

    let cursorCharacter: String = "▋"
    let cursorColor: Color = Color(red: 0.0, green: 0.941, blue: 1.0)

    let toolChipsUseGlass: Bool = true
    let toolChipBackground: Color = Color(red: 0.0, green: 0.941, blue: 1.0).opacity(0.08)
    let toolChipBorder: Color = .clear  // glass provides the visual

    // Slightly sharper radii
    var radiusS: CGFloat { 8 }
    var radiusM: CGFloat { 12 }
    var radiusL: CGFloat { 14 }
    var radiusXL: CGFloat { 18 }
}