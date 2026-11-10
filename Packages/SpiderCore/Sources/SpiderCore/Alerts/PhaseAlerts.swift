import Foundation

/// A heads-up for when a phase ends, planned ahead so the system can show it even
/// when the app isn't running.
public struct PhaseAlert: Equatable, Sendable {
    public let id: String
    public let date: Date
    public let ended: Phase
    public let title: String
    public let body: String
}

public enum PhaseAlerts {
    public static let idPrefix = "phase-end-"

    /// Alerts for the current phase's end and any phases after it that start by themselves.
    public static func upcoming(
        state: TimerState,
        settings: PomodoroSettings,
        now: Date,
        limit: Int = 4
    ) -> [PhaseAlert] {
        var alerts: [PhaseAlert] = []
        var current = state.resolved(at: now, settings: settings).state
        while alerts.count < limit, current.status == .running, let end = current.endsAt {
            let next = current.resolved(at: end, settings: settings).state
            let (title, body) = text(ended: current, next: next, settings: settings)
            alerts.append(PhaseAlert(
                id: "\(idPrefix)\(Int(end.timeIntervalSinceReferenceDate))",
                date: end,
                ended: current.phase,
                title: title,
                body: body
            ))
            current = next
        }
        return alerts
    }

    static func text(ended: TimerState, next: TimerState, settings: PomodoroSettings) -> (String, String) {
        let minutes = settings.minutes(of: next.phase)
        let started = next.status == .running

        switch (ended.phase, next.phase) {
        case (.work, .longBreak):
            return ("Round \(ended.round) done, set complete!",
                    started ? "Enjoy a \(minutes) min long break." : "Start your \(minutes) min long break when you're ready.")
        case (.work, _):
            return ("Work done!",
                    started ? "Time for a \(minutes) min break." : "Start your \(minutes) min break when you're ready.")
        default:
            return ("Break over",
                    started
                        ? "Round \(next.round) of \(settings.rounds) has started."
                        : "Ready for round \(next.round) of \(settings.rounds)?")
        }
    }
}
