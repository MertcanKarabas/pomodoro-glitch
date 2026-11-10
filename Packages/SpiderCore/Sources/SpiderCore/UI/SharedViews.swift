import SwiftUI

extension Phase {
    /// Red for work, teal for breaks.
    public var color: Color {
        isBreak ? Color(red: 0.10, green: 0.66, blue: 0.66) : Color(red: 0.90, green: 0.22, blue: 0.24)
    }

    public var symbolName: String {
        isBreak ? "cup.and.saucer.fill" : "flame.fill"
    }
}

extension HeroPalette {
    /// Night-sky navy behind the hero in the iPhone app and widgets.
    public static let night = LinearGradient(
        colors: [Color(red: 0.09, green: 0.11, blue: 0.24), Color(red: 0.04, green: 0.05, blue: 0.12)],
        startPoint: .top,
        endPoint: .bottom
    )
}

extension TimerState {
    /// "5 min break", "15 min long break" or "work, round 2 of 4".
    public func nextDescription(settings: PomodoroSettings) -> String {
        let next = nextPhase(settings: settings)
        if next.phase == .work {
            return "work, round \(next.round) of \(settings.rounds)"
        }
        return "\(settings.minutes(of: next.phase)) min \(next.phase.title.lowercased())"
    }

    /// Label for the main button: "Start work", "Pause", "Resume"...
    public var primaryActionTitle: String {
        switch status {
        case .running: "Pause"
        case .paused: "Resume"
        case .idle: phase.isBreak ? "Start break" : "Start work"
        }
    }

    /// "Next: 5 min break", with "Paused · " in front while paused.
    public func statusLine(settings: PomodoroSettings) -> String {
        let next = "Next: \(nextDescription(settings: settings))"
        return status == .paused ? "Paused · \(next)" : next
    }
}

/// One dot per work round in the set, filled when done.
public struct RoundDots: View {
    public var completed: Int
    public var total: Int
    public var color: Color
    public var size: CGFloat

    public init(completed: Int, total: Int, color: Color, size: CGFloat = 7) {
        self.completed = completed
        self.total = total
        self.color = color
        self.size = size
    }

    public var body: some View {
        HStack(spacing: size * 0.6) {
            ForEach(0..<total, id: \.self) { index in
                Circle()
                    .fill(index < completed ? AnyShapeStyle(color) : AnyShapeStyle(.quaternary))
                    .frame(width: size, height: size)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(completed) of \(total) rounds done")
    }
}
