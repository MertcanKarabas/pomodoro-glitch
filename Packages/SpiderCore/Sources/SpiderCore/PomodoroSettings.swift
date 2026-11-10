import Foundation

public struct PomodoroSettings: Codable, Equatable, Sendable {
    public static let minuteRange = 1...120
    public static let roundsRange = 1...12
    public static let standard = PomodoroSettings()

    public var workMinutes: Int
    public var shortBreakMinutes: Int
    public var longBreakMinutes: Int
    public var roundsBeforeLongBreak: Int
    /// Start the break by itself when work ends.
    public var autoStartBreaks: Bool
    /// Start the next work round by itself when a break ends.
    public var autoStartWork: Bool

    public init(
        workMinutes: Int = 25,
        shortBreakMinutes: Int = 5,
        longBreakMinutes: Int = 15,
        roundsBeforeLongBreak: Int = 4,
        autoStartBreaks: Bool = true,
        autoStartWork: Bool = false
    ) {
        self.workMinutes = workMinutes
        self.shortBreakMinutes = shortBreakMinutes
        self.longBreakMinutes = longBreakMinutes
        self.roundsBeforeLongBreak = roundsBeforeLongBreak
        self.autoStartBreaks = autoStartBreaks
        self.autoStartWork = autoStartWork
    }

    public func minutes(of phase: Phase) -> Int {
        let raw = switch phase {
        case .work: workMinutes
        case .shortBreak: shortBreakMinutes
        case .longBreak: longBreakMinutes
        }
        return raw.clamped(to: Self.minuteRange)
    }

    public func duration(of phase: Phase) -> TimeInterval {
        TimeInterval(minutes(of: phase) * 60)
    }

    public var rounds: Int { roundsBeforeLongBreak.clamped(to: Self.roundsRange) }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
