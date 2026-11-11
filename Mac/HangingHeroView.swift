import AppKit
import QuartzCore
import SpiderCore
import SwiftUI

/// The hero on his web (or sitting on a desktop widget), built from Core Animation layers.
///
/// Swinging, dropping and the little flip-book poses all run inside macOS's animation
/// server, so the app itself only wakes twice a second to check the timer. This keeps
/// CPU near zero even though the hero is on screen all day.
@MainActor
final class HangingHeroView: NSView {
    /// Web length when the hero is all the way up, and how far he drops in a full work phase.
    static let shortestWeb: CGFloat = 14
    static let dropDistance: CGFloat = 220

    private let controller: TimerController
    private let prefs: HeroPrefs
    private let frames = HeroFrames()

    private let swingLayer = CALayer()
    private let webEdgeLayer = CALayer()
    private let webLayer = CALayer()
    private let knotLayer = CALayer()
    private let heroLayer = CALayer()

    private var updateTimer: Timer?
    private var shownPose: (pose: HeroPose, scale: CGFloat)?
    private var isSwinging = false
    private var webLength: CGFloat?

    /// A click on the hero (not a drag).
    var onClick: (() -> Void)?
    /// The hero is being picked up and moved.
    var onDragBegan: (() -> Void)?
    /// The hero was put down; the window is where it was dropped.
    var onDragEnded: (() -> Void)?
    private(set) var isDragging = false
    private var dragStart: (mouse: NSPoint, windowOrigin: NSPoint)?

    /// Hello on hover, dizzy or grumpy after shaking.
    private var mood = HeroMood()
    private(set) var isHovering = false
    /// He swings from his hands while carried, then settles.
    private var dangle = HeroDangle(length: 50)
    private var physicsTimer: Timer?
    private var lastPhysicsTick: CFTimeInterval?

    /// Where he is on a widget (or the timer card) and what he's doing, or nil while he's on his web.
    private(set) var perchState: PerchState?
    var perchSpot: PerchSpot? { perchState?.spot }

    /// From the top of the web down to the hero's feet at the end of work, for a hero size.
    static func hangHeight(scale: CGFloat) -> CGFloat {
        shortestWeb + dropDistance + (HeroFigure.baseSize.height - HeroFigure.grip.y) * scale + 4
    }

    static func halfWidth(scale: CGFloat) -> CGFloat {
        HeroFigure.baseSize.width * scale / 2
    }

    init(frame: NSRect, controller: TimerController, prefs: HeroPrefs) {
        self.controller = controller
        self.prefs = prefs
        super.init(frame: frame)
        layer = CALayer()
        wantsLayer = true
        setUpLayers()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isOpaque: Bool { false }

    func start() {
        update()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
    }

    // MARK: - Layers

    private func setUpLayers() {
        guard let root = layer else { return }
        root.addSublayer(swingLayer)

        for (web, width, color) in [
            (webEdgeLayer, 3.0, NSColor.black.withAlphaComponent(0.35)),
            (webLayer, 1.4, NSColor.white.withAlphaComponent(0.95)),
        ] {
            web.anchorPoint = CGPoint(x: 0.5, y: 1)
            web.bounds = CGRect(x: 0, y: 0, width: width, height: 0)
            web.backgroundColor = color.cgColor
            swingLayer.addSublayer(web)
        }

        // A little knot where the web is tied, so it looks attached even mid-screen.
        knotLayer.bounds = CGRect(x: 0, y: 0, width: 6, height: 6)
        knotLayer.cornerRadius = 3
        knotLayer.backgroundColor = NSColor.white.cgColor
        knotLayer.borderColor = NSColor.black.withAlphaComponent(0.35).cgColor
        knotLayer.borderWidth = 0.8
        swingLayer.addSublayer(knotLayer)

        heroLayer.contentsGravity = .resizeAspect
        swingLayer.addSublayer(heroLayer)
        layOutLayers()
    }

    /// On his web the window is a narrow strip and everything hangs from its top center;
    /// on a widget it covers the widget and he moves about inside it.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layOutLayers()
    }

