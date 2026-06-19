import Testing
import CoreGraphics
@testable import AppSwipeCore

// NOTE: XCTest is not available in this Command Line Tools-only macOS environment
// (XCTest ships with Xcode, which is not installed). Swift Testing is the supported
// framework here and is what the package's test target is wired for. The test
// scenarios and the stub/spy mock approach are exactly as specified.

// MARK: - Test Doubles

/// Stub provider: returns a fixed window list (already ordered frontmost-first / MRU).
private final class StubWindowProvider: WindowProvider {
    private let windows: [WindowInfo]

    init(_ windows: [WindowInfo]) {
        self.windows = windows
    }

    func currentWindows() -> [WindowInfo] {
        windows
    }
}

/// Spy activator: records every window passed to `activate`.
private final class SpyWindowActivator: WindowActivator {
    private(set) var activated: [WindowInfo] = []

    func activate(_ window: WindowInfo) {
        activated.append(window)
    }
}

/// Mutable provider: the window list it returns can be swapped between `start()` calls, used to
/// simulate the z-order changing because the user activated a different window.
private final class MutableWindowProvider: WindowProvider {
    var windows: [WindowInfo]

    init(_ windows: [WindowInfo]) {
        self.windows = windows
    }

    func currentWindows() -> [WindowInfo] {
        windows
    }
}

// MARK: - Fixtures

private func makeWindow(_ id: CGWindowID) -> WindowInfo {
    WindowInfo(
        id: id,
        title: "Window \(id)",
        appName: "App \(id)",
        pid: pid_t(id)
    )
}

private func makeWindows(_ count: Int) -> [WindowInfo] {
    (0..<count).map { makeWindow(CGWindowID($0)) }
}

// MARK: - start()

@Suite("SwitcherController.start")
struct SwitcherControllerStartTests {

    @Test("zero windows -> empty, index 0, no selection")
    func startWithZeroWindows() {
        let controller = SwitcherController(
            provider: StubWindowProvider([]),
            activator: SpyWindowActivator()
        )

        controller.start()

        #expect(controller.windows.isEmpty)
        #expect(controller.selectedIndex == 0)
        #expect(controller.selectedWindow == nil)
    }

    @Test("one window -> selects index 0")
    func startWithOneWindow() {
        let windows = makeWindows(1)
        let controller = SwitcherController(
            provider: StubWindowProvider(windows),
            activator: SpyWindowActivator()
        )

        controller.start()

        #expect(controller.windows == windows)
        #expect(controller.selectedIndex == 0)
        #expect(controller.selectedWindow == windows[0])
    }

    @Test("two windows -> selects previous window at index 1")
    func startWithTwoWindows() {
        let windows = makeWindows(2)
        let controller = SwitcherController(
            provider: StubWindowProvider(windows),
            activator: SpyWindowActivator()
        )

        controller.start()

        #expect(controller.selectedIndex == 1)
        #expect(controller.selectedWindow == windows[1])
    }

    @Test("many windows -> selects previous window at index 1")
    func startWithManyWindows() {
        let windows = makeWindows(5)
        let controller = SwitcherController(
            provider: StubWindowProvider(windows),
            activator: SpyWindowActivator()
        )

        controller.start()

        #expect(controller.windows.count == 5)
        #expect(controller.selectedIndex == 1)
        #expect(controller.selectedWindow == windows[1])
    }

    @Test("start reloads windows and resets selection to the previous-window slot")
    func startReloadsAndResets() {
        let windows = makeWindows(3)
        let controller = SwitcherController(
            provider: StubWindowProvider(windows),
            activator: SpyWindowActivator()
        )

        controller.start()
        controller.selectNext() // move selection away from the start position
        controller.start()       // restart should reset to the previous-window slot

        #expect(controller.selectedIndex == 1)
    }
}

// MARK: - selectNext()

@Suite("SwitcherController.selectNext")
struct SwitcherControllerSelectNextTests {

    @Test("advances selection downward")
    func advancesSelection() {
        let windows = makeWindows(3)
        let controller = SwitcherController(
            provider: StubWindowProvider(windows),
            activator: SpyWindowActivator()
        )
        controller.start() // selectedIndex == 1

        controller.selectNext()

        #expect(controller.selectedIndex == 2)
        #expect(controller.selectedWindow == windows[2])
    }

    @Test("wraps around from last to first")
    func wrapsAroundFromLastToFirst() {
        let windows = makeWindows(3)
        let controller = SwitcherController(
            provider: StubWindowProvider(windows),
            activator: SpyWindowActivator()
        )
        controller.start()       // index 1
        controller.selectNext()  // index 2 (last)

        controller.selectNext()  // wrap -> 0

        #expect(controller.selectedIndex == 0)
        #expect(controller.selectedWindow == windows[0])
    }

    @Test("no-op on empty windows")
    func noOpOnEmpty() {
        let controller = SwitcherController(
            provider: StubWindowProvider([]),
            activator: SpyWindowActivator()
        )
        controller.start()

        controller.selectNext()

        #expect(controller.selectedIndex == 0)
        #expect(controller.windows.isEmpty)
    }
}

