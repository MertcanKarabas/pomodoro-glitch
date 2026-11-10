import Foundation
import Testing
@testable import SpiderCore

private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
private func at(_ minutes: Double) -> Date { t0.addingTimeInterval(minutes * 60) }

@Suite("HeroPlacement")
struct HeroPlacementTests {
    let settings = PomodoroSettings.standard

    private func placement(_ state: TimerState, _ minutes: Double, finished: FinishedPhase? = nil) -> HeroPlacement {
        HeroPlacement(state: state, now: at(minutes), lastFinished: finished)
    }

    @Test func notStartedSleepsAtTop() {
        let idle = TimerState.initial(settings: settings, now: t0)
        #expect(placement(idle, 3) == HeroPlacement(pose: .sleeping, drop: 0, swings: false))
    }

    @Test func workDropsAsTimePasses() {
        let running = TimerState.initial(settings: settings, now: t0).started(at: t0)
        let half = placement(running, 12.5)
        #expect(half.pose == .hanging)
        #expect(abs(half.drop - 0.5) < 0.0001)
        #expect(half.swings)
        #expect(placement(running, 25).drop == 1)
    }

    @Test func pausedHangsStill() {
        let paused = TimerState.initial(settings: settings, now: t0).started(at: t0).paused(at: at(5))
        let result = placement(paused, 9)
        #expect(result.pose == .hanging)
        #expect(abs(result.drop - 0.2) < 0.0001)
        #expect(!result.swings)
    }

    @Test func breakClimbsBackUp() {
        let onBreak = TimerState(phase: .shortBreak, round: 1, duration: 5 * 60, startedAt: t0, updatedAt: t0)
        #expect(placement(onBreak, 0).drop == 1)
        let mid = placement(onBreak, 4)
        #expect(mid.pose == .climbing)
        #expect(abs(mid.drop - 0.2) < 0.0001)
    }

    @Test func breakWaitingToStartWavesAtBottom() {
        let waiting = TimerState(phase: .shortBreak, round: 1, duration: 5 * 60, updatedAt: t0)
        #expect(placement(waiting, 1) == HeroPlacement(pose: .waving, drop: 1, swings: false))
    }

    @Test func wavesForFiveSecondsAfterPhaseEnds() {
        let onBreak = TimerState(phase: .shortBreak, round: 1, duration: 5 * 60, startedAt: t0, updatedAt: t0)
        let finished = FinishedPhase(phase: .work, at: t0)
        #expect(HeroPlacement(state: onBreak, now: t0.addingTimeInterval(4), lastFinished: finished).pose == .waving)
        #expect(HeroPlacement(state: onBreak, now: t0.addingTimeInterval(6), lastFinished: finished).pose == .climbing)
    }

    @Test func wavesAtTopWhenBreakEnds() {
        let idleWork = TimerState(phase: .work, round: 2, duration: 25 * 60, updatedAt: t0)
        let finished = FinishedPhase(phase: .shortBreak, at: t0)
        let result = HeroPlacement(state: idleWork, now: t0.addingTimeInterval(1), lastFinished: finished)
        #expect(result == HeroPlacement(pose: .waving, drop: 0, swings: true))
    }
}

@MainActor
@Suite("TimerController hero events")
struct TimerControllerHeroTests {
    @Test func phaseEndIsRecordedForTheWave() {
        let clock = FakeClock()
        let defaults = UserDefaults(suiteName: "SpiderCoreTests-\(UUID().uuidString)")!
        let controller = TimerController(storage: TimerStorage(defaults: defaults), clock: { clock.now })
        #expect(controller.lastFinished == nil)
        controller.start()
        clock.advance(minutes: 25.1)
        controller.tick()
        #expect(controller.lastFinished == FinishedPhase(phase: .work, at: clock.now))
    }
}
