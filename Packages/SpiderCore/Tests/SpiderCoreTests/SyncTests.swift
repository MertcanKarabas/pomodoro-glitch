import Foundation
import Testing
@testable import SpiderCore

private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

private func snapshot(_ changedAt: Date, by device: String = "A", running: Bool = false) -> SyncSnapshot {
    var state = TimerState.initial(settings: .standard, now: t0)
    if running { state = state.started(at: t0) }
    return SyncSnapshot(state: state, settings: .standard, changedAt: changedAt, changedBy: device)
}

@Suite("SyncSnapshot.decide")
struct SyncDecisionTests {
    @Test func nothingOnServerMeansPush() {
        #expect(SyncSnapshot.decide(local: snapshot(t0), remote: nil) == .pushLocal)
    }

    @Test func newerSideWins() {
        let older = snapshot(t0)
        let newer = snapshot(t0.addingTimeInterval(5), by: "B")
        #expect(SyncSnapshot.decide(local: older, remote: newer) == .takeRemote)
        #expect(SyncSnapshot.decide(local: newer, remote: older) == .pushLocal)
    }

    @Test func sameChangeFromSameDeviceIsKept() {
        // Local copy may have moved on to the break by itself; still the same change.
        var local = snapshot(t0, running: true)
        local.state = local.state.resolved(at: t0.addingTimeInterval(1600), settings: .standard).state
        #expect(SyncSnapshot.decide(local: local, remote: snapshot(t0, running: true)) == .keepLocal)
    }

    @Test func exactTieBetweenDevicesGoesToServer() {
        #expect(SyncSnapshot.decide(local: snapshot(t0, by: "A"), remote: snapshot(t0, by: "B")) == .takeRemote)
    }

    @Test func snapshotSurvivesJSON() throws {
        let original = snapshot(t0, running: true)
        let data = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode(SyncSnapshot.self, from: data) == original)
    }
}

@Suite("TimerAction links")
struct TimerActionURLTests {
    @Test(arguments: [
        ("spiderpomodoro://start", TimerAction.start),
        ("spiderpomodoro://PAUSE", .pause),
        ("spiderpomodoro://toggle", .toggle),
        ("spiderpomodoro://skip", .skip),
        ("spiderpomodoro://reset", .reset),
    ])
    func knownLinks(link: String, action: TimerAction) {
        #expect(TimerAction(url: URL(string: link)!) == action)
    }

    @Test func otherLinksAreIgnored() {
        #expect(TimerAction(url: URL(string: "spiderpomodoro://dance")!) == nil)
        #expect(TimerAction(url: URL(string: "https://start")!) == nil)
    }
}

@MainActor
@Suite("TimerController sync")
struct TimerControllerSyncTests {
    let clock = FakeClock()
    let defaults = UserDefaults(suiteName: "SpiderCoreTests-\(UUID().uuidString)")!

    private func makeController() -> TimerController {
        let clock = clock
        return TimerController(storage: TimerStorage(defaults: defaults), clock: { clock.now })
    }

    @Test func buttonPressesAreStampedAndReported() {
        let controller = makeController()
        var reports = 0
        controller.onUserChange = { reports += 1 }
        #expect(controller.changedAt == .distantPast)

        controller.start()
        #expect(controller.changedAt == clock.now)
        #expect(reports == 1)

        clock.advance(minutes: 1)
        controller.start()
        #expect(reports == 1, "starting again changes nothing, so nothing to send")
    }

    @Test func phasesEndingByThemselvesAreNotReported() {
        let controller = makeController()
        var reports = 0
        controller.start()
        controller.onUserChange = { reports += 1 }
        let started = controller.changedAt
        clock.advance(minutes: 26)
        controller.tick()
        #expect(controller.state.phase == .shortBreak)
        #expect(controller.changedAt == started)
        #expect(reports == 0)
    }

    @Test func applyTakesRemoteStateAndSettingsQuietly() {
        let controller = makeController()
        var reports = 0
        controller.onUserChange = { reports += 1 }

        var settings = PomodoroSettings.standard
        settings.workMinutes = 50
        let remoteState = TimerState.initial(settings: settings, now: clock.now).started(at: clock.now)
        let remote = SyncSnapshot(state: remoteState, settings: settings, changedAt: clock.now, changedBy: "other")

        controller.apply(remote)
        #expect(controller.state == remoteState)
        #expect(controller.settings.workMinutes == 50)
        #expect(controller.changedAt == clock.now)
        #expect(reports == 0)
        // The next check sees the same change and leaves it alone.
        #expect(controller.snapshot.changedBy == "other")
        #expect(SyncSnapshot.decide(local: controller.snapshot, remote: remote) == .keepLocal)

        // Survives a relaunch.
        let relaunched = makeController()
        #expect(relaunched.state == remoteState)
        #expect(relaunched.changedAt == clock.now)
    }

    @Test func widgetPressIsStampedForSync() {
        let storage = TimerStorage(defaults: defaults)
        let result = SharedTimer.perform(.toggle, at: t0, storage: storage)
        #expect(result.state.status == .running)
        #expect(result.changedAt == t0)
        #expect(result.changedBy == storage.deviceID)
        #expect(storage.loadChangedAt() == t0)

        let controller = makeController()
        #expect(controller.snapshot.changedBy == result.changedBy)
    }
}
