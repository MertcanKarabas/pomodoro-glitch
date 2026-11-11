import CoreGraphics
import Foundation

/// What the hero is doing on a widget or the timer card.
public enum PerchActivity: String, Codable, Sendable {
    /// Staying put: sitting on top, hanging underneath, gripping a side or peeking.
    case resting
    /// Walking along an edge or climbing a side to somewhere else.
    case moving
    /// Hanging underneath, watching the widget through binoculars.
    case spying
}

/// Where the hero is on a widget right now and what he's doing there.
public struct PerchState: Equatable, Sendable {
    public var spot: PerchSpot
    public var along: Double
    public var activity: PerchActivity

    public init(spot: PerchSpot, along: Double, activity: PerchActivity = .resting) {
        self.spot = spot
        self.along = along
        self.activity = activity
    }

    public func pose(task: HeroTask, reaction: HeroReaction?) -> HeroPose {
        switch activity {
        case .resting:
            return spot.pose(task: task, reaction: reaction)
        case .spying:
            return spot == .bottom ? .spying : spot.pose(task: task, reaction: reaction)
        case .moving:
            switch spot {
            case .top, .face: return .walking
            case .bottom: return .upsideDownWalking
            case .left, .right: return .clinging
            }
        }
    }

    /// Hanging still upside down he sways a little.
    public var swings: Bool { spot == .bottom && activity == .resting }
}

/// The way round a widget: along the top edge left to right, round the corner, down the right
/// side, along the bottom right to left, and up the left side. Each edge stops short of the
/// corners by the same margins `PerchGeometry.contact` uses (so a point on an edge is exactly
/// where he'd sit), and a short hop round each corner joins the edges up.
public struct PerchPath: Sendable {
    public let widget: CGRect
    public let edgeMargin: CGFloat
    public let sideMargin: CGFloat

    private struct Segment {
        var start: CGPoint
        var end: CGPoint
        /// The spot for the first and second half (they differ only round a corner).
        var spots: (PerchSpot, PerchSpot)
        var length: Double { Double(hypot(end.x - start.x, end.y - start.y)) }
    }

    private let segments: [Segment]

    public init(widget: CGRect, edgeMargin: CGFloat, sideMargin: CGFloat) {
        self.widget = widget
        self.edgeMargin = edgeMargin
        self.sideMargin = sideMargin
        let left = widget.minX + min(edgeMargin, widget.width / 2)
        let right = widget.maxX - min(edgeMargin, widget.width / 2)
        let low = widget.minY + min(sideMargin, widget.height / 2)
        let high = widget.maxY - min(sideMargin, widget.height / 2)
        let topLeft = CGPoint(x: left, y: widget.maxY), topRight = CGPoint(x: right, y: widget.maxY)
        let rightHigh = CGPoint(x: widget.maxX, y: high), rightLow = CGPoint(x: widget.maxX, y: low)
        let bottomRight = CGPoint(x: right, y: widget.minY), bottomLeft = CGPoint(x: left, y: widget.minY)
        let leftLow = CGPoint(x: widget.minX, y: low), leftHigh = CGPoint(x: widget.minX, y: high)
        segments = [
            Segment(start: topLeft, end: topRight, spots: (.top, .top)),
            Segment(start: topRight, end: rightHigh, spots: (.top, .right)),
            Segment(start: rightHigh, end: rightLow, spots: (.right, .right)),
            Segment(start: rightLow, end: bottomRight, spots: (.right, .bottom)),
            Segment(start: bottomRight, end: bottomLeft, spots: (.bottom, .bottom)),
            Segment(start: bottomLeft, end: leftLow, spots: (.bottom, .left)),
            Segment(start: leftLow, end: leftHigh, spots: (.left, .left)),
            Segment(start: leftHigh, end: topLeft, spots: (.left, .top)),
        ]
    }

    /// All the way round.
    public var length: Double { segments.reduce(0) { $0 + $1.length } }

