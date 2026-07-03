import SwiftUI

/// User appearance preferences — stored in UserDefaults via @AppStorage.
/// These are purely client-side, no server interaction needed.
final class AppearanceSettings: ObservableObject {
    // Color scheme
    @AppStorage("colorScheme") var colorScheme: String = "system"  // system, dark, light

    // Accent color
    @AppStorage("accentColor") var accentColor: String = "teal"  // teal, blue, purple, green, orange, red

    // Font size multiplier (0.8 = small, 1.0 = normal, 1.3 = large, 1.5 = extra large)
    @AppStorage("fontScale") var fontScale: Double = 1.0

    // Message font size (explicit override, 0 = use system Dynamic Type)
    @AppStorage("messageFontSize") var messageFontSize: Double = 0  // 0 = auto, 13-22 = explicit

    // Bubble density (compact vs spacious)
    @AppStorage("compactMode") var compactMode: Bool = false

    // Show timestamps on messages
    @AppStorage("showTimestamps") var showTimestamps: Bool = false

    // MARK: - Plain accessors (for passing to child views without Binding issues)

    var showTimestampsBool: Bool { showTimestamps }
    var compactModeBool: Bool { compactMode }
    var fontScaleDouble: Double { fontScale }
    var messageFontSizeDouble: Double { messageFontSize }

    // MARK: - Computed

    var preferredColorScheme: ColorScheme? {
        switch colorScheme {
        case "dark": return .dark
        case "light": return .light
        default: return nil  // system
        }
    }

    var accent: Color {
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

    var spacingV: CGFloat { compactMode ? 6 : 12 }
    var spacingH: CGFloat { compactMode ? 12 : 16 }
    var bubblePaddingV: CGFloat { compactMode ? 8 : 12 }
    var bubblePaddingH: CGFloat { compactMode ? 12 : 16 }
    var bubbleRadius: CGFloat { compactMode ? 14 : 22 }
}