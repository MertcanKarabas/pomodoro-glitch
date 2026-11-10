import Foundation
import Testing
@testable import SpiderCore

private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
private let minute: TimeInterval = 60

private func at(_ minutes: Double) -> Date { t0.addingTimeInterval(minutes * minute) }

@Suite("TimerState")
struct TimerStateTests {
    let settings = PomodoroSettings.standard

    @Test func initialStateIsIdleWorkRoundOne() {
        let state = TimerState.initial(settings: settings, now: t0)
        #expect(state.status == .idle)
        #expect(state.phase == .work)
        #expect(state.round == 1)
        #expect(state.remaining(at: at(10)) == 25 * minute)
        #expect(state.progress(at: at(10)) == 0)
    }

    @Test func startCountsDown() {
        let state = TimerState.initial(settings: settings, now: t0).started(at: t0)
        #expect(state.status == .running)
        #expect(state.remaining(at: at(1)) == 24 * minute)
        #expect(abs(state.progress(at: at(5)) - 0.2) < 0.000_001)
        #expect(state.endsAt == at(25))
    }

    @Test func pauseFreezesAndResumeContinues() {
        let paused = TimerState.initial(settings: settings, now: t0)
            .started(at: t0)
            .paused(at: at(1))
        #expect(paused.status == .paused)
        #expect(paused.remaining(at: at(10)) == 24 * minute)

        let resumed = paused.started(at: at(10))
        #expect(resumed.status == .running)
        #expect(resumed.remaining(at: at(11)) == 23 * minute)
        #expect(resumed.endsAt == at(34))
    }

    @Test func startWhileRunningChangesNothing() {
        let running = TimerState.initial(settings: settings, now: t0).started(at: t0)
        #expect(running.started(at: at(3)) == running)
    }

    @Test func remainingNeverGoesBelowZero() {
        let running = TimerState.initial(settings: settings, now: t0).started(at: t0)
        #expect(running.remaining(at: at(90)) == 0)
        #expect(running.progress(at: at(90)) == 1)
    }

    @Test func workEndStartsShortBreakAtEndTime() {
        let running = TimerState.initial(settings: settings, now: t0).started(at: t0)
        let (state, finished) = running.resolved(at: at(26), settings: settings)
        #expect(finished == [.work])
        #expect(state.phase == .shortBreak)
        #expect(state.status == .running)
        #expect(state.startedAt == at(25))
        #expect(state.remaining(at: at(26)) == 4 * minute)
        #expect(state.round == 1)
    }

    @Test func breakEndWaitsForNextWorkRound() {
        let running = TimerState.initial(settings: settings, now: t0).started(at: t0)
        let (state, finished) = running.resolved(at: at(40), settings: settings)
        #expect(finished == [.work, .shortBreak])
        #expect(state.phase == .work)
        #expect(state.status == .idle)
        #expect(state.round == 2)
        #expect(state.remaining(at: at(40)) == 25 * minute)
    }

    @Test func fourthRoundGetsLongBreakThenStartsOver() {
        var state = TimerState(phase: .work, round: 4, duration: 25 * minute, startedAt: t0, updatedAt: t0)
        state = state.resolved(at: at(26), settings: settings).state
        #expect(state.phase == .longBreak)
        #expect(state.duration == 15 * minute)

        state = state.resolved(at: at(41), settings: settings).state
        #expect(state.phase == .work)
        #expect(state.round == 1)
        #expect(state.status == .idle)
    }

    @Test func resolvingKeepsUpdatedAt() {
        let running = TimerState.initial(settings: settings, now: t0).started(at: t0)
        let state = running.resolved(at: at(30), settings: settings).state
        #expect(state.updatedAt == t0)
    }

    @Test func resolvingBeforeEndChangesNothing() {
        let running = TimerState.initial(settings: settings, now: t0).started(at: t0)
        let (state, finished) = running.resolved(at: at(24.9), settings: settings)
        #expect(state == running)
        #expect(finished.isEmpty)
    }

