import AppKit

// MARK: - Bootstrap
//
// AppKit-first lifecycle: no SwiftUI `App`, no storyboard. We create the shared
// application, install our composition root (`AppController`) as the delegate, mark the
// process as an accessory agent (no Dock icon, no menu bar), and start the run loop.

let app = NSApplication.shared
let delegate = AppController()
app.delegate = delegate

// Agent app: no Dock icon, lives in the background.
app.setActivationPolicy(.accessory)

app.run()
