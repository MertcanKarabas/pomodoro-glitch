import Foundation

public enum TimeFormat {
    /// "25:00", "4:07", "1:05:00". Rounds up, so a fresh 25 min timer shows 25:00
    /// and the last half second still shows 0:01.
    public static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// "24m": minutes left (rounded up), for the menu bar. Changes once a minute, which keeps
    /// macOS from redrawing the menu bar every second.
    public static func shortMinutes(_ seconds: TimeInterval) -> String {
        "\(minutesLeft(seconds))m"
    }

    /// Whole minutes left, rounded up: 1500 s → 25, 61 s → 2, 59 s → 1, 0 → 0.
    /// Half a second of slack so timeline steps landing a hair late don't show one too many.
    public static func minutesLeft(_ seconds: TimeInterval) -> Int {
        guard seconds > 0 else { return 0 }
        return max(1, Int(((seconds - 0.5) / 60).rounded(.up)))
    }
}
