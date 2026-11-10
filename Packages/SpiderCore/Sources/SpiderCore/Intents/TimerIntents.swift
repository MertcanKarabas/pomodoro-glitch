import AppIntents
import WidgetKit

/// The Start/Pause button in widgets and the Live Activity.
///
/// Defined once here so the app and the widget extension share the exact same type.
/// On iPhone it's a Live Activity intent, so iOS runs it inside the app (waking it in the
/// background if needed) and the app can update the Dynamic Island right away.
public struct ToggleTimerIntent: AppIntent {
    public static let title: LocalizedStringResource = "Start or pause timer"
    public static let description = IntentDescription("Starts, resumes or pauses the Spider Pomodoro timer.")

    public init() {}

    public func perform() async throws -> some IntentResult {
        await pressed(.toggle)
        return .result()
    }
}

public struct SkipPhaseIntent: AppIntent {
    public static let title: LocalizedStringResource = "Skip to next phase"
    public static let description = IntentDescription("Ends the current work or break and moves to the next one.")

    public init() {}

    public func perform() async throws -> some IntentResult {
        await pressed(.skip)
        return .result()
    }
}

#if os(iOS)
extension ToggleTimerIntent: LiveActivityIntent {}
extension SkipPhaseIntent: LiveActivityIntent {}
#endif

/// Lets apps and widgets register the intents in this package with the system.
public struct SpiderCoreIntents: AppIntentsPackage {}

/// Saves the press for every process on this device and sends it to iCloud for the others.
private func pressed(_ action: TimerAction) async {
    let snapshot = SharedTimer.perform(action)
    // On iPhone this runs inside the app, where WidgetKit doesn't refresh widgets by itself.
    WidgetCenter.shared.reloadAllTimelines()
    // If this fails (offline), the app sends it the next time it checks iCloud.
    _ = try? await CloudSync.shared?.push(snapshot)
}
