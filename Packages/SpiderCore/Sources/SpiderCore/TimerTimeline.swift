import Foundation

/// What a widget should show from a given moment on.
public struct TimerMoment: Equatable, Sendable {
    public let date: Date
    public let state: TimerState
    public let lastFinished: FinishedPhase?

    public init(date: Date, state: TimerState, lastFinished: FinishedPhase?) {
        self.date = date
        self.state = state
        self.lastFinished = lastFinished
    }

    public var heroPlacement: HeroPlacement {
        HeroPlacement(state: state, now: date, lastFinished: lastFinished)
    }
}

extension TimerState {
    /// If the timer is running and the next phase starts by itself, when that next phase ends.
    public func followingPhaseEnd(settings: PomodoroSettings) -> Date? {
        guard let end = endsAt else { return nil }
        let after = resolved(at: end, settings: settings).state
        return after.status == .running ? after.endsAt : nil
    }
}

/// Plans widget pictures ahead of time. Countdown text ticks by itself in widgets,
/// but the hero's position and pose only change when a new moment starts, so we add
/// one every minute while running, plus one exactly when each phase ends.
public enum TimerTimeline {
    public static func moments(
        from saved: TimerState,
        settings: PomodoroSettings,
        now: Date,
        step: TimeInterval = 60,
        horizon: TimeInterval = 3 * 3600,
        limit: Int = 240
    ) -> [TimerMoment] {
        var current = saved.resolved(at: now, settings: settings).state
        var lastFinished: FinishedPhase?
        var moments = [TimerMoment(date: now, state: current, lastFinished: nil)]
        var cursor = now

        while current.status == .running, let end = current.endsAt,
              end <= now.addingTimeInterval(horizon), moments.count < limit {
            // Line the steps up with whole minutes left (end − n·step), so a
            // "minutes left" label is right for the whole step.
            var time = end.addingTimeInterval(-step * (end.timeIntervalSince(cursor) / step).rounded(.down))
            if time <= cursor { time = time.addingTimeInterval(step) }
            while time < end, moments.count < limit {
                moments.append(TimerMoment(date: time, state: current, lastFinished: lastFinished))
                time = time.addingTimeInterval(step)
            }
            guard moments.count < limit else { break }
            let finished = FinishedPhase(phase: current.phase, at: end)
            current = current.resolved(at: end, settings: settings).state
            lastFinished = finished
            moments.append(TimerMoment(date: end, state: current, lastFinished: finished))
            cursor = end
        }
        return moments
    }
}