    /// How far along the path a spot is.
    public func distance(of spot: PerchSpot, along: Double) -> Double {
        let index = switch spot {
        case .top, .face: 0
        case .right: 2
        case .bottom: 4
        case .left: 6
        }
        let edge = segments[index]
        let before = segments[..<index].reduce(0) { $0 + $1.length }
        let wanted = CGPoint(x: widget.minX + along * widget.width, y: widget.minY + along * widget.height)
        // How far along this edge (edges run in a straight line, so measure on one axis).
        let offset: CGFloat = switch spot {
        case .top, .face: min(max(wanted.x, edge.start.x), edge.end.x) - edge.start.x
        case .bottom: edge.start.x - max(min(wanted.x, edge.start.x), edge.end.x)
        case .right: edge.start.y - max(min(wanted.y, edge.start.y), edge.end.y)
        case .left: min(max(wanted.y, edge.start.y), edge.end.y) - edge.start.y
        }
        return before + Double(offset)
    }

    /// The spot and point at a distance along the path (wrapping round).
    public func place(at distance: Double) -> (spot: PerchSpot, along: Double, point: CGPoint) {
        let total = length
        guard total > 0 else { return (.top, 0.5, CGPoint(x: widget.midX, y: widget.maxY)) }
        var d = distance.truncatingRemainder(dividingBy: total)
        if d < 0 { d += total }
        var segment = segments[segments.count - 1]
        var into = segment.length
        for candidate in segments {
            if d <= candidate.length {
                segment = candidate
                into = d
                break
            }
            d -= candidate.length
        }
        let fraction = segment.length > 0 ? into / segment.length : 0
        let point = CGPoint(x: segment.start.x + (segment.end.x - segment.start.x) * fraction,
                            y: segment.start.y + (segment.end.y - segment.start.y) * fraction)
        let spot = fraction < 0.5 ? segment.spots.0 : segment.spots.1
        let along: Double = switch spot {
        case .top, .bottom, .face: widget.width > 0 ? Double((point.x - widget.minX) / widget.width) : 0.5
        case .left, .right: widget.height > 0 ? Double((point.y - widget.minY) / widget.height) : 0.5
        }
        return (spot, along, point)
    }
}

/// Makes the hero wander round his widget at random: he stays put for a random while
/// (about `wanderEvery` on average, but any time from minutes to many hours), then walks or
/// climbs to a random spot, the shorter way round. Hanging underneath he now and then gets
/// out his binoculars and spies on the widget. Times are seconds on any steady clock.
public struct PerchRoamer: Sendable {
    /// How long a spy session lasts.
    public static let spySeconds: ClosedRange<Double> = 5...8
    /// On average how often he spies while hanging underneath.
    public static let spyEvery: Double = 10 * 60
    /// The chance he spies right after arriving underneath.
    public static let spyOnArrival = 0.5

    public enum Event: Equatable, Sendable {
        /// He set off; `trip` says the way.
        case departed
        /// He settled somewhere new (worth remembering).
        case arrived
        case startedSpying
        case stoppedSpying
    }

    /// A walk round the widget: from a distance along the path, this far, this way (+1 or -1).
    public struct Trip: Equatable, Sendable {
        public var start: Double
        public var length: Double
        public var direction: Double
        public var destination: PerchState
        var travelled: Double = 0

        /// How far along the path he is now.
        public var position: Double { start + travelled * direction }
    }

    public private(set) var state: PerchState
    public private(set) var trip: Trip?
    public private(set) var wanderEvery: Double
    private var nextTrip: Double
    private var nextSpy: Double = .infinity
    private var spyEnds: Double?

    public init(spot: PerchSpot, along: Double, now: Double, wanderEvery: Double,
                random: inout some RandomNumberGenerator) {
        state = PerchState(spot: spot, along: along)
        self.wanderEvery = wanderEvery
        nextTrip = now + Self.wait(averaging: wanderEvery, random: &random)
        planSpying(from: now, random: &random)
    }

    public var isMoving: Bool { trip != nil }

    /// Changes how often he wanders, starting a fresh random wait.
    public mutating func setWanderEvery(_ seconds: Double, now: Double, random: inout some RandomNumberGenerator) {
        guard seconds != wanderEvery else { return }
        wanderEvery = seconds
        nextTrip = now + Self.wait(averaging: seconds, random: &random)
    }

