import SpiderCore
import WidgetKit

struct TimerEntry: TimelineEntry {
    let moment: TimerMoment
    let settings: PomodoroSettings

    var date: Date { moment.date }
    var state: TimerState { moment.state }
}

/// Reads the shared timer and plans a picture for every minute until the timer stops.
/// The app and the widget buttons ask WidgetKit to reload whenever the timer changes.
struct TimerProvider: TimelineProvider {
    func placeholder(in context: Context) -> TimerEntry {
        Self.sample
    }

    func getSnapshot(in context: Context, completion: @escaping (TimerEntry) -> Void) {
        completion(context.isPreview ? Self.sample : Self.entries(now: Date())[0])
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TimerEntry>) -> Void) {
        let entries = Self.entries(now: Date())
        let last = entries[entries.count - 1]
        // Still running after the last planned picture (very long chains): plan more then.
        let policy: TimelineReloadPolicy = last.state.status == .running ? .after(last.date) : .never
        completion(Timeline(entries: entries, policy: policy))
    }

    private static func entries(now: Date) -> [TimerEntry] {
        let storage = SharedTimer.makeStorage()
        let settings = storage.loadSettings() ?? .standard
        let saved = storage.loadState() ?? .initial(settings: settings, now: now)
        return TimerTimeline.moments(from: saved, settings: settings, now: now)
            .map { TimerEntry(moment: $0, settings: settings) }
    }

    /// Shown in the widget gallery: work, 18:37 left, round 2.
    static var sample: TimerEntry {
        let now = Date()
        let state = TimerState(
            phase: .work, round: 2, duration: 25 * 60,
            startedAt: now.addingTimeInterval(-383), updatedAt: now
        )
        return TimerEntry(moment: TimerMoment(date: now, state: state, lastFinished: nil), settings: .standard)
    }
}
