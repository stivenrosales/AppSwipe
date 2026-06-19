import Testing
import CoreGraphics
@testable import AppSwipeCore

// NOTE: XCTest is not available in this Command Line Tools-only macOS environment
// (XCTest ships with Xcode, which is not installed). Swift Testing is the supported
// framework here and is what the package's test target is wired for — same approach as
// SwitcherControllerTests. The scenarios are exactly those specified for the MRU tracker:
// touch moves to front; ordered respects the MRU; new windows go to the end; vanished
// ids are pruned; A→B→A alternation.

// MARK: - Fixtures

private func makeWindow(_ id: CGWindowID) -> WindowInfo {
    WindowInfo(
        id: id,
        title: "Window \(id)",
        appName: "App \(id)",
        pid: pid_t(id)
    )
}

// MARK: - touch()

@Suite("WindowMRUTracker.touch")
struct WindowMRUTrackerTouchTests {

    @Test("touch on an empty tracker records the id as most recent")
    func touchOnEmpty() {
        let tracker = WindowMRUTracker()

        tracker.touch(1)

        // Ordering a single matching window keeps it; proves the id was recorded.
        #expect(tracker.ordered([makeWindow(1)]) == [makeWindow(1)])
    }

    @Test("touch moves an existing id to the front")
    func touchMovesToFront() {
        let tracker = WindowMRUTracker()
        let windows = [makeWindow(1), makeWindow(2), makeWindow(3)]

        tracker.touch(1)
        tracker.touch(2)
        tracker.touch(3)
        // 3 is most recent, 1 is least. Now re-touch 1: it must jump to the front.
        tracker.touch(1)

        #expect(tracker.ordered(windows).map(\.id) == [1, 3, 2])
    }

    @Test("re-touching the front id is a no-op on the ordering")
    func touchFrontIsIdempotent() {
        let tracker = WindowMRUTracker()
        let windows = [makeWindow(1), makeWindow(2)]

        tracker.touch(2)
        tracker.touch(1) // 1 is now front
        tracker.touch(1) // touching it again must not change anything

        #expect(tracker.ordered(windows).map(\.id) == [1, 2])
    }

    @Test("touch does not duplicate an id already present")
    func touchDoesNotDuplicate() {
        let tracker = WindowMRUTracker()
        // Only one window (id 1) exists. Touch it several times, interleaved with id 2.
        tracker.touch(1)
        tracker.touch(2)
        tracker.touch(1)
        tracker.touch(1)

        // Order id 1 alone: if it had been duplicated, pruning still yields a single entry.
        #expect(tracker.ordered([makeWindow(1)]).map(\.id) == [1])
        // And both together keep a single slot each, 1 in front.
        #expect(tracker.ordered([makeWindow(1), makeWindow(2)]).map(\.id) == [1, 2])
    }
}

// MARK: - ordered()

@Suite("WindowMRUTracker.ordered")
struct WindowMRUTrackerOrderedTests {

    @Test("with no history, ordered preserves the input order")
    func emptyHistoryPreservesInput() {
        let tracker = WindowMRUTracker()
        let windows = [makeWindow(10), makeWindow(20), makeWindow(30)]

        #expect(tracker.ordered(windows) == windows)
    }

    @Test("ordered returns windows in MRU order")
    func ordersByMRU() {
        let tracker = WindowMRUTracker()
        let windows = [makeWindow(1), makeWindow(2), makeWindow(3)]

        tracker.touch(1)
        tracker.touch(3)
        tracker.touch(2) // MRU front-to-back: 2, 3, 1

        #expect(tracker.ordered(windows).map(\.id) == [2, 3, 1])
    }

    @Test("windows absent from the history go to the end, keeping input order")
    func newWindowsGoToEnd() {
        let tracker = WindowMRUTracker()
        // History knows only 2 and 4.
        tracker.touch(4)
        tracker.touch(2) // MRU: 2, 4

        // Input also carries brand-new windows 1, 3, 5 (never touched).
        let windows = [makeWindow(1), makeWindow(2), makeWindow(3), makeWindow(4), makeWindow(5)]

        // Known ones first in MRU order (2, 4), then the unknowns in their input order (1, 3, 5).
        #expect(tracker.ordered(windows).map(\.id) == [2, 4, 1, 3, 5])
    }

    @Test("ordered keeps exactly the input windows (no drops, no additions)")
    func orderedIsAPermutationOfInput() {
        let tracker = WindowMRUTracker()
        tracker.touch(2)
        tracker.touch(1)

        let windows = [makeWindow(1), makeWindow(2), makeWindow(3)]
        let result = tracker.ordered(windows)

        #expect(result.count == windows.count)
        #expect(Set(result.map(\.id)) == Set(windows.map(\.id)))
    }

    @Test("ids no longer present are pruned from the history")
    func prunesVanishedIDs() {
        let tracker = WindowMRUTracker()
        tracker.touch(1)
        tracker.touch(2)
        tracker.touch(3) // MRU: 3, 2, 1

        // Window 3 has since closed: it is not in the current set. Ordering the survivors must
        // not crash and must not leave a ghost slot.
        let survivors = [makeWindow(1), makeWindow(2)]
        #expect(tracker.ordered(survivors).map(\.id) == [2, 1])

        // After pruning, if 3 reappears as a *new* window it is treated as unknown (goes last),
        // because its old history entry was dropped.
        let reappeared = [makeWindow(2), makeWindow(1), makeWindow(3)]
        #expect(tracker.ordered(reappeared).map(\.id) == [2, 1, 3])
    }
}

// MARK: - Alternation (the core use case)

@Suite("WindowMRUTracker.alternation")
struct WindowMRUTrackerAlternationTests {

    @Test("A then B then A alternates between the two most-recent windows")
    func alternateABA() {
        let tracker = WindowMRUTracker()
        let a = makeWindow(100)
        let b = makeWindow(200)
        let windows = [a, b]

        // Use A, then use B.
        tracker.touch(a.id)
        tracker.touch(b.id)
        // MRU front is B, previous is A.
        #expect(tracker.ordered(windows).map(\.id) == [b.id, a.id])

        // Switch back to A.
        tracker.touch(a.id)
        // MRU front is A, previous is B — we have alternated.
        #expect(tracker.ordered(windows).map(\.id) == [a.id, b.id])

        // And again to B.
        tracker.touch(b.id)
        #expect(tracker.ordered(windows).map(\.id) == [b.id, a.id])
    }

    @Test("alternation ignores unrelated windows that sit between the two in the input")
    func alternationIgnoresWindowsInBetween() {
        let tracker = WindowMRUTracker()
        // a = Warp, b = a Chrome window, plus other Chrome windows c, d that the z-order would
        // pile up between them. The MRU must still put the *previously used* window at index 1.
        let a = makeWindow(1)   // Warp
        let b = makeWindow(2)   // Chrome window we alternate with
        let c = makeWindow(3)   // other Chrome window
        let d = makeWindow(4)   // other Chrome window

        tracker.touch(a.id)
        tracker.touch(b.id) // MRU: b, a

        // The provider hands them back z-order-style with the other Chrome windows wedged in
        // between b and a: [b, c, d, a].
        let zOrder = [b, c, d, a]

        let result = tracker.ordered(zOrder)
        // Index 0 is the current (b); index 1 must be the previous *used* window (a), NOT c/d.
        #expect(result.map(\.id) == [b.id, a.id, c.id, d.id])
        #expect(result[1].id == a.id)
    }
}
