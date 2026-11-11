import CoreGraphics
import Foundation

/// What the desktop hero does when you play with him using the mouse.
public enum HeroReaction: Equatable, Sendable {
    /// The mouse is over him: he waves hello.
    case hello
    /// He was shaken: spinning eyes and stars around his head.
    case dizzy
    /// He was shaken a lot: angry eyes, steam and a shaking fist.
    case grumpy

    public var pose: HeroPose {
        switch self {
        case .hello: .waving
        case .dizzy: .dizzy
        case .grumpy: .grumpy
        }
    }
}

/// Spots shaking while the hero is dragged and works out how he feels about it.
/// Times are seconds on any steady clock; points are screen points.
public struct HeroMood: Sendable {
    /// Back-and-forth moves shorter than this are wobble, not shaking.
    public static let minimumStroke: CGFloat = 24
    /// How far the mouse must come back before it counts as turning around.
    public static let turnTolerance: CGFloat = 8
    /// This many turnarounds within `shakeWindow` make a shake.
    public static let turnsForShake = 4
    public static let shakeWindow: Double = 1.2
    /// Turnarounds piled up (fading with time) that make him grumpy.
    public static let annoyanceForGrumpy: Double = 14
    public static let annoyanceHalfLife: Double = 5
    /// How long each feeling lasts after the last shake.
    public static let dizzySeconds: Double = 3
    public static let grumpySeconds: Double = 4
    /// He keeps waving for a moment after the mouse leaves him.
    public static let helloLinger: Double = 0.6

    private var horizontal = Stroke()
    private var vertical = Stroke()
    private var recentTurns: [Double] = []
    private var annoyance: Double = 0
    private var annoyanceTime: Double = 0
    private var feeling: (reaction: HeroReaction, until: Double)?
    private var hovering = false
    private var hoverEnded: Double?

    public init() {}

    /// Feed every mouse position while he's being dragged.
    public mutating func dragged(to point: CGPoint, at time: Double) {
        let turnedX = horizontal.add(point.x)
        let turnedY = vertical.add(point.y)
        guard turnedX || turnedY else { return }

        recentTurns.append(time)
        recentTurns.removeAll { time - $0 > Self.shakeWindow }

        let active = feeling.flatMap { time < $0.until ? $0.reaction : nil }
        if feeling?.reaction == .grumpy, active == nil {
            // He calmed down after the last tantrum: start counting again.
            annoyance = 0
        }
        annoyance = fadedAnnoyance(at: time) + 1
        annoyanceTime = time

        if annoyance >= Self.annoyanceForGrumpy || active == .grumpy {
            feeling = (.grumpy, time + Self.grumpySeconds)
        } else if recentTurns.count >= Self.turnsForShake || active == .dizzy {
            feeling = (.dizzy, time + Self.dizzySeconds)
        }
    }

    /// The drag ended: forget the stroke in progress (the feeling stays).
    public mutating func dropped() {
        horizontal = Stroke()
        vertical = Stroke()
    }

    /// Whether the mouse is over him.
    public mutating func hover(_ isOver: Bool, at time: Double) {
        if hovering, !isOver { hoverEnded = time }
        hovering = isOver
    }

    /// What he should be doing now, or nil to follow the timer.
    public func reaction(at time: Double) -> HeroReaction? {
        if let feeling, time < feeling.until { return feeling.reaction }
        if hovering { return .hello }
        if let hoverEnded, time - hoverEnded < Self.helloLinger { return .hello }
        return nil
    }

    private func fadedAnnoyance(at time: Double) -> Double {
        annoyance * pow(0.5, max(0, time - annoyanceTime) / Self.annoyanceHalfLife)
    }

    /// One axis of mouse movement: notices when it turns around after a long enough stroke.
    private struct Stroke: Sendable {
        var start: CGFloat?
        var farthest: CGFloat = 0
        var direction: CGFloat = 0

        mutating func add(_ value: CGFloat) -> Bool {
            guard let start else {
                self.start = value
                farthest = value
                return false
            }
            if direction == 0 {
                if abs(value - start) >= HeroMood.turnTolerance {
                    direction = value > start ? 1 : -1
                    farthest = value
                }
                return false
            }
            if (value - farthest) * direction > 0 {
                farthest = value
                return false
            }
            guard abs(farthest - value) >= HeroMood.turnTolerance else { return false }
            let length = abs(farthest - start)
            self.start = farthest
            farthest = value
            direction = -direction
            return length >= HeroMood.minimumStroke
        }
    }
}

/// The hero swinging from his hands like a pendulum while you carry him around.
///
/// `angle` is in radians: positive swings his feet to the right (counterclockwise on a
/// y-up screen, which matches a Core Animation z rotation on the Mac).
public struct HeroDangle: Sendable {
    /// Pull that sets how fast he swings (points per second squared). Tuned by eye, not real gravity.
    public static let gravity: Double = 2400
    /// How quickly the swinging dies down (per second).
    public static let damping: Double = 2.4
    public static let maxAngle: Double = 1.2
    /// Fast flicks are capped so he doesn't spin around.
    public static let maxAcceleration: Double = 15000

    public private(set) var angle: Double = 0
    public private(set) var spin: Double = 0
    /// From his hands down to the middle of his body.
    public var length: Double

    private var lastPivot: CGPoint?
    private var velocity = CGVector.zero

    public init(length: Double) {
        self.length = length
    }

    /// Nearly still and hanging straight down.
    public var isSettled: Bool { abs(angle) < 0.002 && abs(spin) < 0.02 }

    /// Moves time on by `dt` seconds. `pivot` is where his hands are (the mouse while dragging),
    /// or nil once he's been put down and his hands stay still.
    public mutating func step(pivot: CGPoint?, dt: Double) {
        guard dt > 0 else { return }
        var accel = CGVector.zero
        if let pivot, let lastPivot {
            let measured = CGVector(dx: (pivot.x - lastPivot.x) / dt, dy: (pivot.y - lastPivot.y) / dt)
            // Smooth the mouse a little; it moves in jumpy steps.
            let smoothed = CGVector(dx: velocity.dx + (measured.dx - velocity.dx) * 0.5,
                                    dy: velocity.dy + (measured.dy - velocity.dy) * 0.5)
            accel = CGVector(dx: clampAccel((smoothed.dx - velocity.dx) / dt),
                             dy: clampAccel((smoothed.dy - velocity.dy) / dt))
            velocity = smoothed
        } else {
            velocity = .zero
        }
        lastPivot = pivot

        // Carried around, his hands accelerate: his body lags behind, and lifting him
        // quickly pulls him straighter.
        let gravity = max(200, Self.gravity + accel.dy)
        let substeps = 4
        let h = dt / Double(substeps)
        for _ in 0..<substeps {
            let pull = -(gravity / length) * sin(angle) - (accel.dx / length) * cos(angle)
            spin += (pull - Self.damping * spin) * h
            angle += spin * h
            if abs(angle) > Self.maxAngle {
                angle = angle > 0 ? Self.maxAngle : -Self.maxAngle
                spin = 0
            }
        }
    }

    private func clampAccel(_ value: Double) -> Double {
        min(max(value, -Self.maxAcceleration), Self.maxAcceleration)
    }
}
