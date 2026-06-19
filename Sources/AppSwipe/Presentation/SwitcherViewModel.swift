import Observation
import CoreGraphics
import AppSwipeCore

/// Observable presentation state for the switcher list.
///
/// This is the single source of truth the SwiftUI list reads from while the panel is visible.
/// Because it is `@Observable`, mutating `windows` or `selectedIndex` updates the live view
/// in place — no need to rebuild the hosting view or re-run the show animation on every Tab.
/// `AppController` mirrors the pure `SwitcherController` state into this model on each step.
///
/// ## Click-to-select
/// `onSelect` is the bridge from a mouse click on a row back to the controller. The list calls it
/// with the clicked window's `CGWindowID`; `AppController` wires it to activate that window and
/// tear the panel down. It is a plain closure (not `@Observable` state) so reassigning it never
/// triggers a view update — it is wired once when the model is created.
@MainActor
@Observable
final class SwitcherViewModel {
    /// Windows to display, in MRU order (frontmost first).
    var windows: [WindowInfo] = []
    /// Index of the highlighted row.
    var selectedIndex: Int = 0

    /// Invoked when the user clicks a row. Carries the clicked window's id. Set by `AppController`.
    @ObservationIgnored
    var onSelect: ((CGWindowID) -> Void)?
}
