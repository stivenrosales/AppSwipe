import AppKit
import ApplicationServices

/// AccessibilityGate handles macOS Accessibility API permissions and interactions.
struct AccessibilityGate {

    /// Checks if the current process is trusted by the Accessibility API.
    /// - Returns: `true` if the process has accessibility permissions, `false` otherwise.
    func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Requests accessibility permissions by displaying the system permission prompt.
    /// Opens the Accessibility panel in System Settings if the user grants permission.
    func requestAccess() {
        // `kAXTrustedCheckOptionPrompt` is a C global `var`, so Swift 6 strict concurrency
        // rejects touching it directly. Its value is the documented, stable string key
        // "AXTrustedCheckOptionPrompt" (see AXUIElement.h), which we use verbatim.
        let options: CFDictionary = [
            "AXTrustedCheckOptionPrompt": kCFBooleanTrue as Any
        ] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Opens the Accessibility privacy settings in System Preferences.
    func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
