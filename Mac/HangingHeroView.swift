import AppKit
import QuartzCore
import SpiderCore
import SwiftUI

/// The hero on his web, built from Core Animation layers.
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
    private let heroLayer = CALayer()

    private var updateTimer: Timer?
    private var shownPose: (pose: HeroPose, scale: CGFloat)?
    private var isSwinging = false
    private var webLength: CGFloat?

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
        let size = bounds.size
        let top = CGPoint(x: size.width / 2, y: size.height)

        // Everything hangs from the top center and swings around it.
        swingLayer.bounds = CGRect(origin: .zero, size: size)
        swingLayer.anchorPoint = CGPoint(x: 0.5, y: 1)
        swingLayer.position = top
        root.addSublayer(swingLayer)

        for (web, width, color) in [
            (webEdgeLayer, 3.0, NSColor.black.withAlphaComponent(0.35)),
            (webLayer, 1.4, NSColor.white.withAlphaComponent(0.95)),
        ] {
            web.anchorPoint = CGPoint(x: 0.5, y: 1)
            web.position = top
            web.bounds = CGRect(x: 0, y: 0, width: width, height: 0)
            web.backgroundColor = color.cgColor
            swingLayer.addSublayer(web)
        }

        heroLayer.contentsGravity = .resizeAspect
        heroLayer.anchorPoint = CGPoint(
            x: HeroFigure.grip.x / HeroFigure.baseSize.width,
            y: 1 - HeroFigure.grip.y / HeroFigure.baseSize.height
        )
        swingLayer.addSublayer(heroLayer)
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
        show(pose: placement.pose, scale: prefs.size.scale)
        setSwinging(placement.swings)
        setWebLength(Self.shortestWeb + placement.drop * Self.dropDistance)
    }

    private func show(pose: HeroPose, scale: CGFloat) {
        if let shownPose, shownPose.pose == pose, shownPose.scale == scale { return }
        shownPose = (pose, scale)

        let backing = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let flipBook = frames.flipBook(for: pose, scale: scale, backingScale: backing)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        heroLayer.bounds = CGRect(
            x: 0, y: 0,
            width: HeroFigure.baseSize.width * scale,
            height: HeroFigure.baseSize.height * scale
        )
        heroLayer.contentsScale = backing
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

    private func setSwinging(_ swinging: Bool) {
        guard swinging != isSwinging else { return }
        isSwinging = swinging
        if swinging {
            let angle = 3 * CGFloat.pi / 180
            let swing = CABasicAnimation(keyPath: "transform.rotation.z")
            swing.fromValue = -angle
            swing.toValue = angle
            swing.duration = 1.7
            swing.autoreverses = true
            swing.repeatCount = .infinity
            swing.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            swingLayer.add(swing, forKey: "swing")
        } else {
            swingLayer.removeAnimation(forKey: "swing")
        }
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

        // Frame times line up with each pose's motion cycle in HeroDrawing.
        let (times, frameDuration): ([Double], Double) = switch pose {
        case .hanging: ([0], 1)
        case .climbing: ([0, 0.225, 0.45, 0.675], 0.225)
        case .waving: ([0, 0.175, 0.35, 0.525], 0.175)
        case .sleeping: ([0, 0.4, 0.8, 1.2, 1.6, 2.0], 0.4)
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
