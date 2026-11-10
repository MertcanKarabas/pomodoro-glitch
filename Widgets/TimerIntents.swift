import AppIntents
import SpiderCore

/// The play/pause button inside the widget. Runs in the widget's process: it saves the
/// timer for the app on this device and sends it to iCloud for the other devices.
struct ToggleTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "Start or pause timer"
    static let description = IntentDescription("Starts, resumes or pauses the Spider Pomodoro timer.")

    func perform() async throws -> some IntentResult {
        await pressed(.toggle)
        return .result()
    }
}

struct SkipPhaseIntent: AppIntent {
    static let title: LocalizedStringResource = "Skip to next phase"
    static let description = IntentDescription("Ends the current work or break and moves to the next one.")

    func perform() async throws -> some IntentResult {
        await pressed(.skip)
        return .result()
    }
}

private func pressed(_ action: TimerAction) async {
    let snapshot = SharedTimer.perform(action)
    // If this fails (offline), the app sends it the next time it checks iCloud.
    try? await CloudSync.shared?.push(snapshot)
}