    @Test func autoStartWorkChainsAllPhases() {
        var auto = settings
        auto.autoStartWork = true
        let running = TimerState.initial(settings: auto, now: t0).started(at: t0)
        // work 25 + break 5 + work 25 = 55, then 2 min into round 2 break.
        let (state, finished) = running.resolved(at: at(57), settings: auto)
        #expect(finished == [.work, .shortBreak, .work])
        #expect(state.phase == .shortBreak)
        #expect(state.round == 2)
        #expect(state.remaining(at: at(57)) == 3 * minute)
    }

    @Test func noAutoStartBreaksMeansBreakWaits() {
        var manual = settings
        manual.autoStartBreaks = false
        let running = TimerState.initial(settings: manual, now: t0).started(at: t0)
        let state = running.resolved(at: at(30), settings: manual).state
        #expect(state.phase == .shortBreak)
        #expect(state.status == .idle)
    }

    @Test func skipWorkGoesToBreakNow() {
        let running = TimerState.initial(settings: settings, now: t0).started(at: t0)
        let state = running.skipped(at: at(3), settings: settings)
        #expect(state.phase == .shortBreak)
        #expect(state.startedAt == at(3))
        #expect(state.updatedAt == at(3))
    }

    @Test func skipBreakGoesToIdleWork() {
        let onBreak = TimerState(phase: .shortBreak, round: 2, duration: 5 * minute, startedAt: t0, updatedAt: t0)
        let state = onBreak.skipped(at: at(1), settings: settings)
        #expect(state.phase == .work)
        #expect(state.round == 3)
        #expect(state.status == .idle)
    }

    @Test func resetGoesBackToStart() {
        let onBreak = TimerState(phase: .longBreak, round: 4, duration: 15 * minute, startedAt: t0, updatedAt: t0)
        let state = onBreak.reset(at: at(2), settings: settings)
        #expect(state == .initial(settings: settings, now: at(2)))
    }

    @Test func newSettingsApplyOnlyWhenIdle() {
        var short = settings
        short.workMinutes = 50
        let idle = TimerState.initial(settings: settings, now: t0)
        #expect(idle.applying(short, at: t0).duration == 50 * minute)

        let running = idle.started(at: t0)
        #expect(running.applying(short, at: at(1)) == running)
    }

    @Test func nextPhaseLabels() {
        let work = TimerState.initial(settings: settings, now: t0)
        #expect(work.nextPhase(settings: settings).phase == .shortBreak)

        let lastWork = TimerState(phase: .work, round: 4, duration: 25 * minute, updatedAt: t0)
        #expect(lastWork.nextPhase(settings: settings).phase == .longBreak)

        let onBreak = TimerState(phase: .shortBreak, round: 1, duration: 5 * minute, updatedAt: t0)
        #expect(onBreak.nextPhase(settings: settings) == (.work, 2))
    }

    @Test func completedRounds() {
        #expect(TimerState(phase: .work, round: 1, duration: 1, updatedAt: t0).completedRounds == 0)
        #expect(TimerState(phase: .shortBreak, round: 1, duration: 1, updatedAt: t0).completedRounds == 1)
        #expect(TimerState(phase: .work, round: 3, duration: 1, updatedAt: t0).completedRounds == 2)
    }

    @Test func settingsAreClamped() {
        let odd = PomodoroSettings(workMinutes: 0, shortBreakMinutes: 500, roundsBeforeLongBreak: 0)
        #expect(odd.duration(of: .work) == 1 * minute)
        #expect(odd.duration(of: .shortBreak) == 120 * minute)
        #expect(odd.rounds == 1)
    }

    @Test func stateSurvivesJSON() throws {
        let state = TimerState.initial(settings: settings, now: t0).started(at: t0).paused(at: at(2))
        let data = try JSONEncoder().encode(state)
        #expect(try JSONDecoder().decode(TimerState.self, from: data) == state)
    }
}

@Suite("TimeFormat")
struct TimeFormatTests {
    @Test(arguments: [
        (1500.0, "25:00"),
        (1499.2, "25:00"),
        (59.2, "1:00"),
        (0.4, "0:01"),
        (0.0, "0:00"),
        (-5.0, "0:00"),
        (3600.0, "1:00:00"),
        (3725.0, "1:02:05"),
    ])
    func clock(seconds: Double, expected: String) {
        #expect(TimeFormat.clock(seconds) == expected)
    }
}
