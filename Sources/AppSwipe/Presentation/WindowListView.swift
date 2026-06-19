import SwiftUI
import AppKit
import AppSwipeCore

// MARK: - Layout constants

/// Corner radius shared by the panel container, its native-glass backdrop, and the clip shape.
/// Kept in one place so the SwiftUI clip and the glass layer mask stay in lock-step.
/// Sourced from the design tokens so the panel and its concentric rows stay in sync.
private let panelCornerRadius: CGFloat = DS.radius.panel

// MARK: - RowDensity

/// Adaptive row sizing for the switcher list.
///
/// With only a handful of windows we use a roomy, comfortable row; as the count grows we step
/// down to a denser row so the panel can show *every* window without scrolling. The values are
/// chosen so the list stays readable at the compact end while still fitting many rows on screen.
///
/// Note: title/subtitle sizes are baseline values that are OFFSET by the user's `textSize`
/// preference via `RowDensity.titleSize(base:)` and `RowDensity.subtitleSize(base:)`.
enum RowDensity {
    case comfortable
    case compact

    /// Picks a density from the number of rows. The threshold is deliberately conservative: most
    /// sessions have a few windows and get the comfortable layout; only busy sessions compact.
    static func forCount(_ count: Int) -> RowDensity {
        count <= 8 ? .comfortable : .compact
    }

    var verticalPadding: CGFloat {
        switch self {
        case .comfortable: return 9   // +1 over the grid for a touch of luxury at low density
        case .compact:     return 5
        }
    }

    var horizontalPadding: CGFloat { DS.space.md }   // 12 — on-grid (was 11)

    var iconSize: CGFloat {
        switch self {
        case .comfortable: return 24
        case .compact:     return 20   // multiple of 4 (was 19)
        }
    }

    /// Returns the title font size for this density, offset by the user preference.
    ///
    /// `base` is the value from `AppPreferences.Key.textSize` (default 13 pt).
    /// The comfortable density uses it directly; compact steps it down 1 pt.
    func titleSize(base: Double) -> CGFloat {
        switch self {
        case .comfortable: return CGFloat(base)
        case .compact:     return CGFloat(max(base - 1, 10))
        }
    }

    /// Returns the subtitle font size, always 3 pt below the title size (clearer hierarchy).
    func subtitleSize(base: Double) -> CGFloat {
        max(titleSize(base: base) - 3, 9)
    }

    /// Spacing between rows.
    var rowSpacing: CGFloat {
        switch self {
        case .comfortable: return DS.space.xs   // 4 — more air for the discreet selection
        case .compact:     return 3
        }
    }

    /// Inner padding around the whole list (inside the rounded container).
    /// Comfortable = 8 keeps concentricity with the panel: 20 − 8 = 12 (row radius).
    var listPadding: CGFloat {
        switch self {
        case .comfortable: return DS.space.sm   // 8
        case .compact:     return 6
        }
    }
}

// MARK: - WindowListView

/// Pure display view for the window switcher. Renders the observable model and forwards row
/// clicks; it holds no navigation logic of its own.
///
/// The view reads from a `SwitcherViewModel`. Because that model is `@Observable`, mutating its
/// `windows`/`selectedIndex` re-renders this view in place; the panel never has to rebuild the
/// hosting view or replay its entrance animation between Tabs.
///
/// ## Adaptive height (no scroll until forced)
/// The list is sized to show *all* windows: it does not impose a fixed `maxHeight`. Instead the
/// owning panel passes `maxHeight` — about 85% of the active screen's visible height. The content
/// grows freely up to that ceiling; only when the windows genuinely cannot fit does the inner
/// `ScrollView` start scrolling. Row density adapts to the window count so that, in practice, the
/// ceiling is rarely reached.
///
/// ## Click-to-select
/// Each row is clickable. A click reports the row's window id back through the view model's
/// `onSelect`, which `AppController` wires to activate that window and close the panel.
///
/// Layout honours user preferences (`AppPreferences`): the list width, whether the app name is
/// shown, text size, font style, and accent color are all read live from `@AppStorage`.
struct WindowListView: View {
    @Bindable var viewModel: SwitcherViewModel

    /// Hard ceiling on the list height, supplied by the panel (≈85% of the visible screen).
    /// The content stays as small as its rows need and only scrolls if it would exceed this.
    let maxHeight: CGFloat

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

    /// Honour the system "Reduce Transparency" setting for the glass fallback.
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    /// Honour the system "Reduce Motion" setting: springs collapse to (near-)instant changes.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Drives the sliding selection background between rows.
    @Namespace private var selectionNamespace

    init(viewModel: SwitcherViewModel, maxHeight: CGFloat) {
        self.viewModel = viewModel
        self.maxHeight = maxHeight
    }

