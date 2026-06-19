import SwiftUI
import AppKit

// MARK: - PreviewRow

/// A single row's data for the Preferences preview.
///
/// Populated from real running applications via `NSWorkspace`, with placeholder entries filling
/// any gap so the preview always shows exactly 4 rows. Using real icons and names makes the
/// preview representative; placeholders use a generic SF-Symbol-based icon so they look natural
/// alongside real entries.
struct PreviewRow: Identifiable {
    let id: Int
    let icon: NSImage?
    let title: String
    let appName: String
}

// MARK: - PreviewRow sample data

extension PreviewRow {

    /// Returns 4 sample rows driven by the currently running regular applications.
    ///
    /// Strategy:
    /// 1. Collect `activationPolicy == .regular` running apps, take their `localizedName` and
    ///    `icon`. Skip apps without a name.
    /// 2. Fill up to 4 rows from that list.
    /// 3. Pad with named placeholders if fewer than 4 real apps are running.
    static func makeSampleRows() -> [PreviewRow] {
        let real: [PreviewRow] = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> PreviewRow? in
                guard let name = app.localizedName, !name.isEmpty else { return nil }
                return PreviewRow(id: 0, icon: app.icon, title: name, appName: name)
            }
            .prefix(4)
            .enumerated()
            .map { index, row in
                PreviewRow(id: index, icon: row.icon, title: row.title, appName: row.appName)
            }

        guard real.count < 4 else { return real }

        let placeholders: [(title: String, appName: String)] = [
            ("Untitled Document",   "TextEdit"),
            ("Downloads",           "Finder"),
            ("Inbox — 3 messages",  "Mail"),
            ("main.swift — AppSwipe", "Xcode"),
        ]

        var rows = real
        var placeholderIndex = 0
        let fallbackIcon = NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)

        while rows.count < 4 && placeholderIndex < placeholders.count {
            let placeholder = placeholders[placeholderIndex]
            // Avoid duplicating a real app we already have.
            if !rows.contains(where: { $0.appName == placeholder.appName }) {
                rows.append(PreviewRow(
                    id: rows.count,
                    icon: fallbackIcon,
                    title: placeholder.title,
                    appName: placeholder.appName
                ))
            }
            placeholderIndex += 1
        }

        return rows
    }
}

// MARK: - SwitcherPreviewView

/// A live, non-interactive replica of the switcher panel, rendered inside the Preferences window.
///
/// ## Fidelity guarantee
/// Every row is rendered by `SwitcherRowView` — the SAME component used in `WindowListView`.
/// There is no style duplication: changing a token in `DesignSystem` ripples into both the real
/// switcher and this preview at once.
///
/// ## Live reactivity
/// All `@AppStorage` bindings here use the same keys as `WindowListView`. SwiftUI invalidates
/// this view whenever the user moves a slider or taps an accent swatch — the preview updates
/// before the user lifts their finger.
///
/// ## Background
/// The real panel uses `NSGlassEffectView` which diffracts the live desktop behind the window.
/// Inside a `PreferencesView` there is no desktop *behind* the glass to diffract, so we use a
/// subtle multi-stop gradient as a representative backdrop — enough color and depth to show how
/// the rows and selection highlight read against a non-white surface.
///
/// ## Width handling
/// The preview renders the panel at its real `listWidth` but is placed inside a fixed-width
/// *scenario* (determined by the Preferences window width). A `scaleEffect` uniformly shrinks the
/// panel so it always fits within the scenario — the user sees a proportional representation of
/// how wide the switcher will be, without the preview ever pushing the Preferences window wider.
/// The container reserves the correct post-scale height so layout never jumps.
///
/// - Parameter scenarioWidth: The available horizontal space inside the Preferences window (the
///   window's fixed width minus horizontal padding). Defaults to a sensible standalone value.
struct SwitcherPreviewView: View {

    /// The fixed pixel budget for the preview stage. Supplied by `PreferencesView` so both views
    /// share the same constant without coupling them through a hard-coded magic number here.
    var scenarioWidth: CGFloat = 448