    private func layOutLayers() {
        let top = CGPoint(x: bounds.midX, y: bounds.height)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        swingLayer.bounds = CGRect(origin: .zero, size: bounds.size)
        if perchState != nil {
            swingLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            swingLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        } else {
            swingLayer.anchorPoint = CGPoint(x: 0.5, y: 1)
            swingLayer.position = top
            if let webLength {
                heroLayer.position = CGPoint(x: top.x, y: top.y - webLength)
            }
        }
        for web in [webEdgeLayer, webLayer] {
            web.position = top
        }
        knotLayer.position = CGPoint(x: top.x, y: top.y - 3)
        CATransaction.commit()
    }

    // MARK: - Widgets

    /// Puts him at a point in the window (on a widget), stopping any walk or jump.
    func placeHero(at point: CGPoint) {
        guard perchState != nil, heroLayer.position != point else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        heroLayer.removeAnimation(forKey: "travel")
        heroLayer.position = point
        CATransaction.commit()
    }

    /// Walks him through these points (in the window) at an even pace. Core Animation moves
    /// him, so it's smooth at the display's refresh rate and costs the app nothing.
    func walk(through points: [CGPoint], duration: Double) {
        guard perchState != nil, let last = points.last else { return }
        guard points.count > 1, duration > 0 else { return placeHero(at: last) }
        let route = CGMutablePath()
        route.addLines(between: points)
        let walk = CAKeyframeAnimation(keyPath: "position")
        walk.path = route
        walk.calculationMode = .paced
        walk.duration = duration
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        heroLayer.position = last
        heroLayer.add(walk, forKey: "travel")
        CATransaction.commit()
    }

    /// A little jump in an arc, from where he was let go onto the widget's edge.
    func hop(from start: CGPoint, to end: CGPoint) {
        guard perchState != nil else { return }
        let route = CGMutablePath()
        route.move(to: start)
        let lift = 24 + abs(end.x - start.x) * 0.2
        route.addQuadCurve(to: end, control: CGPoint(x: (start.x + end.x) / 2, y: max(start.y, end.y) + lift))
        let jump = CAKeyframeAnimation(keyPath: "position")
        jump.path = route
        jump.calculationMode = .paced
        jump.duration = 0.38
        jump.timingFunctions = [CAMediaTimingFunction(name: .easeInEaseOut)]
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        heroLayer.position = end
        heroLayer.add(jump, forKey: "travel")
        CATransaction.commit()
    }

    /// In the window, his hands on the web.
    var gripPoint: CGPoint {
        CGPoint(x: bounds.midX, y: bounds.height - (webLength ?? Self.shortestWeb))
    }

    /// Puts him on a widget (no web; everything turns around the contact point), or back on his web.
    func setPerch(_ state: PerchState?) {
        let old = perchState
        perchState = state
        // Moving along an edge only moves the window; redraw when the spot or activity changes.
        if let state, let old {
            if state.spot != old.spot { mirror(state.spot) }
            if state.spot != old.spot || state.activity != old.activity { update() }
            return
        }
        guard (state == nil) != (old == nil) else { return }
        let spot = state?.spot
        stopPhysics()

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for web in [webEdgeLayer, webLayer, knotLayer] {
            web.isHidden = spot != nil
        }
        for key in ["swing", "travel"] {
            swingLayer.removeAnimation(forKey: key)
            heroLayer.removeAnimation(forKey: key)
        }
        isSwinging = false
        if spot == nil {
            // Hang him back on the web right away, without gliding there.
            webLength = nil
        }
        CATransaction.commit()
        layOutLayers()
        mirror(spot)

        shownPose = nil
        update()
    }

    /// Gripping the left side is the right-side picture flipped.
    private func mirror(_ spot: PerchSpot?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        heroLayer.setAffineTransform(spot?.isMirrored == true ? CGAffineTransform(scaleX: -1, y: 1) : .identity)
        CATransaction.commit()
    }

    // MARK: - Mouse

