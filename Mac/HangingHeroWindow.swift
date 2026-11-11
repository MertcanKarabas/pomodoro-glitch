import AppKit
import OSLog
import SpiderCore

/// A see-through window that keeps the hero hanging under our menu bar icon (or wherever
/// he was dragged), above other windows and on every Space.
///
/// Dropped on a desktop widget, he climbs onto it instead: the window moves down to the
/// widgets' level, so app windows cover him just like they cover the widget.
///
/// Only the hero's body catches the mouse, so you can click and drag him; the rest of the
/// window lets clicks through to whatever is underneath.
///
/// With several displays macOS moves our menu bar icon to the active display's
/// menu bar, so a hero that hasn't been moved follows you to the screen you're using.
@MainActor
final class HangingHeroWindow {
    static let size = NSSize(width: 170, height: 380)
    /// On a widget the window covers it with this much room round it for him to sit, hang
    /// or climb in.
    static let perchRoom: CGFloat = 130

    private let panel: NSPanel
    private let heroView: HangingHeroView
    private let prefs: HeroPrefs
    /// Where the menu bar icon is right now, or nil if it isn't on screen.
    private let iconAnchor: @MainActor () -> NSPoint?
    private var followTimer: Timer?
    private var lastAnchor: NSPoint?
    private var mouseMonitors: [Any] = []
    /// Window level of the desktop widgets, from the last look at them.
    private var widgetLevel: Int?
    private var missedWidgetChecks = 0
    private var ticks = 0
    /// Wanders him round his widget while he's on one.
    private var roamer: PerchRoamer?
    private var motionTimer: Timer?
    private var lastRoamTick: CFTimeInterval?
    private var random = SystemRandomNumberGenerator()
    private let log = Logger(subsystem: "SpiderPomodoro", category: "hero")

    /// The hero was clicked. Gets his body's rect on screen.
    var onHeroClick: ((NSRect) -> Void)?
    /// The hero is being dragged.
    var onHeroDragBegan: (() -> Void)?
    /// Where the timer card is, or nil while it's closed. He can climb it like a widget.
    var cardFrame: (() -> NSRect?)?

    init(heroView: HangingHeroView, prefs: HeroPrefs, iconAnchor: @escaping @MainActor () -> NSPoint?) {
        self.heroView = heroView
        self.prefs = prefs
        self.iconAnchor = iconAnchor
        panel = FreePanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // Clicks pass through until the mouse is over the hero himself.
        panel.ignoresMouseEvents = true
        panel.acceptsMouseMovedEvents = true
        // Above normal windows, below our menu bar panel.
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = heroView

        heroView.onClick = { [weak self] in
            guard let self, let rect = self.heroView.heroRectOnScreen else { return }
            self.onHeroClick?(rect)
        }
        heroView.onDragBegan = { [weak self] in self?.heroPickedUp() }
        heroView.onDragEnded = { [weak self] in self?.heroDropped() }
    }

