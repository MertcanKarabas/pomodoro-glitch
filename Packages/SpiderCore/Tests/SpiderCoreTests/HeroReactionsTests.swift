import CoreGraphics
import Testing
@testable import SpiderCore

@Suite("HeroMood")
struct HeroMoodTests {
    /// Moves the mouse left and right between two x positions, `strokes` times, at `y`.
    private func shake(_ mood: inout HeroMood, strokes: Int, width: CGFloat = 80,
                       from start: Double = 0, strokeTime: Double = 0.12) -> Double {
        var time = start
        for stroke in 0..<strokes {
            let fromX: CGFloat = stroke.isMultiple(of: 2) ? 0 : width
            let toX: CGFloat = stroke.isMultiple(of: 2) ? width : 0
            for step in 1...6 {
                time += strokeTime / 6
                let x = fromX + (toX - fromX) * CGFloat(step) / 6
                mood.dragged(to: CGPoint(x: x, y: 500), at: time)
            }
        }
        return time
    }

    @Test func calmByDefault() {
        #expect(HeroMood().reaction(at: 0) == nil)
    }

    @Test func aQuickShakeMakesHimDizzy() {
        var mood = HeroMood()
        mood.dragged(to: CGPoint(x: 0, y: 500), at: 0)
        let end = shake(&mood, strokes: 6)
        #expect(mood.reaction(at: end) == .dizzy)
    }

    @Test func dizzinessWearsOff() {
        var mood = HeroMood()
        mood.dragged(to: CGPoint(x: 0, y: 500), at: 0)
        let end = shake(&mood, strokes: 6)
        mood.dropped()
        // Counted from the last turnaround, a moment before the shake ended.
        #expect(mood.reaction(at: end + HeroMood.dizzySeconds - 0.3) == .dizzy)
        #expect(mood.reaction(at: end + HeroMood.dizzySeconds + 0.1) == nil)
    }

    @Test func movingHimAcrossTheScreenIsNotShaking() {
        var mood = HeroMood()
        for step in 0...100 {
            mood.dragged(to: CGPoint(x: CGFloat(step) * 8, y: 500 - CGFloat(step)), at: Double(step) * 0.016)
        }
        #expect(mood.reaction(at: 2) == nil)
    }

    @Test func smallWobblesAreNotShaking() {
        var mood = HeroMood()
        mood.dragged(to: CGPoint(x: 0, y: 500), at: 0)
        let end = shake(&mood, strokes: 10, width: 15)
        #expect(mood.reaction(at: end) == nil)
    }

    @Test func slowBackAndForthIsNotShaking() {
        var mood = HeroMood()
        mood.dragged(to: CGPoint(x: 0, y: 500), at: 0)
        let end = shake(&mood, strokes: 6, strokeTime: 0.8)
        #expect(mood.reaction(at: end) == nil)
    }

    @Test func shakingALotMakesHimGrumpy() {
        var mood = HeroMood()
        mood.dragged(to: CGPoint(x: 0, y: 500), at: 0)
        let end = shake(&mood, strokes: 20)
        #expect(mood.reaction(at: end) == .grumpy)
        #expect(mood.reaction(at: end + HeroMood.grumpySeconds + 0.1) == nil)
    }

    @Test func afterCalmingDownAShakeOnlyMakesHimDizzyAgain() {
        var mood = HeroMood()
        mood.dragged(to: CGPoint(x: 0, y: 500), at: 0)
        var end = shake(&mood, strokes: 20)
        #expect(mood.reaction(at: end) == .grumpy)
        mood.dropped()
        let later = end + HeroMood.grumpySeconds + 1
        mood.dragged(to: CGPoint(x: 0, y: 500), at: later)
        end = shake(&mood, strokes: 6, from: later)
        #expect(mood.reaction(at: end) == .dizzy)
    }

    @Test func hoveringWavesHelloAndLingersBriefly() {
        var mood = HeroMood()
        mood.hover(true, at: 1)
        #expect(mood.reaction(at: 1) == .hello)
        mood.hover(false, at: 2)
        #expect(mood.reaction(at: 2 + HeroMood.helloLinger - 0.1) == .hello)
        #expect(mood.reaction(at: 2 + HeroMood.helloLinger + 0.1) == nil)
    }

    @Test func dizzyBeatsHello() {
        var mood = HeroMood()
        mood.hover(true, at: 0)
        mood.dragged(to: CGPoint(x: 0, y: 500), at: 0)
        let end = shake(&mood, strokes: 6)
        #expect(mood.reaction(at: end) == .dizzy)
    }

    @Test func reactionsMapToPoses() {
        #expect(HeroReaction.hello.pose == .waving)
        #expect(HeroReaction.dizzy.pose == .dizzy)
        #expect(HeroReaction.grumpy.pose == .grumpy)
    }
}

@Suite("HeroDangle")
struct HeroDangleTests {
    private let dt = 1.0 / 60

    @Test func carriedRightHisBodySwingsLeftBehindTheHands() {
        var dangle = HeroDangle(length: 50)
        var x: CGFloat = 0
        var speed: CGFloat = 0
        var mostLeft = 0.0
        for _ in 0..<15 {
            speed += 40
            x += speed
            dangle.step(pivot: CGPoint(x: x, y: 500), dt: dt)
            mostLeft = min(mostLeft, dangle.angle)
        }
        #expect(mostLeft < -0.15)
    }

    @Test func hangingStillStaysStraight() {
        var dangle = HeroDangle(length: 50)
        for _ in 0..<60 {
            dangle.step(pivot: CGPoint(x: 100, y: 500), dt: dt)
        }
        #expect(abs(dangle.angle) < 0.001)
        #expect(dangle.isSettled)
    }

    @Test func settlesAfterBeingPutDown() {
        var dangle = HeroDangle(length: 50)
        var x: CGFloat = 0
        for frame in 0..<20 {
            x += frame.isMultiple(of: 2) ? 60 : -60
            dangle.step(pivot: CGPoint(x: x, y: 500), dt: dt)
        }
        for _ in 0..<(60 * 5) {
            dangle.step(pivot: nil, dt: dt)
        }
        #expect(dangle.isSettled)
    }

    @Test func wildFlicksNeverFlipHimOver() {
        var dangle = HeroDangle(length: 35)
        var x: CGFloat = 0
        for frame in 0..<200 {
            x += frame.isMultiple(of: 3) ? 400 : -200
            dangle.step(pivot: CGPoint(x: x, y: 500), dt: dt)
            #expect(abs(dangle.angle) <= HeroDangle.maxAngle)
        }
    }
}