// MARK: - selectPrevious()

@Suite("SwitcherController.selectPrevious")
struct SwitcherControllerSelectPreviousTests {

    @Test("moves selection backward")
    func movesSelectionBackward() {
        let windows = makeWindows(3)
        let controller = SwitcherController(
            provider: StubWindowProvider(windows),
            activator: SpyWindowActivator()
        )
        controller.start() // index 1

        controller.selectPrevious()

        #expect(controller.selectedIndex == 0)
        #expect(controller.selectedWindow == windows[0])
    }

    @Test("wraps around from first to last")
    func wrapsAroundFromFirstToLast() {
        let windows = makeWindows(3)
        let controller = SwitcherController(
            provider: StubWindowProvider(windows),
            activator: SpyWindowActivator()
        )
        controller.start()           // index 1
        controller.selectPrevious()  // index 0 (first)

        controller.selectPrevious()  // wrap -> 2 (last)

        #expect(controller.selectedIndex == 2)
        #expect(controller.selectedWindow == windows[2])
    }

    @Test("no-op on empty windows")
    func noOpOnEmpty() {
        let controller = SwitcherController(
            provider: StubWindowProvider([]),
            activator: SpyWindowActivator()
        )
        controller.start()

        controller.selectPrevious()

        #expect(controller.selectedIndex == 0)
        #expect(controller.windows.isEmpty)
    }
}

// MARK: - confirm()

@Suite("SwitcherController.confirm")
struct SwitcherControllerConfirmTests {

    @Test("activates the currently selected window")
    func activatesSelectedWindow() {
        let windows = makeWindows(3)
        let spy = SpyWindowActivator()
        let controller = SwitcherController(
            provider: StubWindowProvider(windows),
            activator: spy
        )
        controller.start() // selectedIndex == 1

        controller.confirm()

        #expect(spy.activated == [windows[1]])
    }

    @Test("activates the correct window after navigation")
    func activatesCorrectWindowAfterNavigation() {
        let windows = makeWindows(4)
        let spy = SpyWindowActivator()
        let controller = SwitcherController(
            provider: StubWindowProvider(windows),
            activator: spy
        )
        controller.start()      // index 1
        controller.selectNext() // index 2
        controller.selectNext() // index 3

        controller.confirm()

        #expect(spy.activated.count == 1)
        #expect(spy.activated.first == windows[3])
    }

    @Test("does not activate when there are no windows")
    func doesNotActivateWhenEmpty() {
        let spy = SpyWindowActivator()
        let controller = SwitcherController(
            provider: StubWindowProvider([]),
            activator: spy
        )
        controller.start()

        controller.confirm()

        #expect(spy.activated.isEmpty)
    }
}

// MARK: - cancel()

@Suite("SwitcherController.cancel")
struct SwitcherControllerCancelTests {

    @Test("does not activate anything")
    func doesNotActivate() {
        let windows = makeWindows(3)
        let spy = SpyWindowActivator()
        let controller = SwitcherController(
            provider: StubWindowProvider(windows),
            activator: spy
        )
        controller.start()

        controller.cancel()

        #expect(spy.activated.isEmpty)
    }

    @Test("does not mutate the window list")
    func doesNotMutateWindows() {
        let windows = makeWindows(3)
        let controller = SwitcherController(
            provider: StubWindowProvider(windows),
            activator: SpyWindowActivator()
        )
        controller.start()

        controller.cancel()

        #expect(controller.windows == windows)
    }
}

// MARK: - select(windowID:)

/// Direct selection by window id, used by the click-to-select interaction: the Presentation
/// layer reports which row was clicked and the controller moves the highlight to it (then the
/// caller confirms). Pure index math — no activation happens here.
@Suite("SwitcherController.selectWindowID")
struct SwitcherControllerSelectWindowIDTests {

    @Test("moves the selection to the window with the given id")
    func selectsExistingID() {
        let windows = makeWindows(4) // ids 0..3
        let controller = SwitcherController(
            provider: StubWindowProvider(windows),
            activator: SpyWindowActivator()
        )
        controller.start() // index 1

        controller.select(windowID: 3)

        #expect(controller.selectedIndex == 3)
        #expect(controller.selectedWindow == windows[3])
    }

    @Test("is a no-op when the id is not present")
    func ignoresMissingID() {
        let windows = makeWindows(3) // ids 0..2
        let controller = SwitcherController(
            provider: StubWindowProvider(windows),
            activator: SpyWindowActivator()
        )
        controller.start() // index 1

        controller.select(windowID: 99) // not in the list

        #expect(controller.selectedIndex == 1) // unchanged
    }

    @Test("confirm after select activates the clicked window")
    func selectThenConfirmActivatesClickedWindow() {
        let windows = makeWindows(4)
        let spy = SpyWindowActivator()
        let controller = SwitcherController(
            provider: StubWindowProvider(windows),
            activator: spy
        )
        controller.start()

        controller.select(windowID: 2)
        controller.confirm()

        #expect(spy.activated == [windows[2]])
    }
}

// MARK: - MRU integration

