import Foundation
import notify

/// The timer as shared between an app and its widgets through their App Group.
///
/// Each target names the group in its Info.plist under `SpiderAppGroup`. When one process
/// changes the timer it posts a Darwin notification so the others can reload.
public enum SharedTimer {
    public static let appGroupID: String? = Bundle.main.object(forInfoDictionaryKey: "SpiderAppGroup") as? String

    /// Sandboxed apps may only use notification names that start with their App Group.
    static var changeNotificationName: String {
        "\(appGroupID ?? "SpiderPomodoro").changed"
    }

    public static func makeStorage() -> TimerStorage {
        if let appGroupID, let defaults = UserDefaults(suiteName: appGroupID) {
            return TimerStorage(defaults: defaults)
        }
        return TimerStorage()
    }

    /// Tells the app and widgets in other processes that the saved timer changed.
    public static func postChange() {
        notify_post(changeNotificationName)
    }

    /// Calls `handler` on the main thread whenever another process changes the timer.
    /// Keep the returned token to stop with `stopObserving(_:)`.
    @MainActor
    @discardableResult
    public static func observeChanges(_ handler: @escaping @MainActor () -> Void) -> Int32 {
        var token: Int32 = NOTIFY_TOKEN_INVALID
        notify_register_dispatch(changeNotificationName, &token, .main) { _ in
            MainActor.assumeIsolated { handler() }
        }
        return token
    }

    public static func stopObserving(_ token: Int32) {
        notify_cancel(token)
    }

    /// Applies a button press made outside the app (a widget button) to the saved timer.
    /// Returns the result, ready to send to the other devices.
    @discardableResult
    public static func perform(
        _ action: TimerAction,
        at now: Date = Date(),
        storage: TimerStorage = makeStorage()
    ) -> SyncSnapshot {
        let settings = storage.loadSettings() ?? .standard
        let saved = storage.loadState() ?? .initial(settings: settings, now: now)
        let next = saved
            .resolved(at: now, settings: settings).state
            .performing(action, at: now, settings: settings)
        storage.save(next)
        storage.saveChange(at: now, by: storage.deviceID)
        postChange()
        return SyncSnapshot(state: next, settings: settings, changedAt: now, changedBy: storage.deviceID)
    }
}
