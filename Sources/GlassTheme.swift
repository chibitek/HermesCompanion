import SwiftUI

// MARK: - Theme Environment Key

/// Allows passing the active theme through the SwiftUI environment.
private struct ActiveThemeKey: EnvironmentKey {
    static let defaultValue: any HermesTheme = HermesDefaultTheme()
}

extension EnvironmentValues {
    var activeTheme: any HermesTheme {
        get { self[ActiveThemeKey.self] }
        set { self[ActiveThemeKey.self] = newValue }
    }
}

// MARK: - View Modifier Extension

extension View {
    /// Apply conditional transform
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, @ViewBuilder transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// MARK: - Active Theme Environment Modifier

extension View {
    /// Inject the active HermesTheme into the SwiftUI environment.
    /// Use this on sheets/fullScreenCovers whose view hierarchy does not
    /// inherit the environment object from the presenting view.
    func withActiveTheme(_ appearance: AppearanceSettings) -> some View {
        self
            .environmentObject(appearance)
            .environment(\.activeTheme, appearance.activeTheme)
    }
}
