import SwiftUI

/// Mapping helpers that translate raw `AppPreferences` string values into concrete SwiftUI types.
///
/// Keeping these in one file avoids scattering the switch statements across views and ensures every
/// consumer derives the same `Font.Design` or `Color` from the same string key.
enum Theme {

    // MARK: - Font helpers

    /// Returns the `Font.Design` that corresponds to the stored `AppPreferences.FontStyle` raw value.
    /// Falls back to `.default` for any unrecognised string.
    static func fontDesign(for rawValue: String) -> Font.Design {
        switch AppPreferences.FontStyle(rawValue: rawValue) {
        case .rounded:    return .rounded
        case .monospaced: return .monospaced
        default:          return .default
        }
    }

    // MARK: - Color helpers

    /// Returns the full base+bright `Accent` pair for the stored preset raw value.
    /// All accent values live in `DesignSystem.color.accent(for:)` — this is just the
    /// string → enum bridge, so views can stay string-typed via `@AppStorage`.
    static func accentPair(for rawValue: String) -> DesignSystem.color.Accent {
        let preset = AppPreferences.AccentColorPreset(rawValue: rawValue) ?? .system
        return DesignSystem.color.accent(for: preset)
    }

    /// Returns the base accent `Color` for the stored preset raw value.
    /// Falls back to `Color.accentColor` (the system accent) for any unrecognised string.
    static func accentColor(for rawValue: String) -> Color {
        accentPair(for: rawValue).base
    }

    /// A swatch `Color` suitable for use in a color-picker UI (the base tone of the preset).
    static func swatchColor(for preset: AppPreferences.AccentColorPreset) -> Color {
        DesignSystem.color.accent(for: preset).base
    }
}
