import Foundation

/// What the timer has the hero doing, for the Mac poses that act it out (a laptop while he
/// works, his phone on a break).
public enum HeroTask: Equatable, Sendable {
    /// Work is running.
    case working
    /// A break is running.
    case onBreak
    /// The timer is paused.
    case paused
    /// Nothing started yet.
    case asleep
    /// A phase just ended, or a break is waiting to start.
    case cheering

    public init(state: TimerState, now: Date, lastFinished: FinishedPhase?) {
        let celebrating = lastFinished.map {
            now >= $0.at && now.timeIntervalSince($0.at) < HeroPlacement.celebrateSeconds
        } ?? false
        if celebrating {
            self = .cheering
            return
        }
        switch state.status {
        case .running: self = state.phase.isBreak ? .onBreak : .working
        case .paused: self = .paused
        case .idle: self = state.phase.isBreak ? .cheering : .asleep
        }
    }

    /// On his web during a break he takes turns: climbs a while, then hangs on with one hand
    /// and scrolls his phone a while (the web still shortens as the break goes on).
    public static let breakClimbSeconds: Double = 12
    public static let breakScrollSeconds: Double = 24

    /// The pose on his web, given the timer's pose, at a time in seconds (any steady clock).
    public func webPose(timerPose: HeroPose, at time: Double) -> HeroPose {
        guard self == .onBreak, timerPose == .climbing else { return timerPose }
        let cycle = Self.breakClimbSeconds + Self.breakScrollSeconds
        let into = time.truncatingRemainder(dividingBy: cycle)
        return into < Self.breakClimbSeconds ? .climbing : .hangingScrolling
    }
}