    func start() {
        log.notice("Desktop widgets found: \(DesktopWidgets.scan().widgets.count, privacy: .public)")
        if prefs.perch != nil { followWidget() }
        reposition()
        panel.orderFrontRegardless()
        heroView.start()
        // The menu bar icon moves when other apps add or remove theirs, or when you
        // switch displays, so keep following it. On a widget, check every 2 seconds that
        // it's still there (widgets can be moved or removed).
        followTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.ticks += 1
                if self.prefs.perch != nil, self.ticks.isMultiple(of: 2) { self.followWidget() }
                self.reposition()
                self.roam()
            }
        }
        trackMouse()
        watchPrefs()
    }

    // MARK: - Position

    /// - Parameter hopFrom: where he was let go (screen point), to jump from onto a widget.
    private func reposition(hopFrom: NSPoint? = nil) {
        guard !heroView.isDragging else { return }
        if let perch = prefs.perch {
            if roamer == nil {
                roamer = PerchRoamer(spot: perch.spot, along: perch.along, now: CACurrentMediaTime(),
                                     wanderEvery: prefs.wander.seconds, random: &random)
            }
            placeOnWidget(perch, hopFrom: hopFrom)
            return
        }
        if heroView.perchSpot != nil || roamer != nil {
            leaveWidget()
        }
        let anchor = savedAnchor() ?? iconAnchor() ?? fallbackAnchor()
        guard anchor != lastAnchor else { return }
        lastAnchor = anchor
        panel.setFrameOrigin(NSPoint(x: anchor.x - Self.size.width / 2, y: anchor.y - Self.size.height))
        log.notice("Hero anchored at x=\(anchor.x, privacy: .public) y=\(anchor.y, privacy: .public)")
    }

    /// Where he was dropped, if that spot is still on a connected display.
    private func savedAnchor() -> NSPoint? {
        guard let anchor = prefs.customAnchor else { return nil }
        let onScreen = NSScreen.screens.contains { $0.frame.insetBy(dx: -1, dy: -1).contains(anchor) }
        return onScreen ? anchor : nil
    }

    /// Dropped on a widget he can see, he climbs onto it. Anywhere else, his web starts
    /// there (moved so his whole drop fits on that display).
    private func heroDropped() {
        let mouse = NSEvent.mouseLocation
        // His hands as he was let go, to jump from.
        let hands = NSPoint(x: panel.frame.minX + heroView.gripPoint.x, y: panel.frame.minY + heroView.gripPoint.y)
        // The card floats above everything, so it comes first.
        if let card = cardFrame?(), card.insetBy(dx: -PerchGeometry.reach, dy: -PerchGeometry.reach).contains(mouse) {
            let perch = PerchGeometry.perch(droppedAt: mouse, on: card, surface: .timerCard)
            log.notice("Hero climbed onto the timer card: \(perch.spot.rawValue, privacy: .public)")
            roamer = nil
            prefs.perch = perch
            reposition(hopFrom: hands)
            return
        }
        let scan = DesktopWidgets.scan()
        if let widget = PerchGeometry.widget(at: mouse, among: scan.widgets),
           !PerchGeometry.isCovered(mouse, by: scan.coveringWindows) {
            widgetLevel = scan.level
            missedWidgetChecks = 0
            let perch = PerchGeometry.perch(droppedAt: mouse, on: widget)
            log.notice("Hero climbed onto a widget: \(perch.spot.rawValue, privacy: .public)")
            roamer = nil
            prefs.perch = perch
            reposition(hopFrom: hands)
            return
        }
        log.notice("Hero dropped; \(scan.widgets.count, privacy: .public) desktop widgets found")
        prefs.perch = nil
        let frame = panel.frame
        prefs.customAnchor = clamped(NSPoint(x: frame.midX, y: frame.maxY))
        lastAnchor = nil
        reposition()
    }

    // MARK: - Desktop widgets

    /// Picked up off a widget: back on his web, hanging just above the mouse.
    private func heroPickedUp() {
        if prefs.perch != nil {
            prefs.perch = nil
            leaveWidget()
            let mouse = NSEvent.mouseLocation
            let grip = heroView.gripPoint
            let handsAboveMouse = 30 * prefs.size.scale
            panel.setFrameOrigin(NSPoint(x: mouse.x - grip.x, y: mouse.y + handsAboveMouse - grip.y))
        }
        onHeroDragBegan?()
    }

    /// How far from the corners he keeps on the top and bottom edges, and on the sides.
    private var perchMargins: (edge: CGFloat, side: CGFloat) {
        (26 * prefs.size.scale, 45 * prefs.size.scale)
    }

    private func path(round perch: Perch) -> PerchPath {
        PerchPath(widget: perch.widget, edgeMargin: perchMargins.edge, sideMargin: perchMargins.side)
    }

    private func placeOnWidget(_ perch: Perch, hopFrom: NSPoint? = nil) {
        let state = roamer?.state ?? PerchState(spot: perch.spot, along: perch.along)
        heroView.setPerch(state)
        let level: NSWindow.Level = switch perch.surface {
        case .desktopWidget:
            // Just above the widgets, so app windows cover him like they cover the widget.
            NSWindow.Level(rawValue: (widgetLevel ?? Int(CGWindowLevelForKey(.desktopIconWindow)) + 2) + 1)
        case .timerCard:
            // Just above the card (which floats over other windows).
            NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        }
        if panel.level != level { panel.level = level }

        // The window covers the widget (and moves with it); he moves about inside.
        let frame = perch.widget.insetBy(dx: -Self.perchRoom, dy: -Self.perchRoom)
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
        }
        lastAnchor = nil
        // Mid-walk, Core Animation is moving him.
        guard roamer?.isMoving != true else { return }
        let contact = PerchGeometry.contact(
            for: Perch(spot: state.spot, surface: perch.surface, widget: perch.widget, along: state.along),
            edgeMargin: perchMargins.edge, sideMargin: perchMargins.side
        )
        let spot = inWindow(contact)
        if let hopFrom {
            heroView.hop(from: inWindow(hopFrom), to: spot)
        } else {
            heroView.placeHero(at: spot)
        }
    }

    private func inWindow(_ point: NSPoint) -> CGPoint {
        CGPoint(x: point.x - panel.frame.minX, y: point.y - panel.frame.minY)
    }

    private func leaveWidget() {
        roamer = nil
        stopMotion()
        heroView.setPerch(nil)
        panel.level = .floating
        if panel.frame.size != Self.size {
            panel.setFrame(NSRect(origin: panel.frame.origin, size: Self.size), display: true)
        }
        lastAnchor = nil
    }

    // MARK: - Wandering

    /// Lets him wander at random times. Checks once a second while he rests; while he walks,
    /// Core Animation moves him and this only switches his pose at the corners (10 times a second).
    private func roam() {
        guard let perch = prefs.perch, var roamer, !heroView.isDragging else { return stopMotion() }
        let now = CACurrentMediaTime()
        let dt = min(now - (lastRoamTick ?? now), 0.5)
        lastRoamTick = now
        let path = path(round: perch)
        let speed = 70 * prefs.size.scale
        roamer.setWanderEvery(prefs.wander.seconds, now: now, random: &random)
        let event = roamer.advance(to: now, dt: dt, path: path, speed: speed,
                                   paused: heroView.isHovering, random: &random)
        self.roamer = roamer
        heroView.setPerch(roamer.state)
        switch event {
        case .departed:
            if let trip = roamer.trip {
                log.notice("Hero is off to the \(trip.destination.spot.rawValue, privacy: .public)")
                heroView.walk(through: route(for: trip, along: path), duration: trip.length / speed)
            }
        case .arrived:
            // Remember where he settled, so he's there after a restart.
            let state = roamer.state
            prefs.perch = Perch(spot: state.spot, surface: perch.surface, widget: perch.widget, along: state.along)
        case .startedSpying, .stoppedSpying, nil:
            break
        }
        if roamer.isMoving { startMotion() } else { stopMotion() }
    }

    /// Points every few points along his way, in the window.
    private func route(for trip: PerchRoamer.Trip, along path: PerchPath) -> [CGPoint] {
        var points: [CGPoint] = []
        var travelled = 0.0
        while travelled < trip.length {
            points.append(inWindow(path.place(at: trip.start + travelled * trip.direction).point))
            travelled += 3
        }
        points.append(inWindow(path.place(at: trip.start + trip.length * trip.direction).point))
        return points
    }

    private func startMotion() {
        guard motionTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.roam() }
        }
        RunLoop.main.add(timer, forMode: .common)
        motionTimer = timer
    }

    private func stopMotion() {
        motionTimer?.invalidate()
        motionTimer = nil
    }

    /// Follows his widget if it was moved; if it's gone for 10 seconds (removed, or the
    /// widgets restarted), he goes back to hanging from his web where it was.
    private func followWidget() {
        guard let perch = prefs.perch, !heroView.isDragging else { return }
        if perch.surface == .timerCard {
            return cardFrameChanged(cardFrame?())
        }
        let scan = DesktopWidgets.scan()
        widgetLevel = scan.level ?? widgetLevel
        if let widget = PerchGeometry.sameWidget(as: perch.widget, among: scan.widgets) {
            missedWidgetChecks = 0
            if widget != perch.widget { prefs.perch?.widget = widget }
            return
        }
        missedWidgetChecks += 1
        guard missedWidgetChecks >= 5 else { return }
        log.notice("Hero's widget is gone; back on his web")
        missedWidgetChecks = 0
        fallOff(perch)
    }

    /// The timer card moved or closed. If he's on it, he moves with it, or goes back on his web.
    func cardFrameChanged(_ frame: NSRect?) {
        guard let perch = prefs.perch, perch.surface == .timerCard, !heroView.isDragging else { return }
        guard let frame else { return fallOff(perch) }
        guard frame != perch.widget else { return }
        prefs.perch?.widget = frame
        reposition()
    }

    /// Back on his web, hanging from where the top of the widget (or card) was.
    private func fallOff(_ perch: Perch) {
        let contact = PerchGeometry.contact(for: perch, edgeMargin: perchMargins.edge, sideMargin: perchMargins.side)
        prefs.perch = nil
        prefs.customAnchor = clamped(NSPoint(x: contact.x, y: perch.widget.maxY))
    }

    /// Keeps a web spot where the hero, hanging at his lowest, stays on its display.
    private func clamped(_ point: NSPoint) -> NSPoint {
        let screen = NSScreen.screens.first { $0.frame.contains(point) }
            ?? NSScreen.screens.min { distance($0.frame, point) < distance($1.frame, point) }
        guard let visible = screen?.visibleFrame else { return point }
        let scale = prefs.size.scale
        return HeroGeometry.clampedAnchor(
            point,
            in: visible,
            hangHeight: HangingHeroView.hangHeight(scale: scale),
            halfWidth: HangingHeroView.halfWidth(scale: scale)
        )
    }

    /// "Back under the menu bar" clears the drop spot (and takes him off a widget), and a
    /// bigger hero may need moving up, so follow those settings right away.
    private func watchPrefs() {
        withObservationTracking {
            _ = prefs.customAnchor
            _ = prefs.size
            _ = prefs.perch
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if let anchor = self.prefs.customAnchor {
                    let fitted = self.clamped(anchor)
                    if fitted != anchor { self.prefs.customAnchor = fitted }
                }
                self.lastAnchor = nil
                self.reposition()
                self.watchPrefs()
            }
        }
    }

    private func distance(_ rect: NSRect, _ point: NSPoint) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return hypot(dx, dy)
    }

    /// While the icon is being placed (or hidden behind the notch), hang near the right edge.
    private func fallbackAnchor() -> NSPoint {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return .zero }
        return NSPoint(x: screen.visibleFrame.maxX - 140, y: screen.visibleFrame.maxY)
    }

    // MARK: - Mouse

    /// Lets the window catch the mouse only while it's over the hero. Event driven: costs
    /// nothing while the mouse is still.
    private func trackMouse() {
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.updateMouseCatching() }
        }) {
            mouseMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: events, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.updateMouseCatching() }
            return event
        }) {
            mouseMonitors.append(local)
        }
    }

    private func updateMouseCatching() {
        guard !heroView.isDragging else { return }
        let overHero = heroView.heroRectOnScreen?.contains(NSEvent.mouseLocation) ?? false
        heroView.setHovering(overHero)
        if panel.ignoresMouseEvents == overHero {
            panel.ignoresMouseEvents = !overHero
        }
    }
}

/// A panel macOS doesn't push around. Normally a window that would reach above the top of
/// the screen gets moved down below the menu bar; the hero's window is mostly see-through
/// and often pokes out above (say, sitting on a card near the top), so that move would put
/// him in the wrong place.
final class FreePanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
