import Foundation

/// Saves the timer, its settings and sync details. Apps and widgets point it at their
/// shared App Group so they all see the same timer.
public final class TimerStorage {
    private let defaults: UserDefaults
    private let stateKey = "timerState.v1"
    private let settingsKey = "settings.v1"
    private let changedAtKey = "changedAt.v1"
    private let changedByKey = "changedBy.v1"
    private let deviceIDKey = "deviceID.v1"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func loadState() -> TimerState? { load(TimerState.self, key: stateKey) }
    public func save(_ state: TimerState) { save(state, key: stateKey) }

    public func loadSettings() -> PomodoroSettings? { load(PomodoroSettings.self, key: settingsKey) }
    public func save(_ settings: PomodoroSettings) { save(settings, key: settingsKey) }

    /// When a person last changed the timer (here or on another device). `.distantPast` if never.
    public func loadChangedAt() -> Date { defaults.object(forKey: changedAtKey) as? Date ?? .distantPast }

    /// Which device made that change (this one if never synced).
    public func loadChangedBy() -> String { defaults.string(forKey: changedByKey) ?? deviceID }

    public func saveChange(at date: Date, by device: String) {
        defaults.set(date, forKey: changedAtKey)
        defaults.set(device, forKey: changedByKey)
    }

    /// A random ID for this device, made on first use. Shared by the app and its widgets.
    public var deviceID: String {
        if let id = defaults.string(forKey: deviceIDKey) { return id }
        let id = UUID().uuidString
        defaults.set(id, forKey: deviceIDKey)
        return id
    }

    private func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