    /// The hero's body on screen (a bit larger, to allow for the swing), or nil when hidden.
    /// Only this area catches the mouse; everywhere else clicks go to the windows below.
    var heroRectOnScreen: NSRect? {
        guard prefs.showHero, let window, let root = layer, heroLayer.contents != nil else { return nil }
        var inView: NSRect
        if perchState != nil {
            // On a widget the hero layer sits straight in the window; mid-walk, use where he is
            // on screen right now, not where he's heading.
            let hero = heroLayer.presentation() ?? heroLayer
            inView = hero.frame.insetBy(dx: -6, dy: -4)
            if perchSpot == .face {
                // Peeking, the rest of him is behind the edge: leave the widget (or card) under it clickable.
                let edge = hero.position.y - 4
                inView = NSRect(x: inView.minX, y: edge, width: inView.width, height: max(0, inView.maxY - edge))
            }
        } else {
            inView = root.convert(heroLayer.frame, from: swingLayer).insetBy(dx: -8, dy: -6)
        }
        return window.convertToScreen(convert(inView, to: nil))
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// The mouse moved onto or off the hero.
    func setHovering(_ isOver: Bool) {
        // Called on every mouse move anywhere on screen: only act when it changes.
        guard isOver != isHovering else { return }
        isHovering = isOver
        mood.hover(isOver, at: CACurrentMediaTime())
        update()
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        dragStart = (NSEvent.mouseLocation, window.frame.origin)
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart, let window else { return }
        let mouse = NSEvent.mouseLocation
        let dx = mouse.x - start.mouse.x
        let dy = mouse.y - start.mouse.y
        if !isDragging {
            // A few points of wobble still counts as a click.
            guard hypot(dx, dy) >= 4 else { return }
            isDragging = true
            NSCursor.closedHand.push()
            onDragBegan?()
            // Picking him off a widget moves the window back to his web, so measure from here.
            dragStart = (mouse, window.frame.origin)
            startPhysics()
            return
        }
        window.setFrameOrigin(NSPoint(x: start.windowOrigin.x + dx, y: start.windowOrigin.y + dy))
        mood.dragged(to: mouse, at: CACurrentMediaTime())
        update()
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragStart = nil }
        if isDragging {
            isDragging = false
            NSCursor.pop()
            mood.dropped()
            onDragEnded?()
        } else if dragStart != nil {
            onClick?()
        }
    }

    // MARK: - Dangling

    /// Runs the pendulum 60 times a second, only while he's carried or still swinging.
    private func startPhysics() {
        guard physicsTimer == nil else { return }
        lastPhysicsTick = nil
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.physicsTick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        physicsTimer = timer
    }

    private func stopPhysics() {
        physicsTimer?.invalidate()
        physicsTimer = nil
        dangle = HeroDangle(length: dangle.length)
    }

    private func physicsTick() {
        guard perchSpot == nil else { return stopPhysics() }
        let now = CACurrentMediaTime()
        let dt = min(now - (lastPhysicsTick ?? now - 1.0 / 60), 0.05)
        lastPhysicsTick = now
        dangle.length = 50 * prefs.size.scale
        // While carried his hands follow the mouse; once put down they stay still.
        dangle.step(pivot: isDragging ? NSEvent.mouseLocation : nil, dt: dt)

        let settled = !isDragging && dangle.isSettled
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        heroLayer.setAffineTransform(settled ? .identity : CGAffineTransform(rotationAngle: dangle.angle))
        CATransaction.commit()

        if settled {
            physicsTimer?.invalidate()
            physicsTimer = nil
        }
    }

    // MARK: - Updates

    private func update() {
        guard prefs.showHero else {
            swingLayer.isHidden = true
            return
        }
        swingLayer.isHidden = false

        let placement = HeroPlacement(
            state: controller.state,
            now: Date(),
            lastFinished: controller.lastFinished
        )
        let reaction = mood.reaction(at: CACurrentMediaTime())
        if let perchState {
            show(pose: perchState.pose(timerPose: placement.pose, reaction: reaction), scale: prefs.size.scale)
            // Hanging still upside down he sways a little; elsewhere he's sitting, walking or holding on.
            setSwinging(perchState.swings)
            return
        }
        show(pose: reaction?.pose ?? placement.pose, scale: prefs.size.scale)
        setSwinging(placement.swings)
        setWebLength(Self.shortestWeb + placement.drop * Self.dropDistance)
    }