    private var density: RowDensity {
        RowDensity.forCount(viewModel.windows.count)
    }

    /// Selection animation, downgraded to (near-)instant when Reduce Motion is on.
    private var selectionAnimation: Animation {
        reduceMotion ? DS.anim.none : DS.anim.snappy
    }

    var body: some View {
        let density = self.density
        let shape = RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
        let accent = Theme.accentPair(for: accentColorName)
        let resolvedDesign = Theme.fontDesign(for: fontStyle)

        Group {
            if viewModel.windows.isEmpty {
                emptyState(textSize: textSize)
            } else {
                list(density: density, accent: accent, fontDesign: resolvedDesign)
            }
        }
        .frame(width: listWidth)
        // Native macOS glass backdrop, masked to the same rounded shape. On macOS 26 this is a
        // real `NSGlassEffectView`; older systems and Reduce Transparency fall back to an opaque
        // material (see `NativeGlassBackground`). Accessibility handled for free.
        .background(
            NativeGlassBackground(
                cornerRadius: panelCornerRadius,
                reduceTransparency: reduceTransparency
            )
        )
        // Clip the content (rows + glass) to the rounded shape so nothing square pokes out.
        .clipShape(shape)
        .overlay(
            // Light border: instead of a flat hairline, a vertical gradient that is bright at the
            // top edge and fades to almost nothing at the bottom. This "lensing" highlight is the
            // single detail that separates real Tahoe glass from a generic blur. Degrades to a
            // plain separator when transparency is reduced.
            shape.strokeBorder(borderStyle, lineWidth: 1)
        )
        // Three-layer shadow (contact / key / ambient) for genuine depth. Applied *after* the clip
        // so each layer hugs the rounded silhouette. The NSPanel carries no window shadow
        // (`hasShadow = false`), so these are the only shadows — no square halo behind the glass.
        .shadow(DS.shadow.panelContact)
        .shadow(DS.shadow.panelKey)
        .shadow(DS.shadow.panelAmbient)
    }

    // MARK: - Subviews

