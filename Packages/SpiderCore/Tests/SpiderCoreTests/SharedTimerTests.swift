import Foundation
import Testing
@testable import SpiderCore

private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
private func at(_ minutes: Double) -> Date { t0.addingTimeInterval(minutes * 60) }

@Suite("TimerAction")
struct TimerActionTests {
    let settings = PomodoroSettings.standard

    @Test func toggleStartsThenPauses() {
        let idle = TimerState.initial(settings: settings, now: t0)
        let running = idle.performing(.toggle, at: t0, settings: settings)
        #expect(running.status == .running)
        #expect(running.performing(.toggle, at: at(1), settings: settings).status == .paused)
    }

    @Test func skipAndResetMatchDirectCalls() {
        let running = TimerState.initial(settings: settings, now: t0).started(at: t0)
        #expect(running.performing(.skip, at: at(2), settings: settings) == running.skipped(at: at(2), settings: settings))
        #expect(running.performing(.reset, at: at(2), settings: settings) == .initial(settings: settings, now: at(2)))
    }
}

@Suite("TimerTimeline")
struct TimerTimelineTests {
    let settings = PomodoroSettings.standard

    @Test func idleIsOneMoment() {
        let idle = TimerState.initial(settings: settings, now: t0)
        let moments = TimerTimeline.moments(from: idle, settings: settings, now: t0)
        #expect(moments.count == 1)
        #expect(moments[0].heroPlacement.pose == .sleeping)
    }

    @Test func runningWorkPlansEveryMinuteThroughTheBreak() {
        // Started 0 min ago: 25 min work, then 5 min break, then work waits.
        let running = TimerState.initial(settings: settings, now: t0).started(at: t0)
        let moments = TimerTimeline.moments(from: running, settings: settings, now: t0)

        // now + 24 minute marks + work end + 4 minute marks + break end
        #expect(moments.count == 1 + 24 + 1 + 4 + 1)
        #expect(moments.map(\.date) == moments.map(\.date).sorted())

        let workEnd = moments[25]
        #expect(workEnd.date == at(25))
        #expect(workEnd.state.phase == .shortBreak)
        #expect(workEnd.heroPlacement.pose == .waving)

        #expect(moments[26].heroPlacement.pose == .climbing)

        let last = moments.last!
        #expect(last.date == at(30))
        #expect(last.state.phase == .work)
        #expect(last.state.status == .idle)
        #expect(last.state.round == 2)
    }

    @Test func savedStateIsCaughtUpFirst() {
        let running = TimerState.initial(settings: settings, now: t0).started(at: t0)
        let moments = TimerTimeline.moments(from: running, settings: settings, now: at(27))
        #expect(moments[0].state.phase == .shortBreak)
        #expect(moments.last!.state.status == .idle)
    }

    @Test func heroDropsMinuteByMinute() {
        let running = TimerState.initial(settings: settings, now: t0).started(at: t0)
        let moments = TimerTimeline.moments(from: running, settings: settings, now: t0)
        let drops = moments.prefix(25).map(\.heroPlacement.drop)
        #expect(drops == drops.sorted())
        #expect(abs(drops[10] - 10.0 / 25) < 0.0001)
    }

    @Test func followingPhaseEnd() {
        let idle = TimerState.initial(settings: settings, now: t0)
        #expect(idle.followingPhaseEnd(settings: settings) == nil)

        // Work 0...25 min, break starts by itself and ends at 30.
        let working = idle.started(at: t0)
        #expect(working.followingPhaseEnd(settings: settings) == at(30))

        // Break ending leads to work that waits for you: nothing to count down to.
        let onBreak = TimerState(phase: .shortBreak, round: 1, duration: 5 * 60, startedAt: t0, updatedAt: t0)
        #expect(onBreak.followingPhaseEnd(settings: settings) == nil)

        var manual = settings
        manual.autoStartBreaks = false
        #expect(working.followingPhaseEnd(settings: manual) == nil)
    }

    @Test func endlessAutoStartStopsAtLimit() {
        var auto = settings
        auto.autoStartWork = true
        let running = TimerState.initial(settings: auto, now: t0).started(at: t0)
        let moments = TimerTimeline.moments(from: running, settings: auto, now: t0, horizon: 100 * 3600, limit: 50)
        #expect(moments.count == 50)
    }
}

@MainActor
@Suite("TimerController sharing")
struct TimerControllerSharingTests {
    @Test func reloadPicksUpChangesFromAnotherProcess() {
        let clock = FakeClock()
        let defaults = UserDefaults(suiteName: "SpiderCoreTests-\(UUID().uuidString)")!
        let app = TimerController(storage: TimerStorage(defaults: defaults), clock: { clock.now })

        // A widget presses start through its own storage object.
        let widgetStorage = TimerStorage(defaults: defaults)
        let settings = widgetStorage.loadSettings() ?? .standard
        let saved = widgetStorage.loadState() ?? .initial(settings: settings, now: clock.now)
        widgetStorage.save(saved.performing(.start, at: clock.now, settings: settings))

        #expect(app.state.status == .idle)
        app.reload()
        #expect(app.state.status == .running)
    }

    @Test func onSaveRunsForEveryChange() {
        let clock = FakeClock()
        let defaults = UserDefaults(suiteName: "SpiderCoreTests-\(UUID().uuidString)")!
        var saves = 0
        let app = TimerController(storage: TimerStorage(defaults: defaults), clock: { clock.now }, onSave: { saves += 1 })
        app.start()
        app.pause()
        #expect(saves == 2)
        app.pause()
        #expect(saves == 2)
    }
}
