import SwiftUI

// MARK: - DesignSystem

/// The single source of truth for every visual constant in the app: spacing, radii, colors,
/// typography rules, shadows, and animation curves.
///
/// ## Why a token file
/// Before this existed, magic numbers were scattered across `WindowListView`, `SwitcherPanel`,
/// and `PreferencesView` (`11`, `18`, `0.18`, …). That is design debt: changing the panel radius
/// meant hunting through three files and hoping the concentric row radius was updated too. Here
/// every surface derives from the same scale, so concentricity (`radius_inner = radius_outer −
/// padding`) is enforceable and a single edit ripples everywhere.
///
/// The aliased `DS` makes call sites terse: `DS.radius.panel`, `DS.space.md`, `DS.anim.snappy`.
///
/// Nothing here references macOS-26-only APIs (glass lives in `WindowListView`); these tokens are
/// safe on the package's `macOS 14` deployment floor.
enum DesignSystem {

    // MARK: Spacing (base-4 grid)

    /// Layout spacing scale. **Rule:** no layout value lives outside this scale.
    /// A strict grid is what makes a UI read as "engineered" rather than hand-nudged.
    enum space {
        static let xxs: CGFloat = 2
        static let xs:  CGFloat = 4
        static let sm:  CGFloat = 8
        static let md:  CGFloat = 12
        static let lg:  CGFloat = 16
        static let xl:  CGFloat = 24
        static let xxl: CGFloat = 32
    }

    // MARK: Radii (concentricity)

    /// Corner radii. **Rule of concentricity:** an inner radius equals its outer radius minus the
    /// padding between them, so nested rounded rectangles stay visually parallel.
    /// `panel(20) − listPadding(8) = row(12)`.
    enum radius {
        /// Floating panel surface. Tahoe raised the radius of floating surfaces; this aligns with
        /// the macOS 26 Spotlight panel.
        static let panel:   CGFloat = 20
        /// A row's selection/hover background. Concentric with the panel at `listPadding = 8`.
        static let row:     CGFloat = 12
        /// Small controls: buttons, swatch inner ring.
        static let control: CGFloat = 8
        /// Fully-rounded pill (shortcut badge). Large enough to round any reasonable height.
        static let pill:    CGFloat = 999
    }

    // MARK: Colors

    /// Semantic and accent colors. Text colors are *semantic* (`Color.primary`-derived) so they
    /// adapt to light/dark for free; accents are explicit `sRGB` pairs tuned for glass.
    enum color {

        // Text — fixed opacities (NOT `.secondary`/`.tertiary`, which wash out over dark glass).
        static let textPrimary   = Color.primary
        static let textSecondary = Color.primary.opacity(0.58)
        static let textTertiary  = Color.primary.opacity(0.40)

        // Surface treatments over glass.
        /// Top edge of the panel's light border — the "lensing" highlight.
        static let hairlineTop    = Color.white.opacity(0.22)
        /// Bottom edge of the panel's light border — fades to near-nothing.
        static let hairlineBottom = Color.white.opacity(0.04)
        /// Neutral hover fill (no tint, so it never competes with the accent selection).
        static let fillHover      = Color.primary.opacity(0.07)
        /// Divider used in Preferences (above the footer, etc.).
        static let divider        = Color.primary.opacity(0.06)

        /// An accent is a *pair*: a base tone (borders, plain fallback fills) and a brighter tone
        /// used only at the top of the selection gradient, so the highlight reads as lit glass.
        struct Accent {
            let base: Color
            let bright: Color
        }