    /// The scrolling window list. Extracted so the body can swap in an empty state.
    private func list(
        density: RowDensity,
        accent: DesignSystem.color.Accent,
        fontDesign: Font.Design
    ) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: density.rowSpacing) {
                    ForEach(Array(viewModel.windows.enumerated()), id: \.element.id) { index, window in
                        WindowRowView(
                            window: window,
                            isSelected: index == viewModel.selectedIndex,
                            showAppName: showAppName,
                            density: density,
                            textSize: textSize,
                            fontDesign: fontDesign,
                            accent: accent,
                            selectionNamespace: selectionNamespace,
                            selectionAnimation: selectionAnimation,
                            onTap: { viewModel.onSelect?(window.id) }
                        )
                        .id(index)
                    }
                }
                .padding(density.listPadding)
            }
            // `.fixedSize` on the vertical axis lets the ScrollView report its content's natural
            // height to `fittingSize`, so the panel grows to fit. The `maxHeight` frame then caps
            // it; the ScrollView only actually scrolls once the content exceeds that cap.
            .frame(maxHeight: maxHeight)
            .fixedSize(horizontal: false, vertical: true)
            .onChange(of: viewModel.selectedIndex) { _, newIndex in
                withAnimation(reduceMotion ? DS.anim.none : DS.anim.smooth) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
    }

    /// Shown inside the panel when there are no open windows to switch between.
    private func emptyState(textSize: Double) -> some View {
        VStack(spacing: DS.space.sm) {
            Image(systemName: "macwindow.on.rectangle")
                .font(.system(size: 22))
                .foregroundStyle(DS.color.textTertiary)
            Text("Sin ventanas abiertas")
                .font(.system(size: CGFloat(textSize), weight: .medium))
                .foregroundStyle(DS.color.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.space.xl)
        .padding(.horizontal, DS.space.lg)
    }

    /// The panel's light-border style. A top-lit gradient over glass; a flat separator under
    /// Reduce Transparency (no glass to catch the light).
    private var borderStyle: AnyShapeStyle {
        if reduceTransparency {
            return AnyShapeStyle(Color(nsColor: .separatorColor))
        }
        return AnyShapeStyle(
            LinearGradient(
                colors: [DS.color.hairlineTop, DS.color.hairlineBottom],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

// MARK: - NativeGlassBackground

/// Bridges a real AppKit glass surface into SwiftUI for an authentic macOS backdrop.
///
/// ## Why AppKit, not SwiftUI `.glassEffect`
/// The SwiftUI `.glassEffect` API lives in `SwiftUICore`, whose macOS `.swiftinterface` is **not**
/// materialised on disk in a Command-Line-Tools-only toolchain (only the Catalyst variant is), so
/// linking against it from `make build` is a real risk. `NSGlassEffectView` is a concrete ObjC
/// class with a shipping header (`NSGlassEffectView.h`) — zero link risk. So the panel's glass goes
/// through AppKit; SwiftUI glass remains a documented Phase-2 enhancement.
///
/// ## Layering of fallbacks (in priority order)
/// 1. **Reduce Transparency on** → an opaque `windowBackgroundColor` panel (no blur at all).
/// 2. **macOS 26+** → a genuine `NSGlassEffectView` (Tahoe "Liquid Glass").
/// 3. **macOS 14–15** → the previous `NSVisualEffectView(.hudWindow)` behind-window blur.
///
/// In every case the surface layer is given a matching corner radius so no square edge peeks
/// through the translucency — belt-and-suspenders with the SwiftUI `clipShape`.
private struct NativeGlassBackground: NSViewRepresentable {
    let cornerRadius: CGFloat
    let reduceTransparency: Bool

    func makeNSView(context: Context) -> NSView {
        makeSurface()
    }

    func updateNSView(_ view: NSView, context: Context) {
        // Keep the corner radius in sync. `NSGlassEffectView` exposes its own `cornerRadius`
        // property (not a layer mask), so set that when present; otherwise update the layer.
        // `NSGlassEffectView` is referenced only inside the availability guard as a *value*,
        // never as a declared type, so this compiles against the macOS 14 deployment floor.
        if #available(macOS 26, *), let glass = view as? NSGlassEffectView {
            glass.cornerRadius = cornerRadius
        } else {
            view.layer?.cornerRadius = cornerRadius
        }
    }

    /// Builds the appropriate backdrop view for the current OS + accessibility state.
    private func makeSurface() -> NSView {
        if reduceTransparency {
            return opaqueFallback()
        }
        if #available(macOS 26, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular           // neutral, untinted dense glass
            glass.tintColor = nil
            glass.cornerRadius = cornerRadius
            return glass
        }
        return visualEffectFallback()
    }

    /// macOS 14–15 path: the previous behind-window HUD blur.
    private func visualEffectFallback() -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = true
        roundLayer(of: view)
        return view
    }

    /// Reduce-Transparency path: a flat, opaque surface — no sampling of what is behind it.
    private func opaqueFallback() -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        roundLayer(of: view)
        return view
    }

    /// Rounds a view's backing layer to `cornerRadius` with a continuous curve.
    private func roundLayer(of view: NSView) {
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
    }
}

// MARK: - WindowRowView

/// A single row in the window list.
///
/// This view is a thin adapter over `SwitcherRowView`: it resolves the icon from the window's
/// `pid` via `AppIconView` and delegates all rendering to the shared component. This ensures the
/// preview in `PreferencesView` is pixel-identical to the live switcher — same component, same
/// tokens, no duplication.
private struct WindowRowView: View {
    let window: WindowInfo
    let isSelected: Bool
    let showAppName: Bool
    let density: RowDensity
    let textSize: Double
    let fontDesign: Font.Design
    let accent: DesignSystem.color.Accent
    let selectionNamespace: Namespace.ID
    let selectionAnimation: Animation
    let onTap: () -> Void

    private var resolvedIcon: NSImage? {
        NSRunningApplication(processIdentifier: window.pid)?.icon
    }

    /// A distinct window title exists only when it differs from the app name.
    private var hasDistinctTitle: Bool {
        !window.title.isEmpty && window.title != window.appName
    }

    var body: some View {
        SwitcherRowView(
            icon: resolvedIcon,
            title: hasDistinctTitle ? window.title : window.appName,
            appName: window.appName,
            showAppNameSubtitle: hasDistinctTitle && showAppName,
            isSelected: isSelected,
            density: density,
            textSize: textSize,
            fontDesign: fontDesign,
            accent: accent,
            selectionNamespace: selectionNamespace,
            selectionAnimation: selectionAnimation,
            onTap: onTap
        )
    }
}

// MARK: - SwitcherRowView

