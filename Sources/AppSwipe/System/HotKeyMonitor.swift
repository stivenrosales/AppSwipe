import AppKit
import Carbon.HIToolbox
import CoreGraphics

/// Detects the Cmd+Tab switcher gesture and reports it through closures.
///
/// Gesture semantics:
/// - While Command (`.maskCommand`) is held, each Tab press confirms "next" (or "previous"
///   when Shift is also held).
/// - Releasing Command confirms the current selection.
/// - Esc cancels. Consuming the Cmd+Tab keyDown at the head of the session tap also suppresses
///   the native macOS app switcher (the Dock never receives the event).
///
/// This is a System-layer adapter: it knows NOTHING about the domain. It only emits intent
/// through the public closures (`onNext`, `onPrevious`, `onConfirm`, `onCancel`). Wiring those
/// closures to a `SwitcherController` is the caller's responsibility.
///
/// ## Why a CGEventTap (and not an NSEvent monitor)
/// A global `NSEvent` monitor only *observes* events — the Tab keystroke still reaches the
/// frontmost application, so navigating the switcher also fires Tab inside whatever app is
/// active (moving focus, inserting tabs, etc.). A session-level `CGEventTap` installed at the
/// head of the chain can *consume* the event by returning `nil`, so the Tab never leaks. We use
/// that here: Tab and Esc (while the gesture is live) are swallowed; everything else passes
/// through untouched.
///
/// ### The two non-negotiable rules of an event tap
/// 1. **Re-arm after disable.** The system disables a tap if its callback is too slow
///    (`kCGEventTapDisabledByTimeout`) or after certain user input
///    (`kCGEventTapDisabledByUserInput`). If we do not call `CGEvent.tapEnable(…, enable: true)`
///    in response, the tap stays dead and the gesture silently stops working.
/// 2. **Always return the event you do not consume.** Dropping (returning `nil` for) an event we
///    did not mean to swallow would make keystrokes vanish system-wide. Every branch that is not
///    an explicit consume returns the event unchanged.
///
/// We deliberately do **not** consume `flagsChanged`: returning `nil` there would corrupt the
/// system's view of the modifier state. We only read it to detect the Option release.
///
/// - Note: A session event tap requires Accessibility permission. This type assumes the
///   permission is already granted; granting it is handled elsewhere (`AccessibilityGate`). The
///   session tap rides on that permission and needs no separate Input-Monitoring grant.
/// - Note: Not thread-safe. Create, `start()`, and `stop()` on the main thread — the tap is added
///   to the current (main) run loop and its callback fires there.
public final class HotKeyMonitor {

    // MARK: - Public callbacks

    /// Called when the user advances the selection (Tab while Option is held).
    public var onNext: (() -> Void)?

    /// Called when the user moves the selection backwards (Shift+Tab while Option is held).
    public var onPrevious: (() -> Void)?

    /// Called when the user commits the selection (Option released after a gesture).
    public var onConfirm: (() -> Void)?

    /// Called when the user aborts the gesture (Esc).
    public var onCancel: (() -> Void)?

    // MARK: - Private state

    /// The installed event tap (a Mach port wrapped as a `CFMachPort`). `nil` while stopped.
    private var eventTap: CFMachPort?
    /// Run-loop source backing `eventTap`; retained so we can remove it on `stop()`.
    private var runLoopSource: CFRunLoopSource?

    /// `true` once a gesture has begun (Option held + at least one Tab) and is still in flight.
    /// Drives the "Option released ⇒ confirm" transition and is cleared on confirm/cancel.
    private var active = false

    // MARK: - Lifecycle

    public init() {}

    deinit {
        stop()
    }

    /// Installs the session event tap and adds it to the current run loop. Idempotent.
    ///
    /// If tap creation fails (almost always missing Accessibility permission) this is a no-op:
    /// the gesture simply will not fire until the permission is granted and `start()` is retried.
    public func start() {
        guard eventTap == nil else { return }

        // We care about key presses (Tab / Esc) and modifier changes (Option release).
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        // `passUnretained`: the tap lives as long as `self` does, and `self` owns the tap, so no
        // ownership transfer is needed. We must NOT release this in the callback.
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: hotKeyEventTapCallback,
            userInfo: refcon
        ) else {
            // Tap creation failed (e.g. Accessibility not yet trusted). Leave everything nil.
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = source
    }

    /// Tears the tap down: disables it, removes its run-loop source, invalidates the Mach port,
    /// and clears the gesture state. Idempotent. Does not reset callbacks.
    public func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
        if let eventTap {
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }
        active = false
    }

    // MARK: - Event handling

    /// Re-enables the tap after the system disabled it. Without this the tap dies on the first
    /// timeout or interrupting user input and the gesture stops working.
    fileprivate func reenableTap() {
        guard let eventTap else { return }
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    /// Core decision point, called from the C callback.
    ///
    /// Returns `nil` to **consume** the event (it never reaches the active app) or the event
    /// itself to let it pass through. Every non-consuming path returns the event unchanged.
    fileprivate func handle(
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        switch type {
        case .keyDown:
            return handleKeyDown(event)

        case .flagsChanged:
            handleFlagsChanged(event)
            // Never consume modifier changes: doing so corrupts the system modifier state.
            return Unmanaged.passUnretained(event)

        default:
            // Includes any event types we did not register for. Pass through untouched.
            return Unmanaged.passUnretained(event)
        }
    }

    /// Handles a key-down. Consumes (returns `nil`) only the keys that drive the gesture; every
    /// other key is passed through so normal typing is never swallowed.
    private func handleKeyDown(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        switch keyCode {
        case kVK_Tab where flags.contains(.maskCommand):
            // Cmd+Tab: start (or advance) the gesture and swallow the Tab so it never reaches the
            // active app AND so the native macOS app switcher does not appear — consuming the
            // keyDown at the head of the session tap pre-empts the Dock's Cmd+Tab handling.
            active = true
            if flags.contains(.maskShift) {
                onPrevious?()
            } else {
                onNext?()
            }
            return nil  // consume

        case kVK_Escape where active:
            // Esc aborts a live gesture and is swallowed so it does not also hit the active app.
            active = false
            onCancel?()
            return nil  // consume

        default:
            // Any other key (including a bare Tab with no Option, or Esc with no live gesture)
            // passes straight through.
            return Unmanaged.passUnretained(event)
        }
    }

    /// A gesture is committed the moment Option is released while it was in flight. We only read
    /// the flags here — the event itself is always passed through by the caller.
    private func handleFlagsChanged(_ event: CGEvent) {
        // Gesture commits the moment Command is released while it was in flight.
        guard active, !event.flags.contains(.maskCommand) else { return }
        active = false
        onConfirm?()
    }
}

// MARK: - C callback

/// C-compatible trampoline for the event tap. Has no captured state — it recovers the owning
/// `HotKeyMonitor` from `refcon` and forwards the decision to it.
///
/// `takeUnretainedValue()` mirrors the `passUnretained` used at registration: the monitor owns
/// the tap and outlives every callback, so we must not consume a reference here.
private func hotKeyEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    // Re-arm path: the OS disabled the tap (slow callback or interrupting input). Re-enable it
    // and let the (sentinel) event pass. Missing this is what makes taps "randomly stop working".
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let refcon {
            let monitor = Unmanaged<HotKeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
            monitor.reenableTap()
        }
        return Unmanaged.passUnretained(event)
    }

    guard let refcon else {
        // No context to act on — never drop the event.
        return Unmanaged.passUnretained(event)
    }

    let monitor = Unmanaged<HotKeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
    return monitor.handle(type: type, event: event)
}
