import Foundation
import Testing
@testable import SpiderCore

private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
private func at(_ minutes: Double) -> Date { t0.addingTimeInterval(minutes * 60) }

@Suite("PhaseAlerts")
struct PhaseAlertsTests {
    let settings = PomodoroSettings.standard

    @Test func nothingWhenNotRunning() {
        let idle = TimerState.initial(settings: settings, now: t0)
        #expect(PhaseAlerts.upcoming(state: idle, settings: settings, now: t0).isEmpty)
        let paused = idle.started(at: t0).paused(at: at(1))
        #expect(PhaseAlerts.upcoming(state: paused, settings: settings, now: at(2)).isEmpty)
    }

    @Test func workThenAutoBreakGivesTwoAlerts() {
        let running = TimerState.initial(settings: settings, now: t0).started(at: t0)
        let alerts = PhaseAlerts.upcoming(state: running, settings: settings, now: t0)
        #expect(alerts.map(\.date) == [at(25), at(30)])
        #expect(alerts[0].title == "Work done!")
        #expect(alerts[0].body == "Time for a 5 min break.")
        #expect(alerts[1].title == "Break over")
        #expect(alerts[1].body == "Ready for round 2 of 4?")
        #expect(Set(alerts.map(\.id)).count == 2)
    }

    @Test func manualBreakSaysStartWhenReady() {
        var manual = settings
        manual.autoStartBreaks = false
        let running = TimerState.initial(settings: manual, now: t0).started(at: t0)
        let alerts = PhaseAlerts.upcoming(state: running, settings: manual, now: t0)
        #expect(alerts.count == 1)
        #expect(alerts[0].body == "Start your 5 min break when you're ready.")
    }

    @Test func lastRoundMentionsLongBreak() {
        let lastRound = TimerState(phase: .work, round: 4, duration: 25 * 60, startedAt: t0, updatedAt: t0)
        let alert = PhaseAlerts.upcoming(state: lastRound, settings: settings, now: t0)[0]
        #expect(alert.title == "Round 4 done, set complete!")
        #expect(alert.body == "Enjoy a 15 min long break.")
    }

    @Test func autoStartWorkSaysRoundStarted() {
        var auto = settings
        auto.autoStartWork = true
        let onBreak = TimerState(phase: .shortBreak, round: 1, duration: 5 * 60, startedAt: t0, updatedAt: t0)
        let alert = PhaseAlerts.upcoming(state: onBreak, settings: auto, now: t0)[0]
        #expect(alert.body == "Round 2 of 4 has started.")
    }

    @Test func endlessChainIsCapped() {
        var auto = settings
        auto.autoStartWork = true
        let running = TimerState.initial(settings: auto, now: t0).started(at: t0)
        #expect(PhaseAlerts.upcoming(state: running, settings: auto, now: t0).count == 4)
    }
}

@Suite("FocusLog")
struct FocusLogTests {
    private func ended(_ phase: Phase, at date: Date, minutes: Double = 25) -> EndedPhase {
        EndedPhase(phase: phase, round: 1, endedAt: date, duration: minutes * 60)
    }

    @Test func onlyWorkCountsAndOnlyOnce() {
        let first = FocusLog.adding([ended(.work, at: at(25)), ended(.shortBreak, at: at(30))], to: [], now: at(30))
        #expect(first.count == 1)
        let again = FocusLog.adding([ended(.work, at: at(25).addingTimeInterval(0.2))], to: first, now: at(31))
        #expect(again.count == 1)
    }

    @Test func todaySummary() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let morning = calendar.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 9))!
        let yesterday = morning.addingTimeInterval(-24 * 3600)
        let log = FocusLog.adding([
            ended(.work, at: yesterday),
            ended(.work, at: morning),
            ended(.work, at: morning.addingTimeInterval(1800), minutes: 50),
        ], to: [], now: morning)
        let summary = FocusLog.summary(of: log, on: morning.addingTimeInterval(3600), calendar: calendar)
        #expect(summary == FocusSummary(rounds: 2, minutes: 75))
        #expect(summary.text == "2 rounds · 75 min")
        #expect(FocusSummary.none.text == "No rounds yet")
        #expect(FocusSummary(rounds: 1, minutes: 25).text == "1 round · 25 min")
    }

    @Test func oldEntriesAreDropped() {
        let old = FocusLog.adding([ended(.work, at: t0)], to: [], now: t0)
        let later = FocusLog.adding([], to: old, now: t0.addingTimeInterval(40 * 24 * 3600))
        #expect(later.isEmpty)
    }
}

@MainActor
@Suite("TimerController focus count")
struct TimerControllerFocusTests {
    @Test func finishedWorkIsCountedOnceEvenWhenCaughtUpLater() {
        let clock = FakeClock()
        let defaults = UserDefaults(suiteName: "SpiderCoreTests-\(UUID().uuidString)")!
        let controller = TimerController(storage: TimerStorage(defaults: defaults), clock: { clock.now })
        controller.start()
        clock.advance(minutes: 26)
        controller.tick()
        #expect(controller.focusLog.count == 1)

        // Another process sees the same round end: still one.
        let relaunched = TimerController(storage: TimerStorage(defaults: defaults), clock: { clock.now })
        #expect(relaunched.focusLog.count == 1)
        #expect(relaunched.focusLog[0].minutes == 25)
    }

    @Test func skippedWorkIsNotCounted() {
        let clock = FakeClock()
        let defaults = UserDefaults(suiteName: "SpiderCoreTests-\(UUID().uuidString)")!
        let controller = TimerController(storage: TimerStorage(defaults: defaults), clock: { clock.now })
        controller.start()
        clock.advance(minutes: 10)
        controller.skip()
        #expect(controller.focusLog.isEmpty)
    }
}
