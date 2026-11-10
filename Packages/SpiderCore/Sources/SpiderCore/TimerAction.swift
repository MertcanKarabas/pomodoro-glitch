import Foundation

/// A button press: from the app, a widget, or (later) another device.
public enum TimerAction: String, Codable, Sendable {
    /// Start or resume if stopped, pause if running.
    case toggle
    case start
    case pause
    case skip
    case reset
}

extension TimerState {
    public func performing(_ action: TimerAction, at now: Date, settings: PomodoroSettings) -> TimerState {
        switch action {
        case .toggle: status == .running ? paused(at: now) : started(at: now)
        case .start: started(at: now)
        case .pause: paused(at: now)
        case .skip: skipped(at: now, settings: settings)
        case .reset: reset(at: now, settings: settings)
        }
    }
}
