import Foundation
import Testing
@testable import SpiderCore

@MainActor
final class FakeClock {
    var now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    func advance(minutes: Double) { now = now.addingTimeInterval(minutes * 60) }
}

@MainActor
@Suite("TimerController")
struct TimerControllerTests {
    let clock = FakeClock()
    let defaults = UserDefaults(suiteName: "SpiderCoreTests-\(UUID().uuidString)")!

    private func makeController(onFinish: @escaping @MainActor (Phase) -> Void = { _ in }) -> TimerController {
        let clock = clock
        return TimerController(storage: TimerStorage(defaults: defaults), clock: { clock.now }, onPhaseFinished: onFinish)
    }

    @Test func toggleStartsAndPauses() {
        let controller = makeController()
        controller.toggle()
        #expect(controller.state.status == .running)
        clock.advance(minutes: 1)
        controller.toggle()
        #expect(controller.state.status == .paused)
        #expect(controller.clockText == "24:00")
    }

    @Test func tickMovesToBreakAndAlertsOnce() {
        var finished: [Phase] = []
        let controller = makeController { finished.append($0) }
        controller.start()
        clock.advance(minutes: 25.5)
        controller.tick()
        controller.tick()
        #expect(controller.state.phase == .shortBreak)
        #expect(controller.clockText == "4:30")
        #expect(finished == [.work])
    }

    @Test func stateIsRestoredAfterRelaunchWithoutSound() {
        var finished: [Phase] = []
        makeController().start()
        clock.advance(minutes: 26)
        let relaunched = makeController { finished.append($0) }
        #expect(relaunched.state.phase == .shortBreak)
        #expect(finished.isEmpty)
    }

    @Test func settingsAreSavedAndApplied() {
        let controller = makeController()
        var settings = controller.settings
        settings.workMinutes = 45
        controller.update(settings: settings)
        #expect(controller.clockText == "45:00")
        #expect(makeController().settings.workMinutes == 45)
    }

    @Test func tickDelayLandsOnNextSecond() {
        let controller = makeController()
        #expect(controller.nextTickDelay() == 1)
        controller.start()
        clock.now = clock.now.addingTimeInterval(0.3)
        controller.tick()
        // 1499.7 s left: next whole second in 0.7 s.
        #expect(abs(controller.nextTickDelay() - 0.71) < 0.001)
    }
}
