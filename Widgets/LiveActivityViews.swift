#if os(iOS)
import ActivityKit
import SpiderCore
import SwiftUI
import WidgetKit

/// The timer in the Dynamic Island and on the Lock Screen while it runs.
struct SpiderLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SpiderActivityAttributes.self) { context in
            LockScreenActivityView(state: context.state, phaseOver: context.isStale)
                .activityBackgroundTint(Color(red: 0.07, green: 0.09, blue: 0.20))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let shown = ActivityDisplay(state: context.state, phaseOver: context.isStale)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    IslandHero(display: shown)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ActivityCountdown(display: shown)
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .foregroundStyle(shown.phase.color)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Label(shown.title, systemImage: shown.phase.symbolName)
                            .font(.headline)
                            .foregroundStyle(shown.phase.color)
                        Text(shown.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 10) {
                        ActivityProgress(display: shown)
                        ActivityButtons(display: shown)
                    }
                }
            } compactLeading: {
                HeroHead(pose: shown.placement.pose, size: 22)
            } compactTrailing: {
                ActivityCountdown(display: shown)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(shown.phase.color)
                    .frame(maxWidth: 46)
            } minimal: {
                HeroHead(pose: shown.placement.pose, size: 20)
            }
            .keylineTint(shown.phase.color)
        }
    }
}

/// What to show right now: the current phase, or the next one once the current phase is
/// over and the app hasn't had a chance to update yet.
struct ActivityDisplay {
    let phase: Phase
    let isRunning: Bool
    let isPaused: Bool
    let start: Date?
    let end: Date?
    let remaining: TimeInterval
    let progress: Double
    let title: String
    let subtitle: String
    let placement: HeroPlacement

    init(state: SpiderActivityAttributes.ContentState, phaseOver: Bool) {
        if phaseOver, let nextEnd = state.nextEndsAt, let currentEnd = state.endsAt {
            // The next phase started by itself when this one ended.
            phase = state.nextPhase
            isRunning = true
            isPaused = false
            start = currentEnd
            end = nextEnd
            remaining = 0
            progress = 0
            title = state.nextPhase.title
            subtitle = "\(state.phase.title) done"
            placement = HeroPlacement(pose: state.nextPhase.isBreak ? .climbing : .hanging,
                                      drop: state.nextPhase.isBreak ? 1 : 0, swings: true)
        } else if phaseOver {
            phase = state.nextPhase
            isRunning = false
            isPaused = false
            start = nil
            end = nil
            remaining = 0
            progress = 1
            title = "\(state.phase.title) done"
            subtitle = "Next: \(state.nextDescription)"
            placement = state.heroPlacement(phaseOver: true)
        } else {
            phase = state.phase
            isRunning = state.status == .running
            isPaused = state.status == .paused
            start = state.startedAt
            end = state.endsAt
            remaining = state.remaining
            progress = state.progress
            title = state.phase.title
            switch state.status {
            case .paused: subtitle = "Paused · round \(state.round) of \(state.rounds)"
            case .idle: subtitle = "Ready · round \(state.round) of \(state.rounds)"
            case .running: subtitle = "Round \(state.round) of \(state.rounds) · next: \(state.nextDescription)"
            }
            placement = state.heroPlacement(phaseOver: false)
        }
    }

    var buttonTitle: String {
        isRunning ? "Pause" : (isPaused ? "Resume" : "Start")
    }
}

// MARK: - Lock Screen

struct LockScreenActivityView: View {
    let state: SpiderActivityAttributes.ContentState
    let phaseOver: Bool

    var body: some View {
        let shown = ActivityDisplay(state: state, phaseOver: phaseOver)
        HStack(spacing: 12) {
            ActivityHero(placement: shown.placement, scale: 0.5)
                .frame(width: 56)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label(shown.title, systemImage: shown.phase.symbolName)
                        .font(.headline)
                        .foregroundStyle(shown.phase.color)
                    Spacer()
                    Text(shown.subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
                ActivityCountdown(display: shown)
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                ActivityProgress(display: shown)
                ActivityButtons(display: shown)
            }
            .padding(.vertical, 14)
        }
        .padding(.horizontal, 14)
        .frame(height: 170)
    }
}

// MARK: - Pieces

/// The hero on a short web from the top edge, lower the further the phase has run.
struct ActivityHero: View {
    let placement: HeroPlacement
    let scale: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let gripY = HeroFigure.grip.y * scale
            let below = (HeroFigure.baseSize.height - HeroFigure.grip.y) * scale
            let longest = max(6, geometry.size.height - below - 2)
            let web = 6 + placement.drop * (longest - 6)
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(.white.opacity(0.9))
                    .frame(width: 1.2, height: web)
                HeroFigure(pose: placement.pose, scale: scale)
                    .offset(y: web - gripY)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
        .accessibilityHidden(true)
    }
}

/// In the expanded island the hero hangs from the island itself.
struct IslandHero: View {
    let display: ActivityDisplay

    var body: some View {
        ActivityHero(placement: display.placement, scale: 0.36)
            .frame(width: 44, height: 64)
            .padding(.leading, 6)
    }
}

/// Ticks by itself while running.
struct ActivityCountdown: View {
    let display: ActivityDisplay

    var body: some View {
        Group {
            if display.isRunning, let end = display.end, let start = display.start, end > start {
                Text(timerInterval: start...end, countsDown: true)
            } else {
                Text(TimeFormat.clock(display.remaining))
            }
        }
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .multilineTextAlignment(.trailing)
    }
}

/// Fills by itself while running.
struct ActivityProgress: View {
    let display: ActivityDisplay

    var body: some View {
        Group {
            if display.isRunning, let start = display.start, let end = display.end, end > start {
                ProgressView(timerInterval: start...end, countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
            } else {
                ProgressView(value: display.progress)
            }
        }
        .progressViewStyle(.linear)
        .tint(display.phase.color)
    }
}

struct ActivityButtons: View {
    let display: ActivityDisplay

    var body: some View {
        HStack(spacing: 8) {
            Button(intent: ToggleTimerIntent()) {
                Label(display.buttonTitle, systemImage: display.isRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(display.phase.color, in: Capsule())
            }
            .buttonStyle(.plain)

            Button(intent: SkipPhaseIntent()) {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(.white.opacity(0.15), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Skip")
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
    }
}
#endif
