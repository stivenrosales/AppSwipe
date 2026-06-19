import Foundation

/// Shared definitions for the user-facing settings persisted in `UserDefaults`.
///
/// Centralising the keys and defaults here keeps the `@AppStorage` declarations in
/// `PreferencesView` and `WindowListView` in lock-step: a typo in a raw key string would
/// otherwise silently split a setting into two unrelated values.
enum AppPreferences {
    /// `UserDefaults` keys. Use these constants everywhere instead of raw strings.
    enum Key {
        /// Bool — whether each row shows the owning app's name under the window title.
        static let showAppName = "showAppName"
        /// Double — width of the switcher list, in points.
        static let listWidth = "listWidth"
        /// Double — base font size for row text (title + subtitle).
        static let textSize = "textSize"
        /// String — font design style: "system", "rounded", or "monospaced".
        static let fontStyle = "fontStyle"
        /// String — named accent color used for the selected-row highlight.
        static let accentColorName = "accentColorName"
    }

    /// Default values, registered at launch so `@AppStorage` reads them before the user
    /// has ever opened Preferences.
    enum Default {
        static let showAppName = true
        static let listWidth = 400.0
        static let textSize = 13.0
        static let fontStyle = FontStyle.system.rawValue
        static let accentColorName = AccentColorPreset.system.rawValue
    }

    /// Allowed range for the list width slider.
    static let listWidthRange: ClosedRange<Double> = 320...560

    /// Allowed range for the text size slider.
    static let textSizeRange: ClosedRange<Double> = 11...17

    /// Font design options persisted as a raw string in UserDefaults.
    enum FontStyle: String, CaseIterable, Identifiable {
        case system      = "system"
        case rounded     = "rounded"
        case monospaced  = "monospaced"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .system:     return "System"
            case .rounded:    return "Rounded"
            case .monospaced: return "Monospaced"
            }
        }
    }

    /// Named accent color presets persisted as a raw string in UserDefaults.
    enum AccentColorPreset: String, CaseIterable, Identifiable {
        case system  = "system"
        case blue    = "blue"
        case purple  = "purple"
        case pink    = "pink"
        case green   = "green"
        case orange  = "orange"
        case graphite = "graphite"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .system:   return "Sistema"
            case .blue:     return "Azul"
            case .purple:   return "Morado"
            case .pink:     return "Rosa"
            case .green:    return "Verde"
            case .orange:   return "Naranja"
            case .graphite: return "Grafito"
            }
        }
    }

    /// Registers default values so first reads return sane settings, not zero/false.
    /// Call once during app launch, before any view reads `@AppStorage`.
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Key.showAppName:    Default.showAppName,
            Key.listWidth:      Default.listWidth,
            Key.textSize:       Default.textSize,
            Key.fontStyle:      Default.fontStyle,
            Key.accentColorName: Default.accentColorName,
        ])
    }
}
