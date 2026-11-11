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
    let dt = 1.0 / 10
    let twiceADay = 12.0 * 60 * 60

    /// Steps time on until he next sets off (or `limit` seconds pass). Returns the time.
    private func waitForTrip(_ roamer: inout PerchRoamer, from start: Double, limit: Double, step: Double = 30,
                             random: inout SeededRandom) -> Double? {
        var time = start
        while time < start + limit {
            time += step
            if roamer.advance(to: time, dt: step, path: path, speed: 40, paused: false, random: &random) == .departed {
                return time
            }
        }
        return nil
    }

    /// Walks until he arrives. Returns the time.
    private func walk(_ roamer: inout PerchRoamer, from start: Double, random: inout SeededRandom) -> Double {
        var time = start
        for _ in 0..<10_000 where roamer.isMoving {
            time += dt
            _ = roamer.advance(to: time, dt: dt, path: path, speed: 40, paused: false, random: &random)
        }
        return time
    }

    @Test func staysPutForAGoodWhile() {
        // Twice a day on average: over the first minute he almost never moves.
        var moved = 0
        for seed in UInt64(1)...200 {
            var random = SeededRandom(state: seed)
            var roamer = PerchRoamer(spot: .bottom, along: 0.5, now: 0, wanderEvery: twiceADay, random: &random)
            if waitForTrip(&roamer, from: 0, limit: 60, step: 1, random: &random) != nil { moved += 1 }
        }
        #expect(moved <= 3)
    }

    @Test func waitsAreRandomButAverageOut() {
        var random = SeededRandom(state: 42)
        var waits: [Double] = []
        for _ in 0..<2000 {
            waits.append(PerchRoamer.wait(averaging: 600, random: &random))
        }
        let average = waits.reduce(0, +) / Double(waits.count)
        #expect(abs(average - 600) < 60)
        // Some come quickly, some take far longer: no fixed schedule.
        #expect(waits.contains { $0 < 60 })
        #expect(waits.contains { $0 > 1800 })
    }

    @Test func goesAnywhereNotJustUpTop() {
        var counts: [PerchSpot: Int] = [:]
        for seed in UInt64(1)...300 {
            var random = SeededRandom(state: seed)
            var roamer = PerchRoamer(spot: .left, along: 0.5, now: 0, wanderEvery: 60, random: &random)
            guard let left = waitForTrip(&roamer, from: 0, limit: 3600, step: 5, random: &random) else { continue }
            _ = walk(&roamer, from: left, random: &random)
            counts[roamer.state.spot, default: 0] += 1
        }
        for spot in PerchSpot.allCases {
            // About a fifth each.
            #expect((counts[spot] ?? 0) > 35, "\(spot): \(counts[spot] ?? 0)")
        }
    }

    @Test func settlesWhereHeWasHeaded() {
        var random = SeededRandom(state: 5)
        var roamer = PerchRoamer(spot: .top, along: 0.2, now: 0, wanderEvery: twiceADay, random: &random)
        #expect(roamer.travel(to: PerchState(spot: .right, along: 0.5), path: path, now: 0, random: &random) == .departed)
        #expect(roamer.state.activity == .moving)
        _ = walk(&roamer, from: 0, random: &random)
        #expect(roamer.state == PerchState(spot: .right, along: 0.5))
    }

    @Test func underneathHeSometimesSpies() {
        var spied = 0
        for seed in UInt64(1)...40 {
            var random = SeededRandom(state: seed)
            var roamer = PerchRoamer(spot: .top, along: 0.5, now: 0, wanderEvery: twiceADay, random: &random)
            _ = roamer.travel(to: PerchState(spot: .bottom, along: 0.5), path: path, now: 0, random: &random)
            let arrived = walk(&roamer, from: 0, random: &random)
            if roamer.state.activity == .spying {
                spied += 1
                // And puts the binoculars away after a few seconds.
                let event = roamer.advance(to: arrived + PerchRoamer.spySeconds.upperBound + 0.1, dt: dt, path: path,
                                           speed: 40, paused: false, random: &random)
                #expect(event == .stoppedSpying)
                #expect(roamer.state.activity == .resting)
            }
        }
        #expect(spied > 8 && spied < 32)
    }

    @Test func holdsOffWhileTheMouseIsOverHim() {
        var random = SeededRandom(state: 9)
        var roamer = PerchRoamer(spot: .top, along: 0.5, now: 0, wanderEvery: 1, random: &random)
        for second in 1...30 {
            #expect(roamer.advance(to: Double(second), dt: 1, path: path, speed: 40, paused: true, random: &random) == nil)
        }
        #expect(!roamer.isMoving)
    }

    @Test func changingHowOftenStartsAFreshWait() {
        var random = SeededRandom(state: 11)
        var roamer = PerchRoamer(spot: .top, along: 0.5, now: 0, wanderEvery: twiceADay, random: &random)
        roamer.setWanderEvery(5, now: 0, random: &random)
        #expect(waitForTrip(&roamer, from: 0, limit: 600, step: 1, random: &random) != nil)
    }

    @Test func takesTheShorterWayRound() {
        var random = SeededRandom(state: 3)
        // Low on the left side to the left end of the bottom: back round the corner, not all the way.
        var roamer = PerchRoamer(spot: .left, along: 0.2, now: 0, wanderEvery: twiceADay, random: &random)
        _ = roamer.travel(to: PerchState(spot: .bottom, along: 0.15), path: path, now: 0, random: &random)
        #expect(roamer.trip?.direction == -1)
        var spots: Set<PerchSpot> = []
        for step in 1...600 where roamer.isMoving {
            _ = roamer.advance(to: Double(step) * dt, dt: dt, path: path, speed: 40, paused: false, random: &random)
            spots.insert(roamer.state.spot)
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