    private func show(pose: HeroPose, scale: CGFloat) {
        if let shownPose, shownPose.pose == pose, shownPose.scale == scale { return }
        // Blend from one pose into the next instead of snapping.
        let blend = shownPose != nil && shownPose?.scale == scale
        shownPose = (pose, scale)

        let backing = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let flipBook = frames.flipBook(for: pose, scale: scale, backingScale: backing)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Each pose has its own picture size and holds on at its own point.
        let layout = HeroFigure.layout(for: pose)
        heroLayer.bounds = CGRect(x: 0, y: 0, width: layout.size.width * scale, height: layout.size.height * scale)
        heroLayer.anchorPoint = CGPoint(x: layout.contact.x / layout.size.width,
                                        y: 1 - layout.contact.y / layout.size.height)
        heroLayer.contentsScale = backing
        if blend {
            let fade = CATransition()
            fade.type = .fade
            fade.duration = 0.2
            heroLayer.add(fade, forKey: "poseFade")
        }
        heroLayer.contents = flipBook.images.first
        heroLayer.removeAnimation(forKey: "flipBook")
        if flipBook.images.count > 1 {
            let animation = CAKeyframeAnimation(keyPath: "contents")
            animation.values = flipBook.images
            animation.calculationMode = .discrete
            animation.duration = flipBook.frameDuration * Double(flipBook.images.count)
            animation.repeatCount = .infinity
            heroLayer.add(animation, forKey: "flipBook")
        }
        CATransaction.commit()
    }

    /// On his web the whole web swings from the top; on a widget he sways from where he holds on.
    private func setSwinging(_ swinging: Bool) {
        guard swinging != isSwinging else { return }
        isSwinging = swinging
        swingLayer.removeAnimation(forKey: "swing")
        heroLayer.removeAnimation(forKey: "swing")
        guard swinging else { return }
        let angle = 3 * CGFloat.pi / 180
        let swing = CABasicAnimation(keyPath: "transform.rotation.z")
        swing.fromValue = -angle
        swing.toValue = angle
        swing.duration = 1.7
        swing.autoreverses = true
        swing.repeatCount = .infinity
        swing.isAdditive = true
        swing.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        (perchState != nil ? heroLayer : swingLayer).add(swing, forKey: "swing")
    }

    private func setWebLength(_ length: CGFloat) {
        let previous = webLength
        guard previous != length else { return }
        webLength = length

        CATransaction.begin()
        if let previous {
            // Small steps glide evenly (a smooth drop); big jumps (skip, reset) ease in and out.
            let bigJump = abs(length - previous) > 20
            CATransaction.setAnimationDuration(bigJump ? 0.9 : 0.5)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: bigJump ? .easeInEaseOut : .linear))
        } else {
            CATransaction.setDisableActions(true)
        }
        for web in [webEdgeLayer, webLayer] {
            web.bounds.size.height = length
        }
        heroLayer.position = CGPoint(x: bounds.width / 2, y: bounds.height - length)
        CATransaction.commit()
    }
}

/// Pre-drawn pictures of the hero, a few per pose, so poses can animate as a flip-book.
@MainActor
final class HeroFrames {
    struct FlipBook {
        let images: [CGImage]
        let frameDuration: Double
    }

    private var cache: [String: FlipBook] = [:]

    func flipBook(for pose: HeroPose, scale: CGFloat, backingScale: CGFloat) -> FlipBook {
        let key = "\(pose.rawValue)-\(scale)-\(backingScale)"
        if let cached = cache[key] { return cached }

        // Frame times line up with each pose's motion cycle in HeroDrawing. More frames make
        // smoother motion; still poses need just one.
        func loop(_ cycle: Double, _ count: Int) -> ([Double], Double) {
            ((0..<count).map { cycle * Double($0) / Double(count) }, cycle / Double(count))
        }
        let (times, frameDuration): ([Double], Double) = switch pose {
        case .hanging, .upsideDown: ([0], 1)
        case .climbing: loop(0.9, 8)
        case .waving, .sittingWaving: loop(0.7, 8)
        case .sleeping, .sittingAsleep: loop(2.4, 12)
        case .dizzy: loop(1.6, 12)
        case .grumpy: loop(1.2, 12)
        case .sitting: loop(1.2, 12)
        case .peeking: loop(3.0, 20)
        case .clinging: loop(1.6, 12)
        case .walking, .upsideDownWalking: loop(0.6, 10)
        case .spying: loop(2.4, 12)
        }
        let images = times.compactMap { time -> CGImage? in
            let renderer = ImageRenderer(content: HeroFigure(pose: pose, time: time, scale: scale))
            renderer.scale = backingScale
            return renderer.cgImage
        }
        let book = FlipBook(images: images, frameDuration: frameDuration)
        cache[key] = book
        return book
    }
}
