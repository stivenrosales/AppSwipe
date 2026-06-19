import CoreGraphics

/// A single open window, as seen by the domain.
///
/// Pure value type — carries no AppKit/SwiftUI types and no icon. The app icon is
/// resolved in the Presentation layer from `pid`, keeping the domain free of UI
/// dependencies.
public struct WindowInfo: Sendable, Equatable, Identifiable {
    /// CoreGraphics window identifier (`CGWindowListCopyWindowInfo` `kCGWindowNumber`).
    public let id: CGWindowID
    /// The window's title.
    public let title: String
    /// The owning application's display name.
    public let appName: String
    /// The owning application's process identifier. Used downstream to resolve the icon.
    public let pid: pid_t

    public init(id: CGWindowID, title: String, appName: String, pid: pid_t) {
        self.id = id
        self.title = title
        self.appName = appName
        self.pid = pid
    }
}
