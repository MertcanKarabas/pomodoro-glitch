import AppKit
import SpiderCore

/// Finds the desktop widgets on screen, so the hero can climb onto them.
///
/// macOS has no API for this, but each desktop widget is its own window owned by
/// Notification Center, just above the desktop icons. The window list gives their frames
/// without any special permission (only window titles need Screen Recording access, and we
/// don't use them). It doesn't say which widget is which, so the hero treats them all alike.
@MainActor
enum DesktopWidgets {
    struct Scan {
        /// Visible widget rectangles, in screen coordinates.
        var widgets: [CGRect] = []
        /// The window level the widgets are at (nil if there are none).
        var level: Int?
        /// Other apps' windows on screen, which hide any widget under them.
        var coveringWindows: [CGRect] = []
    }

    private static let widgetHost = "com.apple.notificationcenterui"

    static func scan() -> Scan {
        guard let mainHeight = NSScreen.screens.first?.frame.height,
              let windows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]]
        else { return Scan() }

        let hostPIDs = Set(NSRunningApplication.runningApplications(withBundleIdentifier: widgetHost)
            .map(\.processIdentifier))
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let dockLevel = Int(CGWindowLevelForKey(.dockWindow))

        var scan = Scan()
        for window in windows {
            guard let pid = window[kCGWindowOwnerPID as String] as? pid_t,
                  let layer = window[kCGWindowLayer as String] as? Int,
                  let boundsInfo = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo),
                  bounds.width > 40, bounds.height > 40
            else { continue }
            let frame = PerchGeometry.screenRect(fromWindowBounds: bounds, mainDisplayHeight: mainHeight)

            if hostPIDs.contains(pid), layer < 0 {
                // Below normal windows: a desktop widget. (Notification Center's other windows sit higher.)
                let inset = PerchGeometry.widgetWindowInset
                scan.widgets.append(frame.insetBy(dx: inset, dy: inset))
                scan.level = layer
            } else if pid != ownPID, layer >= 0, layer < dockLevel,
                      window[kCGWindowIsOnscreen as String] as? Bool == true,
                      (window[kCGWindowAlpha as String] as? Double ?? 1) > 0.05 {
                scan.coveringWindows.append(frame)
            }
        }
        return scan
    }
}