    /// Moves time on by `dt`.
    /// - Parameters:
    ///   - speed: walking speed in points per second.
    ///   - paused: the mouse is over him: don't set off or start spying (a walk in progress finishes).
    public mutating func advance(
        to now: Double, dt: Double, path: PerchPath, speed: Double, paused: Bool,
        random: inout some RandomNumberGenerator
    ) -> Event? {
        if var trip {
            trip.travelled += speed * dt
            if trip.travelled >= trip.length {
                self.trip = nil
                state = trip.destination
                nextTrip = now + Self.wait(averaging: wanderEvery, random: &random)
                planSpying(from: now, random: &random)
                if state.spot == .bottom, Double.random(in: 0..<1, using: &random) < Self.spyOnArrival {
                    startSpying(at: now, random: &random)
                }
                return .arrived
            }
            let place = path.place(at: trip.position)
            state = PerchState(spot: place.spot, along: place.along, activity: .moving)
            self.trip = trip
            return nil
        }

        if let spyEnds {
            guard now >= spyEnds else { return nil }
            self.spyEnds = nil
            state.activity = .resting
            planSpying(from: now, random: &random)
            return .stoppedSpying
        }

        if paused {
            nextTrip = max(nextTrip, now + 2)
            nextSpy = max(nextSpy, now + 2)
            return nil
        }
        if now >= nextTrip {
            return setOff(path: path, now: now, random: &random)
        }
        if now >= nextSpy {
            startSpying(at: now, random: &random)
            return .startedSpying
        }
        return nil
    }

    /// Sets off for a random spot (anywhere is as likely as anywhere else).
    private mutating func setOff(path: PerchPath, now: Double, random: inout some RandomNumberGenerator) -> Event? {
        var destination = PerchState(spot: PerchSpot.allCases.randomElement(using: &random) ?? .top,
                                     along: Double.random(in: 0.1...0.9, using: &random))
        // Same edge: make it worth the walk.
        if destination.spot == state.spot, abs(destination.along - state.along) < 0.3 {
            destination.along = state.along < 0.5 ? Double.random(in: 0.65...0.9, using: &random)
                                                  : Double.random(in: 0.1...0.35, using: &random)
        }
        return travel(to: destination, path: path, now: now, random: &random)
    }

    /// Sets off the shorter way round towards `destination`.
    mutating func travel(
        to destination: PerchState, path: PerchPath, now: Double, random: inout some RandomNumberGenerator
    ) -> Event? {
        let from = path.distance(of: state.spot, along: state.along)
        let to = path.distance(of: destination.spot, along: destination.along)
        let length = path.length
        var forward = length > 0 ? (to - from).truncatingRemainder(dividingBy: length) : 0
        if forward < 0 { forward += length }
        let backward = length - forward
        let (distance, direction) = forward <= backward ? (forward, 1.0) : (backward, -1.0)
        guard distance >= 1 else {
            // Already there (say, from the peek spot to sitting just above it).
            state = destination
            nextTrip = now + Self.wait(averaging: wanderEvery, random: &random)
            planSpying(from: now, random: &random)
            return .arrived
        }
        trip = Trip(start: from, length: distance, direction: direction, destination: destination)
        state.activity = .moving
        return .departed
    }

    private mutating func startSpying(at now: Double, random: inout some RandomNumberGenerator) {
        state.activity = .spying
        spyEnds = now + Double.random(in: Self.spySeconds, using: &random)
    }

    private mutating func planSpying(from now: Double, random: inout some RandomNumberGenerator) {
        nextSpy = state.spot == .bottom ? now + Self.wait(averaging: Self.spyEvery, random: &random) : .infinity
    }

    /// A random wait with this average: usually around it, sometimes much shorter or longer,
    /// with no pattern to when the next one comes.
    static func wait(averaging mean: Double, random: inout some RandomNumberGenerator) -> Double {
        -mean * log(1 - Double.random(in: 0..<1, using: &random))
    }
}
