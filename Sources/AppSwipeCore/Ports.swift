/// Ports (hexagonal boundaries) the domain depends on. System adapters implement them.

/// Supplies the current list of windows.
///
/// Implementations return windows in z-order / MRU order, frontmost first. The domain
/// treats index 0 as the currently focused window and index 1 as the previous one.
public protocol WindowProvider {
    func currentWindows() -> [WindowInfo]
}

/// Brings a window to the front.
public protocol WindowActivator {
    func activate(_ window: WindowInfo)
}