/// The shared, data-driven row component used by both the live switcher and the Preferences
/// preview.
///
/// Accepts generic data (icon, title, appName) rather than a `WindowInfo` so it can be driven
/// from real running-app data in the preview without any dependency on AppSwipeCore's domain
/// types. The live switcher feeds it through `WindowRowView`; the preview feeds it directly.
///
/// ## Visual behaviour
/// - Selection: top-lit accent gradient + border + tinted lift shadow, slid via
///   `matchedGeometryEffect` for the "flowing glass" feel.
/// - Hover: neutral translucent fill, never competes with the selection accent.
/// - Typography: scales from `textSize` and `fontDesign`, using `RowDensity` helpers.
/// - Interaction: the whole row rect is the hit target; cursor changes to `.pointingHand`.
struct SwitcherRowView: View {
    /// App icon. `nil` falls back to a tinted initial-letter squircle.
    let icon: NSImage?
    /// Primary row text (window title, or app name when they are identical).
    let title: String
    /// App name used for the optional subtitle and the fallback initial glyph.
    let appName: String
    /// Whether to render the app-name subtitle below the title.
    let showAppNameSubtitle: Bool
    let isSelected: Bool
    let density: RowDensity
    let textSize: Double
    let fontDesign: Font.Design
    let accent: DesignSystem.color.Accent
    let selectionNamespace: Namespace.ID
    let selectionAnimation: Animation
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: DS.space.md - 1) {   // 11 — icon ↔ text
            IconView(
                icon: icon,
                appName: appName,
                size: density.iconSize,
                isSelected: isSelected,
                accent: accent,
                selectionAnimation: selectionAnimation
            )

            if showAppNameSubtitle {
                VStack(alignment: .leading, spacing: DS.space.xxs) {   // 2 — title ↔ subtitle
                    titleText(title)
                    Text(appName)
                        .font(.system(
                            size: density.subtitleSize(base: textSize),
                            weight: isSelected ? .medium : .regular,
                            design: fontDesign
                        ))
                        .foregroundStyle(DS.color.textSecondary)
                        .lineLimit(1)
                }
            } else {
                titleText(title)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, density.horizontalPadding)
        .padding(.vertical, density.verticalPadding)
        .background {
            if isSelected {
                selectionBackground
                    .matchedGeometryEffect(id: "selection", in: selectionNamespace)
            } else if isHovered {
                RoundedRectangle(cornerRadius: DS.radius.row, style: .continuous)
                    .fill(DS.color.fillHover)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onHover { hovering in
            withAnimation(hovering ? DS.anim.hoverIn : DS.anim.hoverOut) {
                isHovered = hovering
            }
        }
        .cursor(.pointingHand)
        .animation(selectionAnimation, value: isSelected)
    }

    private func titleText(_ text: String) -> some View {
        Text(text)
            .font(.system(
                size: density.titleSize(base: textSize),
                weight: .semibold,
                design: fontDesign
            ))
            .tracking(DS.typography.titleTracking(for: fontDesign))
            .foregroundStyle(DS.color.textPrimary)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    private var selectionBackground: some View {
        RoundedRectangle(cornerRadius: DS.radius.row, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [accent.bright.opacity(0.30), accent.base.opacity(0.18)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.radius.row, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [accent.base.opacity(0.50), accent.base.opacity(0.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(DS.shadow.selectionLift(accent.base))
            .shadow(DS.shadow.selectionContact)
    }
}

// MARK: - Cursor modifier

/// Lightweight modifier that changes the NSCursor while the pointer is inside the view.
private extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        onHover { inside in
            if inside {
                cursor.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

// MARK: - IconView

/// Displays an app icon, or a tinted initial-letter squircle when no icon is available.
///
/// This view accepts a pre-resolved `NSImage?` so it can be used both from the live switcher
/// (where `WindowRowView` resolves the icon from a `pid`) and from the Preferences preview
/// (where icons come from `NSWorkspace.shared.runningApplications`). The rendering is identical
/// in both contexts — that is the whole point.
///
/// The icon is clipped to the macOS superellipse (squircle) corner, carries a faint contact
/// shadow, and scales up a touch on the focused row.
struct IconView: View {
    /// Pre-resolved icon. `nil` renders the fallback initial-letter squircle.
    let icon: NSImage?
    let appName: String
    let size: CGFloat
    let isSelected: Bool
    let accent: DesignSystem.color.Accent
    let selectionAnimation: Animation

    /// macOS icon corner-radius ratio (Apple's squircle): radius ≈ 22.37% of the side length.
    private var cornerRadius: CGFloat { size * 0.2237 }

    /// First character of the app name for the fallback glyph; "?" if the name is empty.
    private var initial: String {
        String(appName.first.map(String.init)?.uppercased() ?? "?")
    }

    var body: some View {
        Group {
            if let image = icon {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [accent.base.opacity(0.55), accent.base.opacity(0.30)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        Text(initial)
                            .font(.system(size: size * 0.42, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                    )
            }
        }
        .frame(width: size, height: size)
        .shadow(DS.shadow.iconContact)
        .scaleEffect(isSelected ? 1.06 : 1.0)
        .animation(selectionAnimation, value: isSelected)
    }
}
