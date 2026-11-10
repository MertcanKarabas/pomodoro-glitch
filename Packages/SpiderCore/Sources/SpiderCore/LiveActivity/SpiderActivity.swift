#if os(iOS)
import ActivityKit
import Foundation

/// The Live Activity (Dynamic Island and Lock Screen) for the running timer.
public struct SpiderActivityAttributes: ActivityAttributes {
    public init() {}

    /// What the Live Activity shows. It can't change by itself, so besides the current
    /// phase it also carries the next one: when the current phase ends (the content goes
    /// stale), the views switch to the next phase's countdown without waiting for the app.
    public struct ContentState: Codable, Hashable, Sendable {
        public var phase: Phase
        public var status: TimerState.Status
        public var round: Int
        public var rounds: Int
        public var duration: TimeInterval
        public var startedAt: Date?
        public var endsAt: Date?
        /// Time left when this was made (what to show while paused or not started).
        public var remaining: TimeInterval
        /// 0...1 when this was made; places the hero.
        public var progress: Double

        public var nextPhase: Phase
        public var nextRound: Int
        /// Set when the next phase starts by itself: when it will end.
        public var nextEndsAt: Date?
        /// "5 min break", "work, round 2 of 4"...
        public var nextDescription: String

        public init(state: TimerState, settings: PomodoroSettings, now: Date) {
            phase = state.phase
            status = state.status
            round = state.round
            rounds = settings.rounds
            duration = state.duration
            startedAt = state.startedAt
            endsAt = state.endsAt
            remaining = state.remaining(at: now)
            progress = state.progress(at: now)

            let next = state.nextPhase(settings: settings)
            nextPhase = next.phase
            nextRound = next.round
            nextEndsAt = state.followingPhaseEnd(settings: settings)
            nextDescription = state.nextDescription(settings: settings)
        }

        /// Where the hero hangs and what he does.
        /// `phaseOver` is true once the current phase has ended (the content went stale).
        public func heroPlacement(phaseOver: Bool) -> HeroPlacement {
            if phaseOver {
                return HeroPlacement(pose: .waving, drop: phase.isBreak ? 0 : 1, swings: false)
            }
            let drop = phase.isBreak ? 1 - progress : progress
            switch status {
            case .running: return HeroPlacement(pose: phase.isBreak ? .climbing : .hanging, drop: drop, swings: true)
            case .paused: return HeroPlacement(pose: .hanging, drop: drop, swings: false)
            case .idle: return HeroPlacement(pose: phase.isBreak ? .waving : .sleeping, drop: phase.isBreak ? 1 : 0, swings: false)
            }
        }
    }
}
#endif
