import CoreGraphics

/// Pure navigation state for the window switcher.
///
/// Holds no macOS types: it talks to the system only through the `WindowProvider` and
/// `WindowActivator` ports, which makes the whole selection/navigation logic testable
/// without opening a single real window.
///
/// ## Per-window MRU
/// The provider returns windows in CoreGraphics z-order, but z-order is *not* a per-window
/// usage history (activating an app raises all of its windows together). To make "alternate the
/// two most-recently-used windows" work at window granularity — like Cmd+Tab does for apps — the
/// controller keeps its own `WindowMRUTracker` and orders the provider's list through it. See
/// `WindowMRUTracker` for the full rationale.
public final class SwitcherController {
    private let provider: WindowProvider
    private let activator: WindowActivator
    private let mru: WindowMRUTracker

    /// Windows loaded on the most recent `start()`, in **MRU order** (most-recently-used first).
    public private(set) var windows: [WindowInfo] = []
    /// Index of the currently highlighted window. `0` when `windows` is empty.
    public private(set) var selectedIndex: Int = 0

    public init(
        provider: WindowProvider,
        activator: WindowActivator,
        mru: WindowMRUTracker = WindowMRUTracker()
    ) {
        self.provider = provider
        self.activator = activator
        self.mru = mru
    }

    /// The currently highlighted window, or `nil` when there are no windows.
    public var selectedWindow: WindowInfo? {
        guard windows.indices.contains(selectedIndex) else { return nil }
        return windows[selectedIndex]
    }

    /// Loads the window list and positions the selection.
    ///
    /// Steps:
    /// 1. Ask the provider for the current windows (CoreGraphics z-order, frontmost first).
    /// 2. `touch` the real frontmost window (z-order index 0) into the MRU. This **reconciles**
    ///    activations that happened outside the switcher (the user clicked a window directly), so
    ///    our history always agrees with what is actually on top before we compute an order.
    /// 3. Reorder the windows through the MRU so index 0 is the current window and index 1 is the
    ///    window the user actually used before — not whichever sibling the z-order piled on top.
    ///
    /// With two or more windows the selection lands on index 1 — the previously used window — so a
    /// quick Option+Tab+release jumps straight to it. With one window it lands on index 0; with
    /// none, the list stays empty and the index is 0.
    public func start() {
        let zOrdered = provider.currentWindows()

        // Reconcile external activations: whatever the window server currently has on top is, by
        // definition, the most-recently-used window right now.
        if let frontmost = zOrdered.first {
            mru.touch(frontmost.id)
        }

        windows = mru.ordered(zOrdered)
        selectedIndex = windows.count >= 2 ? 1 : 0
    }

    /// Moves the selection down one row, wrapping past the end. No-op when empty.
    public func selectNext() {
        guard !windows.isEmpty else { return }
        selectedIndex = (selectedIndex + 1) % windows.count
    }

    /// Moves the selection up one row, wrapping past the start. No-op when empty.
    public func selectPrevious() {
        guard !windows.isEmpty else { return }
        selectedIndex = (selectedIndex - 1 + windows.count) % windows.count
    }

    /// Moves the highlight directly to the window with `windowID`. No-op if no loaded window has
    /// that id. Used by click-to-select: the Presentation layer reports the clicked row's window
    /// id, the controller highlights it, and the caller then `confirm()`s to activate it.
    public func select(windowID: CGWindowID) {
        guard let index = windows.firstIndex(where: { $0.id == windowID }) else { return }
        selectedIndex = index
    }

    /// Activates the selected window through the activator port. No-op when empty.
    ///
    /// Before activating, the selected window is `touch`ed into the MRU so it becomes the most
    /// recent — this is what makes the *next* `start()` offer the window we are leaving as the
    /// "previous" one, giving true A↔B alternation.
    public func confirm() {
        guard let window = selectedWindow else { return }
        mru.touch(window.id)
        activator.activate(window)
    }

    /// Dismisses the switcher without activating or mutating the window list or the MRU history.
    public func cancel() {
        // Intentionally does not touch `windows`, the MRU, or call the activator.
    }
}
