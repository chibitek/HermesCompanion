import SwiftUI

/// User appearance preferences — stored in UserDefaults via @AppStorage.
/// These are purely client-side, no server interaction needed.
final class AppearanceSettings: ObservableObject {
    // Theme
    @AppStorage("activeThemeId") var activeThemeId: String = ThemeRegistry.defaultThemeId

    // Color scheme
    @AppStorage("colorScheme") var colorScheme: String = "system"  // system, dark, light

    // Accent color
    @AppStorage("accentColor") var accentColor: String = "teal"  // teal, blue, purple, green, orange, red

    // Font size multiplier (0.7 = smallest, 1.0 = normal)
    @AppStorage("fontScale") var fontScale: Double = 0.7

    // Message font size (explicit override, 0 = use system Dynamic Type)
    @AppStorage("messageFontSize") var messageFontSize: Double = 11  // 0 = auto, 10-18 = explicit

    // Bubble density (compact vs spacious)
    @AppStorage("compactMode") var compactMode: Bool = false

    // Show timestamps on messages
    @AppStorage("showTimestamps") var showTimestamps: Bool = false

    // MARK: - Plain accessors (for passing to child views without Binding issues)

    var showTimestampsBool: Bool { showTimestamps }
    var compactModeBool: Bool { compactMode }
    var fontScaleDouble: Double { fontScale }
    var messageFontSizeDouble: Double { messageFontSize }

    init() {
        let defaults = UserDefaults.standard
        let migrationKey = "appearanceTypographyDefaults_v3"
        guard !defaults.bool(forKey: migrationKey) else { return }

        fontScale = 0.7
        messageFontSize = 11.0
        defaults.set(0.7, forKey: "fontScale")
        defaults.set(11.0, forKey: "messageFontSize")
        defaults.set(true, forKey: migrationKey)
    }

    // MARK: - Theme

    /// The resolved active theme. Re-read this whenever activeThemeId changes.
    var activeTheme: any HermesTheme {
        ThemeRegistry.theme(for: activeThemeId)
    }

    // MARK: - Computed (legacy compat — delegates to active theme)

    var preferredColorScheme: ColorScheme? {
        switch colorScheme {
        case "dark": return .dark
        case "light": return .light
        default: return nil  // system
        }
    }

    /// Accent color from the active theme, unless the user has a custom accent
    /// override that differs from the theme default.
    var accent: Color {
        // For themes with locked accents (matrix = green only), use the theme accent.
        // For the default Hermes theme, respect the user's accent color picker.
        if activeThemeId == "hermes" {
            return customAccentColor
        }
        return activeTheme.accent
    }

    private var customAccentColor: Color {
        switch accentColor {
        case "blue": return .blue
        case "purple": return .purple
        case "green": return .green
        case "orange": return Color(red: 0.96, green: 0.62, blue: 0.04)
        case "red": return Color(red: 0.81, green: 0.27, blue: 0.13)
        case "teal": return Color(red: 0.176, green: 0.831, blue: 0.749)
        default: return Color(red: 0.176, green: 0.831, blue: 0.749)
        }
    }

    // MARK: - Font Helpers

    func scaledFont(_ baseFont: Font) -> Font {
        if messageFontSize > 0 {
            return .system(size: messageFontSize)
        }
        return baseFont
    }

    var messageFont: Font {
        if messageFontSize > 0 {
            return .system(size: messageFontSize)
        }
        return .body
    }

    var captionFont: Font {
        .system(size: max(10, 13 * fontScale))
    }

    // MARK: - Layout helpers (delegate spacing to active theme)

    var spacingV: CGFloat { compactMode ? activeTheme.spacingS : activeTheme.spacingM }
    var spacingH: CGFloat { compactMode ? activeTheme.spacingM : activeTheme.spacingL }
    var bubblePaddingV: CGFloat { compactMode ? activeTheme.spacingS : activeTheme.spacingM }
    var bubblePaddingH: CGFloat { compactMode ? activeTheme.spacingM : activeTheme.spacingL }
    var bubbleRadius: CGFloat {
        compactMode ? activeTheme.bubbleRadius * 0.7 : activeTheme.bubbleRadius
    }
}
