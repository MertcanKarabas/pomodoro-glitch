import AppKit
import OSLog

/// A see-through, click-through window that keeps the hero hanging right under
/// our menu bar icon, above other windows and on every Space.
///
/// With several displays macOS moves our menu bar icon to the active display's
/// menu bar, so the hero follows you to the screen you're using.
@MainActor
final class HangingHeroWindow {
    static let size = NSSize(width: 170, height: 380)

    private let panel: NSPanel
    private let heroView: HangingHeroView
    /// Where the menu bar icon is right now, or nil if it isn't on screen.
    private let iconAnchor: @MainActor () -> NSPoint?
    private var followTimer: Timer?
    private var lastAnchor: NSPoint?
    private let log = Logger(subsystem: "SpiderPomodoro", category: "hero")

    init(heroView: HangingHeroView, iconAnchor: @escaping @MainActor () -> NSPoint?) {
        self.heroView = heroView
        self.iconAnchor = iconAnchor
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        // Above normal windows, below our menu bar panel.
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = heroView
    }

    func start() {
        reposition()
        panel.orderFrontRegardless()
        heroView.start()
        // The menu bar icon moves when other apps add or remove theirs, or when you
        // switch displays, so keep following it.
        followTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reposition() }
        }
    }

    private func reposition() {
        let anchor = iconAnchor() ?? fallbackAnchor()
        guard anchor != lastAnchor else { return }
        lastAnchor = anchor
        panel.setFrameOrigin(NSPoint(x: anchor.x - Self.size.width / 2, y: anchor.y - Self.size.height))
        log.notice("Hero anchored at x=\(anchor.x, privacy: .public) y=\(anchor.y, privacy: .public)")
    }

    /// While the icon is being placed (or hidden behind the notch), hang near the right edge.
    private func fallbackAnchor() -> NSPoint {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return .zero }
        return NSPoint(x: screen.visibleFrame.maxX - 140, y: screen.visibleFrame.maxY)
    }
}
