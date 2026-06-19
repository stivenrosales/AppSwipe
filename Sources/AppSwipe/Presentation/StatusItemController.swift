import AppKit
import SwiftUI

/// Owns the menu-bar status item and the Preferences window.
///
/// The app runs as an `.accessory` agent (no Dock icon), so the menu bar is the only place the
/// user can reach it. The menu offers Preferences and—critically—Quit, since until now the only
/// way to stop the app was `pkill`.
///
/// ### Preferences window focus
/// An `.accessory` app cannot, by default, bring a normal window to the front with keyboard
/// focus. So before showing the window we temporarily promote the process with
/// `NSApp.activate(ignoringOtherApps:)` and order the window front as key. The window itself is a
/// standard titled `NSWindow` (not the non-activating switcher panel) so it behaves like any
/// settings window.
@MainActor
final class StatusItemController: NSObject {

    // MARK: - State

    private var statusItem: NSStatusItem?
    /// Retained so the Preferences window survives between openings and is reused if already open.
    private var preferencesWindow: NSWindow?

    // MARK: - Lifecycle

    /// Installs the status item in the menu bar. Idempotent.
    func install() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "macwindow.on.rectangle",
                accessibilityDescription: "AppSwipe"
            )
            button.image?.isTemplate = true
        }
        item.menu = makeMenu()
        statusItem = item
    }

    // MARK: - Menu

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()

        let preferences = NSMenuItem(
            title: "Preferencias…",
            action: #selector(openPreferences),
            keyEquivalent: ","
        )
        preferences.target = self
        menu.addItem(preferences)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Salir de AppSwipe",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    // MARK: - Actions

    /// Opens (or re-focuses) the Preferences window. Internal so the app delegate can call it on
    /// reopen (double-clicking the app), not only from the menu.
    @objc func openPreferences() {
        // Promote the accessory app so the window can take keyboard focus.
        NSApp.activate(ignoringOtherApps: true)

        if let window = preferencesWindow {
            window.makeKeyAndOrderFront(nil)
            return
        }

        // Let SwiftUI drive the window size. An `NSHostingController` with
        // `sizingOptions = [.preferredContentSize]` reports the view's *fitting size* (including
        // the `Form`'s grouped insets) up to the window via `preferredContentSize`, so the window
        // adopts exactly the size the content needs. This is the fix for the old bug where a fixed
        // 420×240 `contentRect` clipped the Form on every side (truncated headers, overflowing
        // slider/toggle): a raw `NSHostingView` never negotiates size with its window.
        let host = NSHostingController(rootView: PreferencesView())
        host.sizingOptions = [.preferredContentSize]

        let window = NSWindow(contentViewController: host)
        window.styleMask = [.titled, .closable]
        window.title = "Preferencias de AppSwipe"
        window.isReleasedWhenClosed = false       // we retain it ourselves for reuse
        window.center()
        window.makeKeyAndOrderFront(nil)

        preferencesWindow = window
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
