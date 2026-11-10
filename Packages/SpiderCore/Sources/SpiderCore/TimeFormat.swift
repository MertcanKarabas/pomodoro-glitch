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
}