    // MARK: Live preferences (same keys as WindowListView)

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

    // MARK: Sample data (constant for the lifetime of the view)

    private let rows: [PreviewRow] = PreviewRow.makeSampleRows()

    // MARK: Namespace for the sliding selection highlight

    @Namespace private var selectionNamespace

    // MARK: Body

    var body: some View {
        let accent = Theme.accentPair(for: accentColorName)
        let fontDesign = Theme.fontDesign(for: fontStyle)
        let density = RowDensity.comfortable    // preview always uses comfortable density

        // Scale factor: shrink the panel proportionally so it fits the scenario.
        // When listWidth <= scenarioWidth the panel is shown at 1:1 (no upscaling).
        let scale = min(1.0, scenarioWidth / listWidth)

        // Estimate the natural height of the panel at full size.
        // We measure via a row-count heuristic rather than GeometryReader to avoid a layout
        // feedback loop: each row is approximately (iconSize + vertical padding) = ~48pt at
        // comfortable density, plus the list's own padding on both ends.
        let rowCount = CGFloat(rows.count)
        let rowHeight: CGFloat = 48     // comfortable density ≈ 48pt per row
        let naturalHeight = rowHeight * rowCount
            + RowDensity.comfortable.listPadding * 2

        // After scaling, the panel occupies a smaller rectangle. Reserve that exact height so
        // the layout does not jump or leave phantom whitespace.
        let scaledHeight = naturalHeight * scale

        VStack(spacing: DS.space.xs) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                SwitcherRowView(
                    icon: row.icon,
                    title: row.title,
                    appName: row.appName,
                    // Show the subtitle only when showAppName is on AND the row has distinct names.
                    // For the sample rows title == appName, so the subtitle appears only when
                    // the user explicitly enables showAppName (which gives a useful signal).
                    showAppNameSubtitle: showAppName && row.title != row.appName,
                    isSelected: index == 1,     // row 1 is always selected to show the highlight
                    density: density,
                    textSize: textSize,
                    fontDesign: fontDesign,
                    accent: accent,
                    selectionNamespace: selectionNamespace,
                    selectionAnimation: DS.anim.snappy,
                    onTap: { }                  // no-op: preview is display-only
                )
            }
        }
        .padding(RowDensity.comfortable.listPadding)
        // Clip to the panel shape — same radius as the real switcher.
        .clipShape(RoundedRectangle(cornerRadius: DS.radius.panel, style: .continuous))
        .overlay(
            // Top-lit hairline border — same as the real panel.
            RoundedRectangle(cornerRadius: DS.radius.panel, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [DS.color.hairlineTop, DS.color.hairlineBottom],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
        // Representative desktop backdrop: a diagonal gradient with some hue so the glass
        // contrast and row highlight are both visible against something that is not white.
        .background(previewBackground)
        // Render the panel at its real listWidth so content proportions are accurate.
        .frame(width: listWidth)
        // Subtle panel shadow to sell the floating depth.
        .shadow(DS.shadow.panelKey)
        // Scale uniformly so the panel fits within the scenario without pushing the window wider.
        // anchorPoint: .center keeps the panel visually centered in the scenario stage.
        .scaleEffect(scale)
        // Collapse the SwiftUI layout frame to the post-scale size so the surrounding VStack
        // reserves the right space and does not leave gaps or overflow.
        .frame(width: scenarioWidth, height: scaledHeight)
    }

    // MARK: - Background

    /// A gradient that evokes a typical colorful macOS desktop, so the preview communicates
    /// the glass contrast and the selection highlight accurately.
    private var previewBackground: some View {
        RoundedRectangle(cornerRadius: DS.radius.panel, style: .continuous)
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: Color(.sRGB, red: 0.10, green: 0.14, blue: 0.30, opacity: 0.95), location: 0.0),
                        .init(color: Color(.sRGB, red: 0.18, green: 0.10, blue: 0.28, opacity: 0.95), location: 0.45),
                        .init(color: Color(.sRGB, red: 0.08, green: 0.18, blue: 0.24, opacity: 0.95), location: 1.0),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }
}
