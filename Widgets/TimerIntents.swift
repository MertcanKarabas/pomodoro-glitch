import AppIntents
import SpiderCore

/// The play/pause button inside the widget. Runs in the widget's process; the app
/// hears about it through `SharedTimer`'s change notification.
struct ToggleTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "Start or pause timer"
    static let description = IntentDescription("Starts, resumes or pauses the Spider Pomodoro timer.")

    func perform() async throws -> some IntentResult {
        SharedTimer.perform(.toggle)
        return .result()
    }
}

struct SkipPhaseIntent: AppIntent {
    static let title: LocalizedStringResource = "Skip to next phase"
    static let description = IntentDescription("Ends the current work or break and moves to the next one.")

    func perform() async throws -> some IntentResult {
        SharedTimer.perform(.skip)
        return .result()
    }
}
