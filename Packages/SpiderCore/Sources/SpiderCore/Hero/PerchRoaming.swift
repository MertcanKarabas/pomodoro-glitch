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

    public func pose(timerPose: HeroPose, reaction: HeroReaction?) -> HeroPose {
        switch activity {
        case .resting:
            return spot.pose(timerPose: timerPose, reaction: reaction)
        case .spying:
            return spot == .bottom ? .spying : spot.pose(timerPose: timerPose, reaction: reaction)
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

/// Makes the hero wander round his widget: rest a while, then walk or climb somewhere else
/// (often up to sit on top), and sometimes sneak underneath to spy on it. With the timer
/// stopped he heads to the top for a nap. Times are seconds on any steady clock.
public struct PerchRoamer: Sendable {
    public static let firstRestSeconds: Double = 8
    public static let restSeconds: ClosedRange<Double> = 10...25
    public static let spySeconds: ClosedRange<Double> = 4...7
    /// While napping, how often to check whether the timer started.
    public static let napCheckSeconds: Double = 3

    public private(set) var state: PerchState
    private var trip: Trip?
    private var nextDecision: Double

    private struct Trip: Sendable {
        var position: Double
        var remaining: Double
        var direction: Double
        var destination: PerchState
    }

    public init(spot: PerchSpot, along: Double, now: Double) {
        state = PerchState(spot: spot, along: along)
        nextDecision = now + Self.firstRestSeconds
    }

    public var isMoving: Bool { trip != nil }

    /// While moving, how far along the path he is (use `PerchPath.place(at:)` for the exact
    /// point, which also covers the hops round corners).
    public var travelDistance: Double? { trip?.position }

    /// Moves time on by `dt`.
    /// - Parameters:
    ///   - speed: walking speed in points per second.
    ///   - calm: the timer isn't running: go and nap on top.
    ///   - paused: the mouse is over him: hold still so he can be picked up.
    /// - Returns: true when he settled somewhere new (worth remembering).
    public mutating func advance(
        to now: Double, dt: Double, path: PerchPath, speed: Double, calm: Bool, paused: Bool,
        random: inout some RandomNumberGenerator
    ) -> Bool {
        if paused {
            nextDecision = max(nextDecision, now + 2)
            return false
        }
        if var trip {
            let step = speed * dt
            if step >= trip.remaining {
                self.trip = nil
                state = trip.destination
                nextDecision = now + pause(for: state.activity, random: &random)
                return true
            }
            trip.position += step * trip.direction
            trip.remaining -= step
            let place = path.place(at: trip.position)
            state = PerchState(spot: place.spot, along: place.along, activity: .moving)
            self.trip = trip
            return false
        }

        guard now >= nextDecision else { return false }
        if calm {
            if state.spot == .top, state.activity == .resting {
                nextDecision = now + Self.napCheckSeconds
                return false
            }
            return travel(to: PerchState(spot: .top, along: Double.random(in: 0.3...0.7, using: &random)),
                          path: path, now: now, random: &random)
        }
        if state.activity == .spying {
            // Seen enough: hang there a while.
            state.activity = .resting
            nextDecision = now + pause(for: .resting, random: &random)
            return true
        }

        // Somewhere new, most often up on top.
        let roll = Double.random(in: 0..<1, using: &random)
        let spot: PerchSpot = switch roll {
        case ..<0.4: .top
        case ..<0.65: .bottom
        case ..<0.8: .face
        case ..<0.9: .left
        default: .right
        }
        let along = Double.random(in: 0.15...0.85, using: &random)
        let spies = spot == .bottom && Double.random(in: 0..<1, using: &random) < 0.6
        return travel(to: PerchState(spot: spot, along: along, activity: spies ? .spying : .resting),
                      path: path, now: now, random: &random)
    }

    /// Sets off the shorter way round towards `destination`. Returns true if he's already there.
    mutating func travel(
        to destination: PerchState, path: PerchPath, now: Double, random: inout some RandomNumberGenerator
    ) -> Bool {
        let from = path.distance(of: state.spot, along: state.along)
        let to = path.distance(of: destination.spot, along: destination.along)
        let length = path.length
        var forward = length > 0 ? (to - from).truncatingRemainder(dividingBy: length) : 0
        if forward < 0 { forward += length }
        let backward = length - forward
        let (distance, direction) = forward <= backward ? (forward, 1.0) : (backward, -1.0)
        guard distance >= 1 else {
            state = destination
            nextDecision = now + pause(for: destination.activity, random: &random)
            return true
        }
        trip = Trip(position: from, remaining: distance, direction: direction, destination: destination)
        state.activity = .moving
        return false
    }

    private func pause(for activity: PerchActivity, random: inout some RandomNumberGenerator) -> Double {
        activity == .spying
            ? Double.random(in: Self.spySeconds, using: &random)
            : Double.random(in: Self.restSeconds, using: &random)
    }
}
