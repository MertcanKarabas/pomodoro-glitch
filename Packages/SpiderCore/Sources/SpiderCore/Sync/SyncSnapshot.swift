import Foundation

/// Everything one device tells the others: the timer, its settings, and who changed it when.
public struct SyncSnapshot: Codable, Equatable, Sendable {
    public var state: TimerState
    public var settings: PomodoroSettings
    /// When a person last pressed a button or changed a setting, on any device.
    public var changedAt: Date
    /// Random ID of the device where that happened.
    public var changedBy: String

    public init(state: TimerState, settings: PomodoroSettings, changedAt: Date, changedBy: String) {
        self.state = state
        self.settings = settings
        self.changedAt = changedAt
        self.changedBy = changedBy
    }

    public enum Decision: Equatable, Sendable {
        /// Both sides already agree.
        case keepLocal
        /// The other side is newer: use it here.
        case takeRemote
        /// This device is newer (or the other side has nothing): send ours.
        case pushLocal
    }

    /// The newest change wins. On an exact tie between two devices the server copy wins,
    /// so every device ends up with the same timer.
    public static func decide(local: SyncSnapshot, remote: SyncSnapshot?) -> Decision {
        guard let remote else { return .pushLocal }
        if remote.changedAt > local.changedAt { return .takeRemote }
        if remote.changedAt < local.changedAt { return .pushLocal }
        return remote.changedBy == local.changedBy ? .keepLocal : .takeRemote
    }
}

extension TimerAction {
    /// `spiderpomodoro://start`, `://pause`, `://toggle`, `://skip`, `://reset`.
    public init?(url: URL) {
        guard url.scheme?.lowercased() == "spiderpomodoro", let host = url.host?.lowercased() else { return nil }
        self.init(rawValue: host)
    }
}
