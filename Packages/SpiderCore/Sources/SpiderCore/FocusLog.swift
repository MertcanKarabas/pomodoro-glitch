import Foundation

/// A finished work round, for "today" counts.
public struct FocusEntry: Codable, Equatable, Sendable {
    public let endedAt: Date
    public let minutes: Int
}

/// How much was done on one day.
public struct FocusSummary: Equatable, Sendable {
    public let rounds: Int
    public let minutes: Int

    public static let none = FocusSummary(rounds: 0, minutes: 0)

    /// "3 rounds · 75 min" (or "No rounds yet").
    public var text: String {
        rounds == 0 ? "No rounds yet" : "\(rounds) round\(rounds == 1 ? "" : "s") · \(minutes) min"
    }
}

/// Work rounds that ran to the end. Each device fills it in as it watches the timer;
/// the same round seen twice (by the app and a widget, say) only counts once.
public enum FocusLog {
    /// Older entries are dropped.
    static let keepDays = 35

    public static func adding(_ ended: [EndedPhase], to entries: [FocusEntry], now: Date) -> [FocusEntry] {
        var result = entries
        for phase in ended where phase.phase == .work {
            let isNew = !result.contains { abs($0.endedAt.timeIntervalSince(phase.endedAt)) < 1 }
            if isNew {
                result.append(FocusEntry(endedAt: phase.endedAt, minutes: Int((phase.duration / 60).rounded())))
            }
        }
        let cutoff = now.addingTimeInterval(-Double(keepDays) * 24 * 3600)
        return result.filter { $0.endedAt >= cutoff }.sorted { $0.endedAt < $1.endedAt }
    }

    public static func summary(of entries: [FocusEntry], on day: Date, calendar: Calendar = .current) -> FocusSummary {
        let today = entries.filter { calendar.isDate($0.endedAt, inSameDayAs: day) }
        return FocusSummary(rounds: today.count, minutes: today.reduce(0) { $0 + $1.minutes })
    }
}
