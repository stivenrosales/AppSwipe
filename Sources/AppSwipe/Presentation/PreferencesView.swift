import SwiftUI

/// User-facing preferences UI, persisted to `UserDefaults` via `@AppStorage`.
///
/// All settings are respected live by `WindowListView`, which reads the same `AppPreferences` keys:
/// changes take effect the next time (or, when the panel is on screen, immediately).
///
/// Sections:
/// - **Appearance** — show app name, list width
/// - **Typography** — text size, font style
/// - **Accent color** — swatch picker for the selection highlight
///
/// ## Sizing
/// The window is fixed at `windowWidth` points wide. A fixed width prevents `SwitcherPreviewView`
/// from pushing the window wider when `listWidth` grows — the preview scales to fit the scenario
/// instead. Height is still content-driven: `fixedSize(horizontal: false, vertical: true)` lets
/// the window shrink/grow vertically as content changes, while the horizontal dimension stays
/// locked. `StatusItemController` hosts this in an `NSHostingController` with
/// `sizingOptions = [.preferredContentSize]`, so the window adopts the view's fitting size exactly.
struct PreferencesView: View {

    // MARK: - Layout constants

    /// Fixed pixel width of the Preferences window.
    /// Wide enough to comfortably display the grouped Form (which needs ~20pt lateral insets) and
    /// the preview stage, while staying narrow enough for typical laptop displays.
    private static let windowWidth: CGFloat = 480

    /// Horizontal padding applied on both sides of the preview stage.
    private static let previewHPadding: CGFloat = DS.space.lg   // 16pt each side → 32pt total

    /// Available width for the preview panel inside the scenario stage.
    /// = windowWidth − (previewHPadding × 2) = 480 − 32 = 448pt.
    private static let scenarioWidth: CGFloat =
        windowWidth - previewHPadding * 2

    // MARK: - Stored preferences

    @AppStorage(AppPreferences.Key.showAppName)
    private var showAppName = AppPreferences.Default.showAppName

    @AppStorage(AppPreferences.Key.listWidth)
    private var listWidth = AppPreferences.Default.listWidth

    @AppStorage(AppPreferences.Key.textSize)
    private var textSize = AppPreferences.Default.textSize

    @AppStorage(AppPreferences.Key.fontStyle)
    private var fontStyle = AppPreferences.Default.fontStyle

    @AppStorage(AppPreferences.Key.accentColorName)
    private var accentColorName = AppPreferences.Default.accentColorName

    /// Resolved base accent, shared by the header glyph, slider tints, and the toggle.
    private var accent: Color { Theme.accentColor(for: accentColorName) }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            // MARK: Live preview
            // Rendered ABOVE the Form so it is the first thing the user sees when they open
            // Preferences. `SwitcherPreviewView` uses the exact same `SwitcherRowView` component
            // as the live switcher — there is no style duplication; fidelity is structural.
            previewSection

