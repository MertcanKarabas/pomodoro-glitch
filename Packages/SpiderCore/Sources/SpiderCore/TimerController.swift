import Foundation
import Observation

/// A phase that ended while the app was watching, and when that was noticed.
public struct FinishedPhase: Equatable, Sendable {
    public let phase: Phase
    public let at: Date

    public init(phase: Phase, at: Date) {
        self.phase = phase
        self.at = at
    }
}

/// Runs the timer for an app: keeps `now` fresh, moves to the next phase when one ends,
/// saves every change and calls `onPhaseFinished` so the app can play a sound.
@MainActor
@Observable
public final class TimerController {
    public private(set) var state: TimerState
    public private(set) var settings: PomodoroSettings
    public private(set) var now: Date
    /// Last phase that ended while running (not while the app was closed). Drives the hero's wave.
    public private(set) var lastFinished: FinishedPhase?
    /// When a person last changed the timer or its settings, here or on another device.
    public private(set) var changedAt: Date
    /// Finished work rounds seen on this device (last few weeks).
    public private(set) var focusLog: [FocusEntry]

    /// Rounds and focus minutes finished today.
    public var today: FocusSummary { FocusLog.summary(of: focusLog, on: Date()) }

    /// Called after a person changes the timer on this device (not for syncing or phases
    /// ending by themselves), so it can be sent to the other devices.
    @ObservationIgnored public var onUserChange: (@MainActor () -> Void)?

    @ObservationIgnored private let storage: TimerStorage
    @ObservationIgnored private let clock: @MainActor () -> Date
    @ObservationIgnored private let onPhaseFinished: @MainActor (Phase) -> Void
    @ObservationIgnored private let onSave: @MainActor () -> Void
    @ObservationIgnored private var tickTask: Task<Void, Never>?

    /// - Parameter onSave: called after every saved change, so the app can refresh widgets
    ///   and tell other processes.
    public init(
        storage: TimerStorage = TimerStorage(),
        clock: @escaping @MainActor () -> Date = { Date() },
        onPhaseFinished: @escaping @MainActor (Phase) -> Void = { _ in },
        onSave: @escaping @MainActor () -> Void = {}
    ) {
        let now = clock()
        let settings = storage.loadSettings() ?? .standard
        self.storage = storage
        self.clock = clock
        self.onPhaseFinished = onPhaseFinished
        self.onSave = onSave
        self.settings = settings
        self.state = storage.loadState() ?? .initial(settings: settings, now: now)
        self.changedAt = storage.loadChangedAt()
        self.focusLog = storage.loadFocusLog()
        self.now = now
        // Catch up on phases that ended while the app was closed, without a sound.
        resolve(alert: false)
    }

    // MARK: - Read

    public var remaining: TimeInterval { state.remaining(at: now) }
    public var progress: Double { state.progress(at: now) }
    public var clockText: String { TimeFormat.clock(remaining) }

    // MARK: - Actions

    public func toggle() { perform(.toggle) }
    public func start() { perform(.start) }
    public func pause() { perform(.pause) }
    public func skip() { perform(.skip) }
    public func reset() { perform(.reset) }

    public func perform(_ action: TimerAction) {
        let settings = settings
        if change({ state, time in state.performing(action, at: time, settings: settings) }) {
            markUserChange()
        }
    }

    public func update(settings newSettings: PomodoroSettings) {
        guard newSettings != settings else { return }
        settings = newSettings
        storage.save(newSettings)
        change { state, time in state.applying(newSettings, at: time) }
        onSave()
        markUserChange()
    }

    /// Picks up changes another process saved (a widget button, for example).
    public func reload() {
        let savedSettings = storage.loadSettings() ?? settings
        let savedState = storage.loadState() ?? state
        let savedChangedAt = storage.loadChangedAt()
        if savedSettings != settings { settings = savedSettings }
        if savedState != state { state = savedState }
        if savedChangedAt != changedAt { changedAt = savedChangedAt }
        let savedLog = storage.loadFocusLog()
        if savedLog != focusLog { focusLog = savedLog }
        now = clock()
        resolve(alert: false)
    }

    // MARK: - Sync

    /// This device's timer as sent to the other devices.
    public var snapshot: SyncSnapshot {
        SyncSnapshot(state: state, settings: settings, changedAt: changedAt, changedBy: storage.loadChangedBy())
    }

    /// Takes a newer timer from another device.
    public func apply(_ remote: SyncSnapshot) {
        if remote.settings != settings {
            settings = remote.settings
            storage.save(remote.settings)
        }
        changedAt = remote.changedAt
        storage.saveChange(at: remote.changedAt, by: remote.changedBy)
        now = clock()
        if remote.state != state {
            save(remote.state)
        } else {
            onSave()
        }
        // Phases that ended on the way here end quietly; the other device already rang.
        resolve(alert: false)
    }

    private func markUserChange() {
        changedAt = now
        storage.saveChange(at: now, by: storage.deviceID)
        onUserChange?()
    }

    // MARK: - Ticking

    public func tick() {
        // Nothing moves while idle or paused, so don't wake anyone watching `now`.
        guard state.status == .running else { return }
        now = clock()
        resolve(alert: true)
    }

    public func startTicking() {
        guard tickTask == nil else { return }
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let delay = self?.nextTickDelay() else { return }
                try? await Task.sleep(for: .seconds(delay))
                self?.tick()
            }
        }
    }

    public func stopTicking() {
        tickTask?.cancel()
        tickTask = nil
    }

    /// Wake right when the shown second changes, so the countdown never stutters.
    func nextTickDelay() -> TimeInterval {
        guard state.status == .running else { return 1 }
        let fraction = remaining - remaining.rounded(.down)
        return max(0.05, fraction + 0.01)
    }

    // MARK: - Private

    /// Returns whether the timer changed.
    @discardableResult
    private func change(_ transform: (TimerState, Date) -> TimerState) -> Bool {
        let time = clock()
        now = time
        resolve(alert: true)
        let next = transform(state, time)
        guard next != state else { return false }
        save(next)
        return true
    }

    private func resolve(alert: Bool) {
        let (next, finished) = state.resolved(at: now, settings: settings)
        guard next != state else { return }
        // Count finished rounds even when catching up quietly.
        let log = storage.recordFinished(finished, now: now)
        if log != focusLog { focusLog = log }
        save(next)
        if alert, let last = finished.last {
            lastFinished = FinishedPhase(phase: last.phase, at: now)
            onPhaseFinished(last.phase)
        }
    }

    private func save(_ next: TimerState) {
        state = next
        storage.save(next)
        onSave()
    }
}
