import AppKit
import SwiftUI

// MARK: - SwitcherPanel

/// A floating, non-activating `NSPanel` that hosts the switcher list.
///
/// The panel never steals key focus from the frontmost app, which is essential for a window
/// switcher that must keep reading the Option key state while it is visible.
///
/// ## Show once, update many
/// The panel is driven by a `SwitcherViewModel`. `show(_:)` builds the `NSHostingView` and plays
/// the entrance animation **only on the hidden → visible transition**. While visible, the
/// observable model updates the SwiftUI list in place; the panel does not rebuild the hosting
/// view or replay the animation, so stepping through windows feels smooth instead of flickering.
///
/// ### Typical usage
/// ```swift
/// panel.show(viewModel)   // first Tab: builds + animates in
/// viewModel.selectedIndex = 2   // later Tabs: list updates live, no re-animation
/// panel.dismiss()         // Option released / Esc: animates out
/// ```
@MainActor
final class SwitcherPanel {

    // MARK: - Private state

    private let panel: _FloatingPanel
    /// Retains the hosting view so ARC does not tear it down while visible.
    private var hostingView: _HostingView?
    /// `true` between a successful `show` and the next `dismiss`. Gates the build/animate work.
    private(set) var isVisible = false

    /// Fraction of the visible screen height the list may occupy before it is allowed to scroll.
    /// The panel grows to fit all windows up to this ceiling; only beyond it does scrolling start.
    private static let maxHeightFraction: CGFloat = 0.85

    /// Transparent margin baked around the rounded content inside the hosting view.
    ///
    /// With `hasShadow = false` the only shadow is the SwiftUI one drawn on the content shape, and
    /// SwiftUI shadows render *outside* a view's layout bounds. Without breathing room the panel
    /// would clip its own shadow at the frame edge. This margin (≥ shadow radius + offset) gives
    /// the shadow a transparent canvas so it fades out cleanly on every side.
    /// Sized for the widest panel shadow layer — the ambient shadow (radius 34, y 18 ⇒ ~52pt of
    /// reach) — plus a small safety cushion, so even the soft ambient halo never clips at the frame.
    private static let shadowMargin: CGFloat = 54

    // MARK: - Init

    init() {
        panel = _FloatingPanel()
    }

    // MARK: - Public API

    /// Presents the switcher for `viewModel`.
    ///
    /// On the first call (while hidden) this builds the hosting view, sizes and positions the
    /// panel on the screen under the mouse, and animates it in. If already visible it is a no-op:
    /// the live `@Observable` model is what drives subsequent updates, so there is nothing to
    /// rebuild.
    func show(_ viewModel: SwitcherViewModel) {
        guard !isVisible else { return }

        // Resolve the target screen first: its visible height sets the ceiling we hand to the
        // list, so the list knows how tall it may grow before it must scroll. The shadow margin
        // (top + bottom) is reserved out of that ceiling so the list never overflows the screen.
        let screen = screenContainingMouse() ?? NSScreen.main ?? NSScreen.screens[0]
        let maxListHeight =
            screen.visibleFrame.height * Self.maxHeightFraction - Self.shadowMargin * 2

        // Wrap the list in the transparent shadow margin. The hosting view (and therefore the
        // panel) is sized to the *padded* content, giving the SwiftUI shadow room on every side.
        // `_HostingView` also opts into first-mouse clicks so a row activates on the very first
        // click even though the panel is never the key window (see its definition).
        let hosting = _HostingView(
            rootView: AnyView(
                WindowListView(viewModel: viewModel, maxHeight: maxListHeight)
                    .padding(Self.shadowMargin)
            )
        )
        hosting.translatesAutoresizingMaskIntoConstraints = true
        // The hosting view must not paint an opaque backdrop, or it would fill the transparent
        // margin (re-introducing a square) and hide the rounded shadow.
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor

        hostingView = hosting

        // Size the panel to the padded list's natural fitting size. Because the list no longer
        // imposes a fixed max height, this grows to show every window (capped by `maxListHeight`),
        // so the panel is never clipped and never carries empty space.
        let ideal = hosting.fittingSize
        let size = CGSize(
            width:  max(ideal.width,  240 + Self.shadowMargin * 2),
            height: max(ideal.height,  60 + Self.shadowMargin * 2)
        )
        hosting.frame = CGRect(origin: .zero, size: size)
        panel.contentView = hosting
        panel.setContentSize(size)
        positionOnScreen(screen, size: size)

        isVisible = true
        animateIn()
        panel.orderFrontRegardless()
    }

    /// Hides the panel with a brief fade-out and releases the hosting view.
    func dismiss() {
        guard isVisible else { return }
        isVisible = false
        animateOut {
            self.panel.orderOut(nil)
            self.panel.contentView = nil
            self.hostingView = nil
        }
    }

    // MARK: - Positioning

    /// Positions the panel slightly above the screen's vertical centre (the upper third), where the
    /// eye naturally lands when switching apps. The `+ height * 0.08` nudge is conservative on
    /// purpose: a full third can crowd the top edge once the adaptive panel grows tall on small
    /// displays, so 8% keeps a safe margin while still feeling "up".
    private func positionOnScreen(_ screen: NSScreen, size: CGSize) {
        let visibleFrame = screen.visibleFrame
        let origin = CGPoint(
            x: visibleFrame.midX - size.width  / 2,
            y: visibleFrame.midY - size.height / 2 + visibleFrame.height * 0.08
        )
        panel.setFrameOrigin(origin)
    }

