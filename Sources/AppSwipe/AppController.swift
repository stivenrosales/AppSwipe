import AppKit
import CoreGraphics
import AppSwipeCore

/// Composition root and app lifecycle owner.
///
/// Wires the System adapters (`CGWindowEnumerator`, `AXWindowActivator`, `HotKeyMonitor`,
/// `AccessibilityGate`) to the pure domain (`SwitcherController`) and the Presentation layer
/// (`SwitcherPanel` + `WindowListView` + `StatusItemController`). This is the only place where
/// all layers meet; the domain itself stays free of any macOS type.
@MainActor
final class AppController: NSObject, NSApplicationDelegate {

    // MARK: - Collaborators

    private let controller: SwitcherController
    private let hotKeyMonitor: HotKeyMonitor
    private let panel: SwitcherPanel
    private let accessibilityGate = AccessibilityGate()
    private let statusItem = StatusItemController()

    /// Single observable model shared with the SwiftUI list for the whole app lifetime.
    /// Mutating it updates the visible panel in place — no rebuild, no re-animation per Tab.
    private let viewModel = SwitcherViewModel()

    // MARK: - State

    /// `true` while a switcher gesture is in flight (Option held), whether or not the panel has
    /// appeared yet. The panel may still be hidden during the initial delay.
    private var isActive = false

    /// Pending "show the panel" work, scheduled on the first Tab and fired after `panelDelay`.
    /// Cancelled if Option is released first (instant switch, no UI) or if a second Tab arrives
    /// (the user is navigating, so we reveal the panel immediately). `nil` when nothing is pending.
    private var pendingShow: DispatchWorkItem?

    /// How long Option+Tab must be held before the panel appears. A quick tap-and-release switches
    /// windows directly without ever flashing the UI — the AltTab "I know where I'm going" path.
    private static let panelDelay: TimeInterval = 0.2

    // MARK: - Init

    override init() {
        controller = SwitcherController(
            provider: CGWindowEnumerator(),
            activator: AXWindowActivator()
        )
        hotKeyMonitor = HotKeyMonitor()
        panel = SwitcherPanel()
        super.init()
    }

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppPreferences.registerDefaults()
        statusItem.install()
        wireClickToSelect()
        ensureAccessibilityPermission()
        wireHotKeys()
        hotKeyMonitor.start()
    }

    /// Reopening the app — double-clicking it in Finder (or `open`-ing it) while it already runs —
    /// opens Preferences. A reliable path to settings even when the menu-bar icon is hidden by a
    /// menu-bar manager (Ice/Bartender) or pushed off-screen by the notch.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        statusItem.openPreferences()
        return true
    }

    // MARK: - Permission

    /// Requests Accessibility permission on first launch if it is not already granted.
    ///
    /// The global event monitor silently no-ops without this permission, so we prompt the user
    /// and open the relevant Settings pane to guide them through onboarding.
    private func ensureAccessibilityPermission() {
        guard !accessibilityGate.isTrusted() else { return }
        accessibilityGate.requestAccess()
        accessibilityGate.openSettings()
    }

    // MARK: - Click-to-select wiring

    /// Connects a click on a list row to activation. The user keeps Option held with one hand and
    /// clicks a row with the other; the panel is non-activating, so it receives the click without
    /// stealing key focus (and without breaking the Option monitoring). Selecting by click moves
    /// the highlight to that window and commits it, exactly as releasing Option on it would.
    private func wireClickToSelect() {
        viewModel.onSelect = { [weak self] windowID in
            MainActor.assumeIsolated { self?.handleClickSelect(windowID) }
        }
    }

    // MARK: - Hot-key wiring

    /// Maps the raw gesture callbacks onto domain actions and panel presentation.
    ///
    /// The closures capture `self` weakly to avoid a retain cycle (the monitor is owned by
    /// `self`). Each callback runs on the main thread (`NSEvent` delivery guarantee), so the
    /// `@MainActor`-isolated state is touched safely without hopping.
    private func wireHotKeys() {
        hotKeyMonitor.onNext = { [weak self] in
            MainActor.assumeIsolated { self?.handleNext() }
        }
        hotKeyMonitor.onPrevious = { [weak self] in
            MainActor.assumeIsolated { self?.handlePrevious() }
        }
        hotKeyMonitor.onConfirm = { [weak self] in
            MainActor.assumeIsolated { self?.handleConfirm() }
        }
        hotKeyMonitor.onCancel = { [weak self] in
            MainActor.assumeIsolated { self?.handleCancel() }
        }
    }

    // MARK: - Gesture handlers

    /// Tab handling, in three cases:
    /// - **First Tab (no gesture yet):** load the window list and *schedule* the panel after a
    ///   short delay instead of showing it now. A fast tap-and-release then switches with no UI.
    /// - **Second Tab before the panel is shown:** the user is clearly navigating, so reveal the
    ///   panel immediately and advance the selection.
    /// - **Tab while the panel is visible:** just advance the selection (updates the panel in
    ///   place via the observable model).
    private func handleNext() {
        if isActive {
            // Navigating: if the panel has not appeared yet (still within the delay), the second
            // Tab is the signal to reveal it now.
            revealPanelIfPending()
            controller.selectNext()
            syncViewModel()
        } else {
            controller.start()
            guard !controller.windows.isEmpty else { return }  // zero windows: stay hidden
            isActive = true
            syncViewModel()
            schedulePanel()
        }
    }

    /// Shift+Tab moves the selection backwards. Ignored when no gesture is in flight. Like a second
    /// Tab, it reveals a still-pending panel — the user is navigating.
    private func handlePrevious() {
        guard isActive else { return }
        revealPanelIfPending()
        controller.selectPrevious()
        syncViewModel()
    }

    /// Option released: commit the highlighted window and tear everything down. If the panel was
    /// never shown (released within the delay), this is an instant, UI-less switch.
    private func handleConfirm() {
        guard isActive else { return }
        controller.confirm()
        endGesture()
    }

    /// Esc: abort without activating anything and tear everything down.
    private func handleCancel() {
        guard isActive else { return }
        controller.cancel()
        endGesture()
    }

    /// A row was clicked: select that window and commit it, then dismiss. Works whether or not the
    /// delay has elapsed — a click is an explicit, immediate choice.
    private func handleClickSelect(_ windowID: CGWindowID) {
        guard isActive else { return }
        controller.select(windowID: windowID)
        controller.confirm()
        endGesture()
    }

    // MARK: - Panel scheduling

    /// Schedules the panel to appear after `panelDelay`, cancelling any previously pending show.
    private func schedulePanel() {
        pendingShow?.cancel()

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // Only show if the gesture is still live and the panel is not already up. If Option
            // was released in the meantime the work item may still fire before it was cancelled.
            guard self.isActive, !self.panel.isVisible else { return }
            self.panel.show(self.viewModel)
        }
        pendingShow = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.panelDelay, execute: work)
    }

    /// If a delayed show is still pending, cancel it and show the panel right now. No-op once the
    /// panel is already visible.
    private func revealPanelIfPending() {
        guard pendingShow != nil else { return }
        pendingShow?.cancel()
        pendingShow = nil
        if !panel.isVisible {
            panel.show(viewModel)
        }
    }

    // MARK: - Presentation

    /// Mirrors the pure controller state into the observable model the panel renders.
    private func syncViewModel() {
        viewModel.windows = controller.windows
        viewModel.selectedIndex = controller.selectedIndex
    }

    /// Cancels any pending show, dismisses the panel, and resets gesture state.
    private func endGesture() {
        pendingShow?.cancel()
        pendingShow = nil
        panel.dismiss()
        isActive = false
    }
}
