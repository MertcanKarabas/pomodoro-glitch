import CoreGraphics
import Testing
@testable import SpiderCore

/// Repeatable random numbers for tests.
struct SeededRandom: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

@Suite("PerchPath")
struct PerchPathTests {
    // A 250×200 card; edges stop 20 pt from the ends, sides 30 pt.
    let card = CGRect(x: 100, y: 100, width: 250, height: 200)
    var path: PerchPath { PerchPath(widget: card, edgeMargin: 20, sideMargin: 30) }

    @Test func lengthGoesAllTheWayRound() {
        // Edges, plus four hops round the corners (20 across, 30 down).
        let corner = Double(hypot(20.0, 30.0))
        #expect(abs(path.length - (2 * (210 + 140) + 4 * corner)) < 0.001)
    }

    @Test func everyPointOnThePathIsWhereHeWouldSit() {
        for spot in PerchSpot.allCases {
            for along in [0.0, 0.1, 0.5, 0.9, 1.0] {
                let place = path.place(at: path.distance(of: spot, along: along))
                let contact = PerchGeometry.contact(for: Perch(spot: spot, widget: card, along: along),
                                                    edgeMargin: 20, sideMargin: 30)
                #expect(abs(place.point.x - contact.x) < 0.001 && abs(place.point.y - contact.y) < 0.001,
                        "\(spot) \(along)")
            }
        }
    }

    @Test func goesRoundClockwise() {
        let corner = Double(hypot(20.0, 30.0))
        #expect(path.place(at: 10).spot == .top)
        #expect(path.place(at: 210 + corner + 50).spot == .right)
        #expect(path.place(at: 350 + 2 * corner + 100).spot == .bottom)
        #expect(path.place(at: 560 + 3 * corner + 50).spot == .left)
        #expect(path.place(at: path.length + 10).spot == .top)   // wrapped round
        #expect(path.place(at: -corner - 10).spot == .left)
    }

    @Test func noJumpsRoundTheCorners() {
        var previous = path.place(at: 0).point
        for step in stride(from: 1.0, through: path.length, by: 1) {
            let point = path.place(at: step).point
            #expect(hypot(point.x - previous.x, point.y - previous.y) <= 1.0001)
            previous = point
        }
    }
}

@Suite("PerchRoamer")
struct PerchRoamerTests {
    let card = CGRect(x: 100, y: 100, width: 250, height: 200)
    var path: PerchPath { PerchPath(widget: card, edgeMargin: 20, sideMargin: 30) }
    let dt = 1.0 / 30

    /// Runs until he stops moving (or gives up), returning the time.
    private func walk(_ roamer: inout PerchRoamer, from start: Double, calm: Bool = false,
                      random: inout SeededRandom) -> Double {
        var time = start
        for _ in 0..<10_000 {
            time += dt
            _ = roamer.advance(to: time, dt: dt, path: path, speed: 40, calm: calm, paused: false, random: &random)
            if !roamer.isMoving { break }
        }
        return time
    }

    @Test func restsAWhileWhereHeWasDropped() {
        var random = SeededRandom(state: 1)
        var roamer = PerchRoamer(spot: .bottom, along: 0.5, now: 0)
        _ = roamer.advance(to: 5, dt: dt, path: path, speed: 40, calm: false, paused: false, random: &random)
        #expect(!roamer.isMoving)
        #expect(roamer.state == PerchState(spot: .bottom, along: 0.5))
    }

    @Test func thenSetsOffAndSettlesSomewhere() {
        for seed in UInt64(1)...20 {
            var random = SeededRandom(state: seed)
            var roamer = PerchRoamer(spot: .left, along: 0.5, now: 0)
            _ = roamer.advance(to: PerchRoamer.firstRestSeconds + 0.1, dt: dt, path: path, speed: 40,
                               calm: false, paused: false, random: &random)
            _ = walk(&roamer, from: PerchRoamer.firstRestSeconds + 0.1, random: &random)
            #expect(!roamer.isMoving)
            #expect(roamer.state.activity != .moving)
            if roamer.state.activity == .spying {
                #expect(roamer.state.spot == .bottom)
            }
        }
    }

    @Test func oftenEndsUpSittingOnTop() {
        var tops = 0
        for seed in UInt64(1)...60 {
            var random = SeededRandom(state: seed)
            var roamer = PerchRoamer(spot: .bottom, along: 0.5, now: 0)
            _ = roamer.advance(to: 9, dt: dt, path: path, speed: 40, calm: false, paused: false, random: &random)
            _ = walk(&roamer, from: 9, random: &random)
            if roamer.state.spot == .top { tops += 1 }
        }
        #expect(tops >= 15)
    }

    @Test func withTheTimerStoppedHeNapsOnTop() {
        var random = SeededRandom(state: 7)
        var roamer = PerchRoamer(spot: .bottom, along: 0.3, now: 0)
        _ = roamer.advance(to: 9, dt: dt, path: path, speed: 40, calm: true, paused: false, random: &random)
        #expect(roamer.isMoving)
        let arrived = walk(&roamer, from: 9, calm: true, random: &random)
        #expect(roamer.state.spot == .top)
        #expect(roamer.state.activity == .resting)
        #expect(roamer.state.pose(timerPose: .sleeping, reaction: nil) == .sittingAsleep)
        // And stays there.
        _ = roamer.advance(to: arrived + 60, dt: dt, path: path, speed: 40, calm: true, paused: false, random: &random)
        #expect(!roamer.isMoving)
    }

    @Test func holdsStillWhileTheMouseIsOverHim() {
        var random = SeededRandom(state: 3)
        var roamer = PerchRoamer(spot: .top, along: 0.2, now: 0)
        _ = roamer.travel(to: PerchState(spot: .top, along: 0.8), path: path, now: 0, random: &random)
        let before = roamer.state
        _ = roamer.advance(to: 1, dt: dt, path: path, speed: 40, calm: false, paused: true, random: &random)
        #expect(roamer.state == before)
    }

    @Test func takesTheShorterWayRound() {
        var random = SeededRandom(state: 3)
        // Low on the left side to the left end of the bottom: back round the corner, not all the way.
        var roamer = PerchRoamer(spot: .left, along: 0.2, now: 0)
        _ = roamer.travel(to: PerchState(spot: .bottom, along: 0.15), path: path, now: 0, random: &random)
        var spots: Set<PerchSpot> = []
        for step in 1...600 {
            _ = roamer.advance(to: Double(step) * dt, dt: dt, path: path, speed: 40, calm: false, paused: false,
                               random: &random)
            spots.insert(roamer.state.spot)
            if !roamer.isMoving { break }
        }
        #expect(spots == [.left, .bottom])
    }

    @Test func walkingAndSpyingPoses() {
        #expect(PerchState(spot: .top, along: 0.5, activity: .moving).pose(timerPose: .hanging, reaction: nil) == .walking)
        #expect(PerchState(spot: .bottom, along: 0.5, activity: .moving).pose(timerPose: .hanging, reaction: nil)
                == .upsideDownWalking)
        #expect(PerchState(spot: .bottom, along: 0.5, activity: .spying).pose(timerPose: .hanging, reaction: nil) == .spying)
        #expect(PerchState(spot: .right, along: 0.5, activity: .moving).pose(timerPose: .hanging, reaction: nil) == .clinging)
        #expect(PerchState(spot: .bottom, along: 0.5).swings)
        #expect(!PerchState(spot: .bottom, along: 0.5, activity: .spying).swings)
    }
}
