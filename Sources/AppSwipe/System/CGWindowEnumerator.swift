import ApplicationServices
import CoreGraphics
import Foundation
import AppSwipeCore

/// System adapter that enumerates on-screen windows via `CGWindowListCopyWindowInfo`.
///
/// Returns windows in z-order (frontmost first), filtered to normal windows only
/// (layer 0, has an owner, not the current process).
///
/// ## Real titles via Accessibility
/// `CGWindowListCopyWindowInfo`'s `kCGWindowName` is empty unless the process has Screen
/// Recording permission, so on its own it yields no usable window titles. Instead we enrich
/// each window with its *real* title from the Accessibility API (`kAXTitleAttribute`), matched
/// to the CoreGraphics window by `CGWindowID` (see `AXWindowID.swift`). This needs only the
/// Accessibility permission we already hold — no Screen Recording.
///
/// To keep enumeration cheap we build one `AXUIElementCreateApplication` per *process* (not per
/// window) and resolve a `CGWindowID → title` map once per app. Windows whose title cannot be
/// resolved keep the app name as a fallback. The CoreGraphics z-order (the MRU order) is
/// preserved throughout.
public struct CGWindowEnumerator: WindowProvider {

    public init() {}

    public func currentWindows() -> [WindowInfo] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard
            let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[CFString: Any]]
        else {
            return []
        }

        // First pass: parse the raw CG entries into lightweight records, preserving z-order.
        let records: [RawWindow] = raw.compactMap { entry in
            // Must be a normal window (layer 0).
            guard let layer = entry[kCGWindowLayer] as? Int, layer == 0 else { return nil }
            // Must have an owner PID.
            guard let pid = entry[kCGWindowOwnerPID] as? pid_t else { return nil }
            // NOTE: we intentionally do NOT exclude our own process. The switcher panel is a
            // floating, borderless NSPanel (window level > 0), so the `layer == 0` filter above
            // already drops it. Our normal windows (e.g. the Preferences window) SHOULD be
            // switchable like any other window — excluding the whole PID was hiding Preferences.
            // Must have a window number (CGWindowID is UInt32).
            guard let windowID = entry[kCGWindowNumber] as? CGWindowID else { return nil }
            // Owner name (app name) — discard entries with no owner name.
            guard let appName = entry[kCGWindowOwnerName] as? String, !appName.isEmpty else {
                return nil
            }
            return RawWindow(id: windowID, appName: appName, pid: pid)
        }

        // Resolve real AX titles, grouping the work by process so each app element is built once.
        let titlesByID = resolveTitles(for: records)

        // Second pass: build the domain models, attaching the real title when available.
        return records.map { record in
            let realTitle = titlesByID[record.id]
            let title = (realTitle?.isEmpty == false) ? realTitle! : record.appName
            return WindowInfo(
                id: record.id,
                title: title,
                appName: record.appName,
                pid: record.pid
            )
        }
    }

    // MARK: - Private

    /// Minimal record carried between the two enumeration passes.
    private struct RawWindow {
        let id: CGWindowID
        let appName: String
        let pid: pid_t
    }

    /// Builds a `CGWindowID → real title` map by querying each process's AX windows once.
    ///
    /// One `AXUIElementCreateApplication` is created per distinct PID; every AX window of that
    /// app is read once and keyed by its `CGWindowID`, so the cost scales with apps + windows,
    /// not with windows × apps.
    private func resolveTitles(for records: [RawWindow]) -> [CGWindowID: String] {
        // Only the PIDs we actually have on-screen windows for.
        let pids = Set(records.map(\.pid))
        guard !pids.isEmpty else { return [:] }

        var titles: [CGWindowID: String] = [:]
        titles.reserveCapacity(records.count)

        for pid in pids {
            let app = AXUIElementCreateApplication(pid)
            guard let axWindows = axWindowList(of: app, attribute: kAXWindowsAttribute as String) else {
                continue
            }
            for axWindow in axWindows {
                guard let windowID = axWindowID(axWindow),
                      let title = axString(of: axWindow, attribute: kAXTitleAttribute as String),
                      !title.isEmpty else {
                    continue
                }
                titles[windowID] = title
            }
        }
        return titles
    }
}
