import ApplicationServices
import CoreGraphics
import Darwin

// MARK: - _AXUIElementGetWindow bridge
//
// `_AXUIElementGetWindow` is a private (but long-stable) Accessibility API that returns the
// `CGWindowID` backing an `AXUIElement`. It is the standard technique used by AltTab, yabai,
// and Hammerspoon to correlate the two window worlds macOS exposes:
//
//   • CoreGraphics windows (`CGWindowListCopyWindowInfo`) — carry the real `CGWindowID`,
//     z-order, and owner PID, but cannot be raised or focused.
//   • Accessibility windows (`AXUIElement`) — can be raised/focused, but are *not* keyed by
//     `CGWindowID`; matching them by title is unreliable (titles change, repeat, or are empty).
//
// Bridging the two by `CGWindowID` gives an exact, title-independent match.
//
// The symbol is resolved at runtime via `dlsym` so the build never links against a private
// symbol (no `Package.swift` changes) and the whole feature degrades gracefully: if the symbol
// ever disappears, `axWindowID(_:)` simply returns `nil` and callers fall back to other paths.

private typealias AXGetWindowFn =
    @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

/// Runtime-resolved pointer to `_AXUIElementGetWindow`, or `nil` if the symbol is unavailable.
private let axUIElementGetWindow: AXGetWindowFn? = {
    guard let handle = dlopen(nil, RTLD_NOW),
          let symbol = dlsym(handle, "_AXUIElementGetWindow") else {
        return nil
    }
    return unsafeBitCast(symbol, to: AXGetWindowFn.self)
}()

/// Returns the `CGWindowID` backing an Accessibility window element, or `nil` if it cannot be
/// resolved (symbol missing, or the element is not a live window).
///
/// This is the shared primitive used by both the enumerator (to attach real titles) and the
/// activator (to find the element to raise) so the two stay in lock-step on how they match.
func axWindowID(_ element: AXUIElement) -> CGWindowID? {
    guard let getWindow = axUIElementGetWindow else { return nil }
    var windowID = CGWindowID(0)
    guard getWindow(element, &windowID) == .success else { return nil }
    return windowID
}

// MARK: - AX attribute helpers

/// Reads the `AXUIElement` array of an attribute (e.g. `kAXWindowsAttribute`), or `nil`.
func axWindowList(of element: AXUIElement, attribute: String) -> [AXUIElement]? {
    var rawValue: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &rawValue)
    guard result == .success,
          let value = rawValue,
          CFGetTypeID(value) == CFArrayGetTypeID() else {
        return nil
    }
    return (value as! [AXUIElement])  // safe: type-ID checked above
}

/// Reads a `String` attribute (e.g. `kAXTitleAttribute`) from an element, or `nil`.
func axString(of element: AXUIElement, attribute: String) -> String? {
    var rawValue: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &rawValue)
    guard result == .success,
          let value = rawValue,
          CFGetTypeID(value) == CFStringGetTypeID() else {
        return nil
    }
    return (value as! String)  // safe: type-ID checked above
}