    /// Returns the `NSScreen` whose frame contains the current mouse location.
    private func screenContainingMouse() -> NSScreen? {
        // `NSEvent.mouseLocation` returns screen coordinates (origin = bottom-left of the
        // primary display). `NSScreen.frame` uses the same coordinate system.
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) }
    }

    // MARK: - Animation helpers

    /// Materialises the panel: a spring-driven scale 0.92 → 1.0 (it has *mass*, so it settles with
    /// life) plus a separate, non-bouncing opacity fade (a rebounding alpha looks wrong).
    ///
    /// Under "Reduce Motion" the scale is dropped entirely — a plain fade with no transform.
    private func animateIn() {
        guard let layer = panel.contentView?.layer else { return }
        layer.removeAllAnimations()

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        // Start state (applied instantly, before the run-loop tick).
        layer.opacity = 0
        if !reduceMotion {
            layer.transform = CATransform3DMakeScale(0.92, 0.92, 1)
        }

        // Opacity fades on its own short ease-out curve (independent of the spring).
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = Float(0)
        fade.toValue   = Float(1)
        fade.duration  = 0.13
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(fade, forKey: "fadeIn")
        layer.opacity = 1

        if !reduceMotion {
            // Spring scale: mass 1, stiffness 320, damping 18 — a quick, lightly-damped settle.
            let spring = CASpringAnimation(keyPath: "transform.scale")
            spring.mass = 1
            spring.stiffness = 320
            spring.damping = 18
            spring.initialVelocity = 0
            spring.fromValue = 0.92
            spring.toValue   = 1.0
            // `settlingDuration` isn't exposed in the CLT header, so derive a settle time from the
            // spring parameters: ~ a few time-constants of 2·mass/damping.
            spring.duration = springSettlingDuration(mass: 1, damping: 18)
            layer.add(spring, forKey: "scaleIn")
            layer.transform = CATransform3DIdentity
        }
    }

    /// Approximates a spring's settling time from its physical parameters, since the CLT
    /// `CASpringAnimation` header does not expose `settlingDuration`. The decay time-constant of an
    /// underdamped spring is `2·mass/damping`; ~4 of those reaches visual rest. Clamped to a sane
    /// floor so the animation never reads as instant.
    private func springSettlingDuration(mass: CGFloat, damping: CGFloat) -> CFTimeInterval {
        let timeConstant = (2 * mass) / damping
        return CFTimeInterval(max(timeConstant * 4, 0.3))
    }

    /// Fades the panel out, then runs `completion` when the animation finishes.
    private func animateOut(completion: @escaping @MainActor () -> Void) {
        guard let layer = panel.contentView?.layer else {
            completion()
            return
        }
        layer.removeAllAnimations()

        CATransaction.begin()
        CATransaction.setAnimationDuration(0.10)
        CATransaction.setAnimationTimingFunction(
            CAMediaTimingFunction(name: .easeIn)
        )
        CATransaction.setCompletionBlock {
            // The completion block runs on the main thread (CA guarantee) but is not marked
            // @MainActor, so we hop back explicitly for Swift 6.
            Task { @MainActor in completion() }
        }

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = Float(1)
        fade.toValue   = Float(0)

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1.0
        scale.toValue   = 0.96

        layer.add(fade,  forKey: "fadeOut")
        layer.add(scale, forKey: "scaleOut")
        layer.opacity   = 0
        layer.transform = CATransform3DMakeScale(0.96, 0.96, 1)

        CATransaction.commit()
    }
}

// MARK: - _FloatingPanel

/// Concrete `NSPanel` configured as a non-activating, borderless, floating overlay.
///
/// Prefixed with `_` to signal it is an implementation detail of `SwitcherPanel`.
private final class _FloatingPanel: NSPanel {

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless],
            backing:   .buffered,
            defer:     true
        )

        // Appearance
        level           = .floating
        isOpaque        = false
        backgroundColor = .clear
        // No window shadow: the OS shadow is rectangular (it tracks the panel *frame*, not the
        // rounded content), which is exactly the square halo we want to kill. The rounded shadow
        // is drawn in SwiftUI on the content shape instead (see WindowListView). The panel frame
        // is fully transparent and carries extra margin so that SwiftUI shadow has room to render.
        hasShadow       = false
        isMovable       = false

        // Show on every Space and in full-screen apps.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Enable Core Animation on the content layer so the fade/scale can run.
        contentView?.wantsLayer = true
    }

    /// The panel must never become the key window — doing so would pull focus away from the app
    /// whose Option key state we are monitoring.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - _HostingView

/// `NSHostingView` subclass that accepts first-mouse clicks.
///
/// The switcher panel is intentionally non-activating and never becomes key (it must keep
/// monitoring the Option key). For a window that is not key, AppKit normally treats the first
/// click only as a window-activation click and swallows it — so a row would need *two* clicks to
/// fire. Returning `true` from `acceptsFirstMouse(for:)` makes the very first click act on the
/// row's SwiftUI `onTapGesture` immediately, which is exactly the AltTab click-to-select feel:
/// hold Option with one hand, click a row with the other, and it activates at once.
///
/// Type-erased to `AnyView` so the panel can wrap the list in layout modifiers (the shadow
/// margin) without leaking a concrete generic type into `SwitcherPanel`'s stored property.
private final class _HostingView: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