        /// Resolves a named preset to its `Accent` pair. `system` follows the user's chosen system
        /// accent via `Color.accentColor` (base == bright; the system color is already calibrated).
        static func accent(for preset: AppPreferences.AccentColorPreset) -> Accent {
            switch preset {
            case .blue:
                return Accent(base:   Color(.sRGB, red: 0.20, green: 0.52, blue: 0.98),
                              bright: Color(.sRGB, red: 0.36, green: 0.63, blue: 1.0))
            case .purple:
                return Accent(base:   Color(.sRGB, red: 0.58, green: 0.34, blue: 0.95),
                              bright: Color(.sRGB, red: 0.71, green: 0.49, blue: 1.0))
            case .pink:
                return Accent(base:   Color(.sRGB, red: 0.96, green: 0.30, blue: 0.56),
                              bright: Color(.sRGB, red: 1.0,  green: 0.44, blue: 0.66))
            case .green:
                return Accent(base:   Color(.sRGB, red: 0.22, green: 0.80, blue: 0.42),
                              bright: Color(.sRGB, red: 0.32, green: 0.88, blue: 0.52))
            case .orange:
                return Accent(base:   Color(.sRGB, red: 0.99, green: 0.58, blue: 0.20),
                              bright: Color(.sRGB, red: 1.0,  green: 0.66, blue: 0.30))
            case .graphite:
                // Raised from 0.55 → 0.62: dark grey over glass reads as dirty, not neutral.
                return Accent(base:   Color(.sRGB, red: 0.62, green: 0.62, blue: 0.66),
                              bright: Color(.sRGB, red: 0.74, green: 0.74, blue: 0.78))
            case .system:
                return Accent(base: Color.accentColor, bright: Color.accentColor)
            }
        }
    }

    // MARK: Typography

    /// Typography rules that depend on the user's chosen `Font.Design`.
    enum typography {
        /// Negative tracking only looks right on `.default` (the SF text optical model). Rounded
        /// and monospaced carry their own spacing, so tighten nothing there.
        static func titleTracking(for design: Font.Design) -> CGFloat {
            design == .default ? -0.2 : 0
        }
    }

    // MARK: Shadows

    /// A shadow layer: color, blur radius, and vertical offset (x is always 0 here).
    struct Shadow {
        let color: Color
        let radius: CGFloat
        let y: CGFloat
    }

    /// Multi-layer shadow recipes. Real depth comes from stacking a tight *contact* shadow, a
    /// *key* shadow for mass, and a wide *ambient* shadow for the sense of floating.
    enum shadow {
        // Panel (L0) — three layers. The ambient (34 + 18) drives `SwitcherPanel.shadowMargin`.
        static let panelContact = Shadow(color: .black.opacity(0.12), radius: 3,  y: 1)
        static let panelKey     = Shadow(color: .black.opacity(0.24), radius: 16, y: 8)
        static let panelAmbient = Shadow(color: .black.opacity(0.18), radius: 34, y: 18)

        /// Selected row (L2) tinted lift — "lit", not painted. `color` is supplied by the accent.
        static func selectionLift(_ accent: Color) -> Shadow {
            Shadow(color: accent.opacity(0.28), radius: 7, y: 3)
        }
        static let selectionContact = Shadow(color: .black.opacity(0.10), radius: 3, y: 1)

        /// App-icon contact shadow — seats the icon on the row.
        static let iconContact = Shadow(color: .black.opacity(0.18), radius: 2, y: 1)
    }

    // MARK: Animation

    /// Motion curves. **Rule of motion:** what ENTERS or is SELECTED uses a spring (it has mass,
    /// it feels alive); what LEAVES is fast and linear (a decision, not a flourish). Hover is the
    /// one defensible ease — it is continuous, not a discrete state change.
    enum anim {
        static let snappy   = Animation.spring(response: 0.28, dampingFraction: 0.82)
        static let smooth   = Animation.spring(response: 0.34, dampingFraction: 0.88)
        static let hoverIn  = Animation.easeOut(duration: 0.16)
        static let hoverOut = Animation.easeOut(duration: 0.20)

        /// Reduced-motion replacement: effectively instant, but still a valid `Animation` so call
        /// sites do not branch their structure.
        static let none = Animation.linear(duration: 0.01)
    }
}

/// Terse alias for `DesignSystem`. Use `DS.radius.panel`, `DS.space.md`, etc. at call sites.
typealias DS = DesignSystem

// MARK: - Shadow application helper

extension View {
    /// Applies a `DesignSystem.Shadow` token. Keeps call sites declarative
    /// (`.shadow(DS.shadow.panelKey)`) instead of repeating `color:radius:x:y:`.
    func shadow(_ token: DesignSystem.Shadow) -> some View {
        shadow(color: token.color, radius: token.radius, x: 0, y: token.y)
    }
}
