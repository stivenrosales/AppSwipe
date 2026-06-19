# AppSwipe

A fast, minimal, **native macOS window switcher**. It replaces ⌘-Tab with a clean, glassy list of your windows — so you switch to *windows*, not just apps.

> **Beta** · Free & open source. A Pro version may come later, but the core stays open.

## Why

macOS's built-in ⌘-Tab switches between *apps*. AppSwipe switches between *windows*, in true most‑recently‑used order — so flipping between your last two windows is instant, even when they belong to the same app. No live thumbnails (those require private APIs); just a crisp **icon + title** list that feels native and gets out of your way.

## Features

- **⌘-Tab to switch windows** — hold ⌘, tap Tab to cycle, release to select. ⌘⇧Tab goes backwards.
- **True MRU order** — alternate between your two last windows like ⌘-Tab, regardless of app.
- **Native Liquid Glass** — uses macOS Tahoe's `NSGlassEffectView`.
- **Instant quick‑switch** — a fast tap‑and‑release switches with no UI; hold to reveal the list.
- **Mouse or keyboard** selection, with hover feedback.
- **Live preview** in Preferences — change size, font and accent color and see it update instantly.
- **Menu‑bar item** with Preferences and Quit.
- **100% public macOS APIs** for window data + Accessibility — no Screen Recording permission needed.

## Requirements

- **macOS 26 (Tahoe)** — uses native Liquid Glass APIs.
- The Swift toolchain (Xcode or Command Line Tools) to build.
- **Accessibility** permission (the app guides you through it on first launch).

## Install (beta — build from source)

```bash
git clone https://github.com/stivenrosales/AppSwipe.git
cd AppSwipe
./scripts/run.sh
```

`run.sh` builds a release, installs **AppSwipe.app** into `/Applications`, signs it with a stable local certificate (so the Accessibility permission survives rebuilds), and launches it. Then grant **Accessibility** in *System Settings → Privacy & Security → Accessibility*.

> ⚠️ AppSwipe is signed with a *local self‑signed* certificate, not an Apple Developer ID. macOS Gatekeeper may warn on first open — right‑click the app → **Open** to confirm. A notarized signed release will come later.

## Building & developing

This project uses **Swift Package Manager**, driven through a `Makefile`:

```bash
make build     # debug build
make test      # run the domain test suite (Swift Testing)
make release   # release build
```

### macOS Tahoe build note

On macOS 26 **Command Line Tools**, plain `swift build` fails to compile the package manifest (a symbol mismatch in `libPackageDescription`, `SwiftVersion` vs `SwiftLanguageMode`). The `Makefile` + `scripts/swift-wrapper.sh` work around this transparently — **always build via `make`, never `swift` directly.**

## Architecture

Clean and layered, with a pure, fully‑tested core:

- **`AppSwipeCore`** — pure domain: window model, MRU tracker, selection logic. No AppKit/SwiftUI. Unit‑tested.
- **`AppSwipe`** (executable) — System adapters (window enumeration, activation, the ⌘-Tab `CGEventTap`, permissions) + SwiftUI presentation (panel, list, preferences) + the composition root.

The domain depends on protocols (ports); the macOS adapters implement them — so the switching logic is tested without ever opening a window.

## Support the creator ☕

AppSwipe is free. If it makes your day a little smoother, you can buy me a coffee:

**PayPal:** `stivenrosales01@gmail.com`

Every coffee fuels the next feature. Thank you! 🙌

## Roadmap

- Type‑to‑filter the window list
- Close a window straight from the switcher
- Launch at login
- Configurable shortcut

## License

[GPL‑3.0](LICENSE) © Stiven Rosales.

You're free to use, study, modify and share AppSwipe. Forks and derivatives must remain open source under the same license.

## Disclaimer

Beta software, provided as‑is. AppSwipe uses the Accessibility API to read and activate your windows — nothing ever leaves your machine.
