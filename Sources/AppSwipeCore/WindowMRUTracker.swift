import CoreGraphics

/// Tracks the most-recently-used (MRU) order of windows, *by window* — not by app.
///
/// ## Why this exists
/// macOS' CoreGraphics z-order is not a per-window usage history: when an app is activated, the
/// window server raises **all** of that app's windows together to the top of the stack. So after
/// jumping to one Chrome window, the *other* Chrome windows sit on top of the window you used
/// just before (say, a Warp terminal). Selecting "the previous window" off the raw z-order would
/// land on a sibling Chrome window, not the terminal you actually alternated with.
///
/// This tracker keeps an explicit, app-agnostic usage history so "alternate the two most recent
/// windows" behaves like Cmd+Tab does for apps — but at the granularity of individual windows.
///
/// ## Model
/// The history is an ordered list of `CGWindowID`s, **front = most recently used**. `touch(_:)`
/// promotes an id to the front; `ordered(_:)` projects a live window list onto that history and,
/// as a side effect, prunes ids that no longer correspond to a live window.
///
/// Pure domain type: depends only on `CoreGraphics` (for `CGWindowID`). No AppKit/SwiftUI.
/// Not thread-safe by design — it is driven from the main thread alongside `SwitcherController`.
public final class WindowMRUTracker {

    /// Usage history, most-recent first. Holds at most one entry per `CGWindowID`.
    private var order: [CGWindowID] = []

    public init() {}

    /// Promotes `id` to the front of the history (the most-recently-used position).
    ///
    /// If `id` is already tracked it is moved (not duplicated); if it is new it is inserted at the
    /// front. Re-touching the current front id is a no-op.
    public func touch(_ id: CGWindowID) {
        if let existing = order.firstIndex(of: id) {
            // Already front: nothing to do (avoids a needless remove+insert).
            guard existing != 0 else { return }
            order.remove(at: existing)
        }
        order.insert(id, at: 0)
    }

    /// Returns `windows` reordered by the usage history.
    ///
    /// Ordering rules:
    /// - Windows present in the history come first, in most-recently-used order.
    /// - Windows absent from the history follow, preserving their original input order.
    ///
    /// Side effect: ids in the history that are **not** present in `windows` (their window has
    /// closed) are pruned, so the history never grows without bound and a closed-then-reopened
    /// window is treated as new (it sorts to the end) rather than resurrecting a stale slot.
    ///
    /// The result is always a permutation of `windows`: same elements, no drops, no additions.
    public func ordered(_ windows: [WindowInfo]) -> [WindowInfo] {
        // Index the live windows by id for O(1) lookup while walking the history.
        var byID: [CGWindowID: WindowInfo] = [:]
        byID.reserveCapacity(windows.count)
        for window in windows {
            byID[window.id] = window
        }

        // Prune history down to ids that still have a live window, preserving MRU order. This is
        // the single place the history is garbage-collected.
        order = order.filter { byID[$0] != nil }

        // Known windows first, in MRU order.
        let knownIDs = Set(order)
        var result: [WindowInfo] = []
        result.reserveCapacity(windows.count)
        for id in order {
            if let window = byID[id] {
                result.append(window)
            }
        }

        // Then the windows the history has never seen, in their original input order.
        for window in windows where !knownIDs.contains(window.id) {
            result.append(window)
        }

        return result
    }
}