/// Behaviour added by the per-window MRU: `start()` reconciles the real frontmost window and
/// orders by usage history; `confirm()` records the activated window as most-recent. Together
/// these give true window-level A↔B alternation that ignores sibling windows the z-order piles
/// on top of the previously used one.
@Suite("SwitcherController.mru")
struct SwitcherControllerMRUTests {

    /// Window 1 = Warp; 2 = the Chrome window we alternate with; 3,4 = other Chrome windows that
    /// the z-order wedges on top of Warp after Chrome is activated.
    private func warpAndChrome() -> (warp: WindowInfo, chrome: WindowInfo, others: [WindowInfo]) {
        (makeWindow(1), makeWindow(2), [makeWindow(3), makeWindow(4)])
    }

    @Test("first start orders straight off the z-order (empty history)")
    func firstStartPreservesZOrder() {
        let windows = makeWindows(4)
        let controller = SwitcherController(
            provider: StubWindowProvider(windows),
            activator: SpyWindowActivator()
        )

        controller.start()

        // With no prior history the MRU is a no-op beyond touching the frontmost: order is the
        // z-order, so index 1 is the second z-order window.
        #expect(controller.windows == windows)
        #expect(controller.selectedIndex == 1)
        #expect(controller.selectedWindow == windows[1])
    }

    @Test("confirm marks the activated window most-recent so the next start offers the prior one")
    func confirmRecordsMostRecentForAlternation() {
        let (warp, chrome, others) = warpAndChrome()
        // Provider can change between gestures to mirror the live z-order.
        let provider = MutableWindowProvider([warp, chrome] + others)
        let controller = SwitcherController(
            provider: provider,
            activator: SpyWindowActivator()
        )

        // Gesture 1: from Warp (frontmost), pick the previous slot (index 1 == chrome) and confirm.
        controller.start()
        #expect(controller.selectedWindow == chrome)
        controller.confirm() // MRU now: chrome, warp

        // The user is now in Chrome, which also raised its sibling windows. The z-order the
        // provider reports is [chrome, other3, other4, warp] — Warp is buried.
        provider.windows = [chrome, others[0], others[1], warp]

        // Gesture 2: starting from Chrome must offer *Warp* as the previous window (index 1),
        // NOT a sibling Chrome window, because the MRU remembers Warp was used just before.
        controller.start()
        #expect(controller.selectedIndex == 1)
        #expect(controller.selectedWindow == warp)
    }

    @Test("A -> B -> A alternation lands back on A's prior window each time")
    func fullAlternationCycle() {
        let a = makeWindow(10)
        let b = makeWindow(20)
        let provider = MutableWindowProvider([a, b])
        let spy = SpyWindowActivator()
        let controller = SwitcherController(provider: provider, activator: spy)

        // Start in A, jump to B.
        controller.start()                       // frontmost a; index 1 == b
        #expect(controller.selectedWindow == b)
        controller.confirm()                      // activate b; MRU: b, a
        provider.windows = [b, a]                 // b now frontmost

        // Start in B, jump back to A.
        controller.start()                        // frontmost b; index 1 == a
        #expect(controller.selectedWindow == a)
        controller.confirm()                      // activate a; MRU: a, b
        provider.windows = [a, b]                 // a now frontmost

        // Start in A again, previous is B once more.
        controller.start()
        #expect(controller.selectedWindow == b)

        #expect(spy.activated.map(\.id) == [b.id, a.id])
    }

    @Test("start reconciles an external activation (user clicked a window directly)")
    func startReconcilesExternalActivation() {
        let (warp, chrome, others) = warpAndChrome()
        let provider = MutableWindowProvider([warp, chrome] + others)
        let controller = SwitcherController(
            provider: provider,
            activator: SpyWindowActivator()
        )

        // First gesture establishes some history: warp is frontmost, MRU touches it.
        controller.start() // MRU: warp

        // The user then clicks one of the other windows directly (no switcher involved). The
        // window server now reports it as frontmost.
        let clicked = others[1] // window 4
        provider.windows = [clicked, warp, chrome, others[0]]

        // Next start must reconcile: the clicked window is treated as most-recent (index 0), and
        // the previously used window (warp) becomes the index-1 "previous" slot.
        controller.start()
        #expect(controller.selectedWindow == warp)
        #expect(controller.windows.first == clicked)
    }

    @Test("MRU survives Shift+Tab navigation when confirming a different window")
    func confirmAfterNavigationUpdatesMRU() {
        let windows = makeWindows(4) // ids 0,1,2,3
        let provider = MutableWindowProvider(windows)
        let controller = SwitcherController(provider: provider, activator: SpyWindowActivator())

        controller.start()       // frontmost id 0; index 1 == id 1
        controller.selectNext()  // index 2 == id 2
        controller.confirm()     // activate id 2 -> MRU front is id 2

        // Reflect that id 2 is now frontmost.
        provider.windows = [windows[2], windows[0], windows[1], windows[3]]

        controller.start()
        // Most-recent is id 2; previous used was id 0 (the frontmost at the first start). So
        // index 1 should be id 0.
        #expect(controller.windows.first?.id == 2)
        #expect(controller.selectedWindow?.id == 0)
    }
}
