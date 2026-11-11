import Foundation
import Testing
@testable import SpiderCore

@Suite("HeroTask")
struct HeroTaskTests {
    let t0 = Date(timeIntervalSince1970: 1_000_000)
    let settings = PomodoroSettings.standard

    @Test func followsTheTimer() {
        let idle = TimerState.initial(settings: settings, now: t0)
        #expect(HeroTask(state: idle, now: t0, lastFinished: nil) == .asleep)

        let working = idle.started(at: t0)
        #expect(HeroTask(state: working, now: t0.addingTimeInterval(60), lastFinished: nil) == .working)

        let paused = working.paused(at: t0.addingTimeInterval(60))
        #expect(HeroTask(state: paused, now: t0.addingTimeInterval(120), lastFinished: nil) == .paused)

        let onBreak = working.skipped(at: t0.addingTimeInterval(60), settings: settings).started(at: t0.addingTimeInterval(61))
        #expect(HeroTask(state: onBreak, now: t0.addingTimeInterval(120), lastFinished: nil) == .onBreak)
    }

    @Test func cheersRightAfterAPhaseEnds() {
        let working = TimerState.initial(settings: settings, now: t0).started(at: t0)
        let finished = FinishedPhase(phase: .work, at: t0.addingTimeInterval(10))
        #expect(HeroTask(state: working, now: t0.addingTimeInterval(12), lastFinished: finished) == .cheering)
    }

    @Test func onHisWebABreakMixesClimbingAndScrolling() {
        let climb = HeroTask.breakClimbSeconds
        #expect(HeroTask.onBreak.webPose(timerPose: .climbing, at: 1) == .climbing)
        #expect(HeroTask.onBreak.webPose(timerPose: .climbing, at: climb + 1) == .hangingScrolling)
        let cycle = climb + HeroTask.breakScrollSeconds
        #expect(HeroTask.onBreak.webPose(timerPose: .climbing, at: cycle + 1) == .climbing)
        // Work, or the wave when a break ends, stay as they are.
        #expect(HeroTask.working.webPose(timerPose: .hanging, at: climb + 1) == .hanging)
        #expect(HeroTask.onBreak.webPose(timerPose: .waving, at: climb + 1) == .waving)
    }
}

@Suite("Menu bar time")
struct MenuBarTimeTests {
    @Test func showsWholeMinutesSoItChangesOnceAMinute() {
        #expect(TimeFormat.shortMinutes(25 * 60) == "25m")
        #expect(TimeFormat.shortMinutes(24 * 60 + 13) == "25m")
        #expect(TimeFormat.shortMinutes(24 * 60) == "24m")
        #expect(TimeFormat.shortMinutes(42) == "1m")
        // The same text all through a minute.
        let texts = Set(stride(from: 23.0 * 60 + 1, through: 24 * 60, by: 1).map(TimeFormat.shortMinutes))
        #expect(texts == ["24m"])
    }
}