            Form {
                // MARK: Appearance
                Section {
                    Toggle("Mostrar el nombre de la app", isOn: $showAppName)
                        .tint(accent)

                    VStack(alignment: .leading, spacing: DS.space.sm) {
                        HStack {
                            Text("Ancho de la lista")
                            Spacer()
                            Text("\(Int(listWidth)) pt")
                                .foregroundStyle(accent)
                                .monospacedDigit()
                        }
                        Slider(
                            value: $listWidth,
                            in: AppPreferences.listWidthRange,
                            step: 10
                        )
                        .tint(accent)
                    }
                } header: {
                    sectionHeader("Apariencia", systemImage: "paintbrush.fill")
                }

                // MARK: Typography
                Section {
                    VStack(alignment: .leading, spacing: DS.space.sm) {
                        HStack {
                            Text("Tamaño de texto")
                            Spacer()
                            Text("\(Int(textSize)) pt")
                                .foregroundStyle(accent)
                                .monospacedDigit()
                        }
                        Slider(
                            value: $textSize,
                            in: AppPreferences.textSizeRange,
                            step: 1
                        )
                        .tint(accent)
                    }

                    // Picker is allowed to flow: the grouped Form aligns the label left and the
                    // control right on its own. The old `Spacer()` + `.fixedSize()` forced the
                    // segmented control to its intrinsic width and pushed it past the frame edge.
                    Picker("Estilo de fuente", selection: $fontStyle) {
                        ForEach(AppPreferences.FontStyle.allCases) { style in
                            Text(style.displayName).tag(style.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    sectionHeader("Tipografía", systemImage: "textformat.size")
                }

                // MARK: Accent color
                Section {
                    VStack(alignment: .leading, spacing: DS.space.md) {
                        Text("Color de selección")
                        AccentColorPickerView(selectedName: $accentColorName)
                    }
                } header: {
                    sectionHeader("Color de acento", systemImage: "paintpalette.fill")
                } footer: {
                    VStack(alignment: .leading, spacing: 0) {
                        Divider()
                            .overlay(DS.color.divider)
                            .padding(.bottom, DS.space.sm)
                        Text("Los cambios se aplican la próxima vez que abres el switcher.")
                            .font(.footnote)
                            .foregroundStyle(DS.color.textSecondary)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)   // Preferences is short; no phantom scroll.
        }
        // Fixed width prevents SwitcherPreviewView from pushing the window wider as listWidth
        // changes. The preview is scaled to fit the scenario instead (see previewSection).
        // Height is still content-driven so the window grows/shrinks vertically as needed.
        .frame(width: Self.windowWidth)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Preview section

    /// The "Vista previa" section: a header label followed by the live `SwitcherPreviewView`.
    ///
    /// The preview is centered horizontally so it reads as a discrete floating artifact rather than
    /// a form row — matching how System Settings presents live app previews in macOS 26.
    ///
    /// `SwitcherPreviewView` receives the computed `scenarioWidth` so it knows exactly how much
    /// horizontal space is available and can apply the correct scale factor for `listWidth`.
    /// The `HStack` spacers center the (already fixed-width) preview within the window.
    private var previewSection: some View {
        VStack(alignment: .leading, spacing: DS.space.sm) {
            HStack(spacing: DS.space.xs) {
                Image(systemName: "eye.fill")
                Text("VISTA PREVIA".uppercased())
                    .tracking(0.6)
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(DS.color.textTertiary)
            .padding(.horizontal, DS.space.xl)

            HStack {
                Spacer(minLength: 0)
                SwitcherPreviewView(scenarioWidth: Self.scenarioWidth)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Self.previewHPadding)
            .padding(.bottom, DS.space.md)
        }
        .padding(.top, DS.space.xs)
    }

    // MARK: - Header

    /// A small product header above the Form: an accent-tinted app glyph, the name, and a subtitle.
    /// Mirrors the System Settings layout pattern of macOS 26.
    private var header: some View {
        HStack(spacing: DS.space.md) {
            ZStack {
                RoundedRectangle(cornerRadius: DS.radius.control, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.85), accent.opacity(0.55)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "macwindow.on.rectangle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 38, height: 38)
            .shadow(color: accent.opacity(0.30), radius: 4, x: 0, y: 2)

            VStack(alignment: .leading, spacing: DS.space.xxs) {
                Text("AppSwipe")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DS.color.textPrimary)
                Text("Window switcher")
                    .font(.footnote)
                    .foregroundStyle(DS.color.textSecondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.space.xl)
        .padding(.top, DS.space.xl)
        .padding(.bottom, DS.space.lg)
    }

    /// Section header in the Tahoe System-Settings idiom: an SF glyph + UPPERCASE label with
    /// positive tracking, in the tertiary text color.
    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        HStack(spacing: DS.space.xs) {
            Image(systemName: systemImage)
            Text(title.uppercased())
                .tracking(0.6)
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(DS.color.textTertiary)
    }
}

// MARK: - AccentColorPickerView

/// A grid of tappable color swatches for picking the named accent color preset.
///
/// The selected swatch lifts (spring scale) and gains a *floating* accent ring (a stroked circle
/// with an inner gap), instead of a checkmark — the checkmark competed with the color it sat on.
/// Every swatch carries a faint shadow of its own hue so the color reads as luminous, and hovering
/// nudges the scale to signal interactivity.
private struct AccentColorPickerView: View {
    @Binding var selectedName: String

    @State private var hovered: String?

    private let swatchSize: CGFloat = 28
    private let columns = [GridItem(.adaptive(minimum: 32), spacing: DS.space.md)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: DS.space.md) {
            ForEach(AppPreferences.AccentColorPreset.allCases) { preset in
                let isSelected = selectedName == preset.rawValue
                let isHovered = hovered == preset.rawValue
                let color = Theme.swatchColor(for: preset)

                swatch(color: color, isSelected: isSelected, isHovered: isHovered)
                    .help(preset.displayName)
                    .contentShape(Circle())
                    .onTapGesture {
                        withAnimation(DS.anim.snappy) {
                            selectedName = preset.rawValue
                        }
                    }
                    .onHover { inside in
                        withAnimation(.easeOut(duration: 0.10)) {
                            hovered = inside ? preset.rawValue : (hovered == preset.rawValue ? nil : hovered)
                        }
                    }
            }
        }
    }

    /// One swatch: filled circle, hue shadow, optional floating selection ring, and a hairline on
    /// unselected swatches so very light colors still read on a light background.
    private func swatch(color: Color, isSelected: Bool, isHovered: Bool) -> some View {
        Circle()
            .fill(color)
            .frame(width: swatchSize, height: swatchSize)
            .overlay {
                // Floating accent ring with a 3pt inner gap (via padding) when selected.
                if isSelected {
                    Circle()
                        .strokeBorder(color, lineWidth: 2)
                        .padding(-3)
                } else {
                    // Hairline keeps pale swatches visible on light backgrounds.
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                }
            }
            // The color "glows" — a soft shadow of its own hue.
            .shadow(color: color.opacity(0.40), radius: 3, x: 0, y: 1)
            .scaleEffect(isSelected ? 1.12 : (isHovered ? 1.08 : 1.0))
    }
}
