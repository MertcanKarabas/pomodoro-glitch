import SpiderCore
import SwiftUI
import WidgetKit

struct TimerWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TimerEntry

    var body: some View {
        switch family {
        case .systemMedium:
            MediumTimerView(entry: entry)
                .containerBackground(for: .widget) { HeroPalette.night }
        #if os(iOS)
        case .accessoryRectangular:
            RectangularTimerView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        case .accessoryCircular:
            CircularTimerView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        case .accessoryInline:
            InlineTimerView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        #endif
        default:
            SmallTimerView(entry: entry)
                .containerBackground(for: .widget) { HeroPalette.night }
        }
    }
}

// MARK: - Home screen / desktop

/// Timer on the left, hero hanging down the right edge.
struct SmallTimerView: View {
    let entry: TimerEntry

    var body: some View {
        let state = entry.state
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                PhaseTag(phase: state.phase)
                Spacer(minLength: 0)
                MinutesLeftText(state: state, date: entry.date, size: 32)
                PhaseProgress(state: state, date: entry.date)
                HStack {
                    RoundDots(completed: state.completedRounds, total: entry.settings.rounds, color: state.phase.color, size: 5)
                    Spacer(minLength: 4)
                    ToggleButton(state: state, showsTitle: false)
                }
            }
            .padding([.leading, .vertical], 14)

            WidgetHero(moment: entry.moment, scale: 0.42)
                .frame(width: 48)
                .padding(.trailing, 4)
        }
        .foregroundStyle(.white)
    }
}

/// Hero hanging on the left, timer and buttons on the right.
struct MediumTimerView: View {
    let entry: TimerEntry

    var body: some View {
        let state = entry.state
        HStack(spacing: 0) {
            WidgetHero(moment: entry.moment, scale: 0.55)
                .frame(width: 96)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    PhaseTag(phase: state.phase)
                    Spacer()
                    RoundDots(completed: state.completedRounds, total: entry.settings.rounds, color: state.phase.color, size: 6)
                }
                MinutesLeftText(state: state, date: entry.date, size: 42)
                PhaseProgress(state: state, date: entry.date)
                Text(state.statusLine(settings: entry.settings))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    ToggleButton(state: state, showsTitle: true)
                    Button(intent: SkipPhaseIntent()) {
                        Image(systemName: "forward.end.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(.white.opacity(0.15), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Skip to \(state.nextDescription(settings: entry.settings))")
                }
            }
            .padding(.vertical, 14)
            .padding(.trailing, 16)
        }
        .foregroundStyle(.white)
    }
}

// MARK: - Lock screen (iPhone)

#if os(iOS)
struct RectangularTimerView: View {
    let entry: TimerEntry

    var body: some View {
        let state = entry.state
        VStack(alignment: .leading, spacing: 2) {
            Label(state.phase.title, systemImage: state.phase.symbolName)
                .font(.headline)
            MinutesLeftText(state: state, date: entry.date, size: 22)
            PhaseProgress(state: state, date: entry.date)
        }
    }
}

struct CircularTimerView: View {
    let entry: TimerEntry

    var body: some View {
        let state = entry.state
        ZStack {
            AccessoryWidgetBackground()
            Gauge(value: 1 - state.progress(at: entry.date)) {
                EmptyView()
            } currentValueLabel: {
                Text("\(TimeFormat.minutesLeft(state.remaining(at: entry.date)))")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
            }
            .gaugeStyle(.accessoryCircularCapacity)
        }
        .accessibilityLabel("\(state.phase.title), \(TimeFormat.minutesLeft(state.remaining(at: entry.date))) minutes left")
    }
}

struct InlineTimerView: View {
    let entry: TimerEntry

    var body: some View {
        let state = entry.state
        let minutes = TimeFormat.minutesLeft(state.remaining(at: entry.date))
        Text(state.status == .paused
             ? "\(state.phase.title) paused · \(minutes) min left"
             : "\(state.phase.title) · \(minutes) min left")
    }
}
#endif

// MARK: - Pieces

/// "18 min". Widgets get a fresh picture at every whole minute left, so plain minutes are
/// always right, even where the system doesn't animate live countdown text.
struct MinutesLeftText: View {
    let state: TimerState
    let date: Date
    let size: CGFloat

    var body: some View {
        let minutes = TimeFormat.minutesLeft(state.remaining(at: date))
        (Text("\(minutes)")
            .font(.system(size: size, weight: .semibold, design: .rounded))
         + Text(" min")
            .font(.system(size: size * 0.45, weight: .semibold, design: .rounded)))
            .monospacedDigit()
            .lineLimit(1)
            .accessibilityLabel("\(minutes) minutes left")
    }
}

/// Moves on at each minute step, like the minutes text.
struct PhaseProgress: View {
    let state: TimerState
    let date: Date

    var body: some View {
        ProgressView(value: state.progress(at: date))
            .progressViewStyle(.linear)
            .tint(state.phase.color)
    }
}

struct PhaseTag: View {
    let phase: Phase

    var body: some View {
        Label(phase.title, systemImage: phase.symbolName)
            .font(.caption.weight(.bold))
            .foregroundStyle(phase.color)
            .lineLimit(1)
    }
}

struct ToggleButton: View {
    let state: TimerState
    let showsTitle: Bool

    var body: some View {
        let symbol = state.status == .running ? "pause.fill" : "play.fill"
        Button(intent: ToggleTimerIntent()) {
            Group {
                if showsTitle {
                    Label(state.primaryActionTitle, systemImage: symbol)
                        .padding(.horizontal, 12)
                } else {
                    Image(systemName: symbol)
                        .padding(.horizontal, 9)
                }
            }
            .font(.system(size: 12, weight: .semibold))
            .padding(.vertical, 7)
            .background(state.phase.color, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(state.primaryActionTitle)
    }
}

/// The hero on a web line hanging from the top edge of this space,
/// lower the further the timer has run.
struct WidgetHero: View {
    let moment: TimerMoment
    let scale: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let placement = moment.heroPlacement
            let gripY = HeroFigure.grip.y * scale
            let heroBelowGrip = (HeroFigure.baseSize.height - HeroFigure.grip.y) * scale
            let longest = max(8, geometry.size.height - heroBelowGrip - 4)
            let webLength = 8 + placement.drop * (longest - 8)

            ZStack(alignment: .top) {
                Rectangle()
                    .fill(.white.opacity(0.9))
                    .frame(width: 1.2, height: webLength)
                HeroFigure(pose: placement.pose, scale: scale)
                    .offset(y: webLength - gripY)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
        .accessibilityHidden(true)
    }
}
