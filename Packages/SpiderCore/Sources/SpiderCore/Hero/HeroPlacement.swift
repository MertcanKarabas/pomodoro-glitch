import Foundation

/// Where the hero is on his web and what he's doing, worked out from the timer.
///
/// - Work: drops from the top (0) to the bottom (1) as time passes.
/// - Break: climbs from the bottom back to the top.
/// - Just after a phase ends: waves for a few seconds.
/// - Not started: sleeps at the top. A break waiting to start: waves at the bottom.
public struct HeroPlacement: Equatable, Sendable {
    public static let celebrateSeconds: TimeInterval = 5

    public var pose: HeroPose
    /// 0 = up at the top, 1 = all the way down.
    public var drop: Double
    /// Gentle pendulum swing while something is happening.
    public var swings: Bool

    public init(pose: HeroPose, drop: Double, swings: Bool) {
        self.pose = pose
        self.drop = drop
        self.swings = swings
    }

    public init(state: TimerState, now: Date, lastFinished: FinishedPhase?) {
        let celebrating = lastFinished.map {
            now >= $0.at && now.timeIntervalSince($0.at) < Self.celebrateSeconds
        } ?? false
        let progress = state.progress(at: now)
        let running = state.status == .running

        if state.phase.isBreak {
            drop = state.status == .idle ? 1 : 1 - progress
            if celebrating || state.status == .idle {
                pose = .waving
            } else {
                pose = running ? .climbing : .hanging
            }
        } else {
            drop = state.status == .idle ? 0 : progress
            if celebrating {
                pose = .waving
            } else {
                pose = state.status == .idle ? .sleeping : .hanging
            }
        }
        swings = running || celebrating
    }
}
