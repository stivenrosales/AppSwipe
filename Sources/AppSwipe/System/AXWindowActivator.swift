import AppKit
import ApplicationServices
import AppSwipeCore

/// Activates a window using the Accessibility API (AXUIElement) + NSRunningApplication.
///
/// ## Why match by CGWindowID, not by title
/// The previous implementation matched the AX window by `kAXTitleAttribute == window.title`.
/// That fails in practice: without Screen Recording permission `kCGWindowName` is empty, so the
/// enumerator falls back to the *app name* as the title. The AX window's real title is something
/// else entirely, so the comparison never matches and nothing is raised.
///
/// The fix is to match by the window's real `CGWindowID` — which *is* `window.id` — using the
/// `_AXUIElementGetWindow` bridge (see `AXWindowID.swift`). This is title-independent and exact.
///
/// ## Strategy
/// 1. Create an `AXUIElement` for the owning process and read `kAXWindowsAttribute`.
/// 2. Find the AX window whose `CGWindowID` equals `window.id`.
/// 3. Fallback cascade for robustness: match by title; failing that, take the first window;
///    failing that, just activate the app.
/// 4. On the matched window: raise it, mark it main + focused. On the app: mark it frontmost
///    and activate via `NSRunningApplication`. Several mechanisms are used together because
///    activation on macOS Tahoe is finicky.
///
/// All AX calls are best-effort: if the process exited or an attribute is unreadable, the
/// method exits silently without crashing.
public final class AXWindowActivator: WindowActivator {

    public init() {}

    public func activate(_ window: WindowInfo) {
        let app = AXUIElementCreateApplication(window.pid)

        // Always raise the owning application as a baseline, even if window matching fails.
        defer { activateApp(pid: window.pid, axApp: app) }

        guard let axWindows = axWindowList(of: app, attribute: kAXWindowsAttribute as String),
              !axWindows.isEmpty else {
            // The process may have exited or denied accessibility; the app is still activated.
            return
        }

        guard let axWindow = matchWindow(window, in: axWindows) else { return }

        focusWindow(axWindow)
    }

    // MARK: - Window matching (cascade)

    /// Resolves the AX window for `window` using progressively looser strategies.
    private func matchWindow(_ window: WindowInfo, in axWindows: [AXUIElement]) -> AXUIElement? {
        // 1. Exact match by real CGWindowID (preferred, title-independent).
        if let byID = axWindows.first(where: { axWindowID($0) == window.id }) {
            return byID
        }

        // 2. Fallback: match by title (only meaningful when a real window title is known and
        //    differs from the app name — e.g. when Screen Recording permission is granted).
        if window.title != window.appName,
           let byTitle = axWindows.first(where: {
               axString(of: $0, attribute: kAXTitleAttribute as String) == window.title
           }) {
            return byTitle
        }

        // 3. Last resort: the app's first window, so the user at least lands on the right app.
        return axWindows.first
    }

    // MARK: - Focusing

    /// Brings a single AX window to the foreground of its application.
    private func focusWindow(_ axWindow: AXUIElement) {
        // Raise the window to the front of the app's window stack.
        AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
        // Mark it as the app's main + focused window (ignore errors).
        AXUIElementSetAttributeValue(axWindow, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(axWindow, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    }

    /// Brings the owning application to the foreground using several mechanisms.
    ///
    /// Tahoe can ignore any single signal, so we combine the AX frontmost flag with
    /// `NSRunningApplication.activate`.
    private func activateApp(pid: pid_t, axApp: AXUIElement) {
        AXUIElementSetAttributeValue(axApp, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        NSRunningApplication(processIdentifier: pid)?.activate()
    }
}
