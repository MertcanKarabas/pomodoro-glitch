import Foundation

/// The whole timer in one small value. Devices share this and each one works out
/// the time left from `startedAt`, so nothing has to tick in sync.
public struct TimerState: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable {
        case idle, running, paused
    }

    public var phase: Phase
    /// Which work round of the set we are in, starting at 1.
    public var round: Int
    public var duration: TimeInterval
    /// Set while running.
    public var startedAt: Date?
    /// Set while paused.
    public var pausedRemaining: TimeInterval?
    /// Time of the last user action (start, pause, skip, reset, settings).
    /// Phases ending by themselves don't change it. Used to pick the newest state when syncing.
    public var updatedAt: Date

    public init(
        phase: Phase,
        round: Int,
        duration: TimeInterval,
        startedAt: Date? = nil,
        pausedRemaining: TimeInterval? = nil,
        updatedAt: Date
    ) {
        self.phase = phase
        self.round = round
        self.duration = duration
        self.startedAt = startedAt
        self.pausedRemaining = pausedRemaining
        self.updatedAt = updatedAt
    }

    public static func initial(settings: PomodoroSettings, now: Date) -> TimerState {
        TimerState(phase: .work, round: 1, duration: settings.duration(of: .work), updatedAt: now)
    }

    public var status: Status {
        if startedAt != nil { return .running }
        if pausedRemaining != nil { return .paused }
        return .idle
    }

    public var endsAt: Date? {
        startedAt?.addingTimeInterval(duration)
    }

    public func remaining(at now: Date) -> TimeInterval {
        if let endsAt {
            return endsAt.timeIntervalSince(now).clamped(to: 0...duration)
        }
        return pausedRemaining ?? duration
    }

    /// 0 at the start of the phase, 1 at the end.
    public func progress(at now: Date) -> Double {
        guard duration > 0 else { return 0 }
        return (1 - remaining(at: now) / duration).clamped(to: 0...1)
    }

    // MARK: - User actions

    public func started(at now: Date) -> TimerState {
        var next = self
        switch status {
        case .running:
            return self
        case .paused:
            let left = pausedRemaining ?? duration
            next.startedAt = now.addingTimeInterval(left - duration)
            next.pausedRemaining = nil
        case .idle:
            next.startedAt = now
        }
        next.updatedAt = now
        return next
    }

    public func paused(at now: Date) -> TimerState {
        guard status == .running else { return self }
        var next = self
        next.pausedRemaining = remaining(at: now)
        next.startedAt = nil
        next.updatedAt = now
        return next
    }

    /// Jump to the next phase now.
    public func skipped(at now: Date, settings: PomodoroSettings) -> TimerState {
        var next = advanced(from: now, settings: settings)
        next.updatedAt = now
        return next
    }

    /// Back to round 1 work, not started.
    public func reset(at now: Date, settings: PomodoroSettings) -> TimerState {
        .initial(settings: settings, now: now)
    }

    /// New durations apply right away only when the timer isn't started.
    public func applying(_ settings: PomodoroSettings, at now: Date) -> TimerState {
        guard status == .idle else { return self }
        var next = self
        next.duration = settings.duration(of: phase)
        next.round = min(round, settings.rounds)
        next.updatedAt = now
        return next
    }

    // MARK: - Phases ending by themselves

    /// Moves past every phase that has ended by `now`.
    /// Every device gets the same answer from the same state, so this never needs syncing.
    public func resolved(at now: Date, settings: PomodoroSettings) -> (state: TimerState, finished: [Phase]) {
        var current = self
        var finished: [Phase] = []
        // The cap only guards against odd settings; normal use loops at most a few times.
        while let end = current.endsAt, end <= now, finished.count < 1_000 {
            finished.append(current.phase)
            current = current.advanced(from: end, settings: settings)
        }
        return (current, finished)
    }

    /// The phase after this one, beginning at `time`. Starts running or waits, per settings.
    func advanced(from time: Date, settings: PomodoroSettings) -> TimerState {
        let nextPhase: Phase
        let nextRound: Int
        switch phase {
        case .work:
            nextPhase = round >= settings.rounds ? .longBreak : .shortBreak
            nextRound = round
        case .shortBreak:
            nextPhase = .work
            nextRound = round + 1
        case .longBreak:
            nextPhase = .work
            nextRound = 1
        }
        let autoStart = nextPhase.isBreak ? settings.autoStartBreaks : settings.autoStartWork
        return TimerState(
            phase: nextPhase,
            round: nextRound,
            duration: settings.duration(of: nextPhase),
            startedAt: autoStart ? time : nil,
            pausedRemaining: nil,
            updatedAt: updatedAt
        )
    }

    /// What comes after the current phase, for "Next: ..." labels.
    public func nextPhase(settings: PomodoroSettings) -> (phase: Phase, round: Int) {
        let next = advanced(from: .distantPast, settings: settings)
        return (next.phase, next.round)
    }

    /// Work rounds finished in the current set.
    public var completedRounds: Int {
        phase == .work ? round - 1 : round
    }
}
