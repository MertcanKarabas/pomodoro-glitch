import Foundation

/// Saves timer state and settings. Later this points at the App Group so widgets can read it.
public final class TimerStorage {
    private let defaults: UserDefaults
    private let stateKey = "timerState.v1"
    private let settingsKey = "settings.v1"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func loadState() -> TimerState? { load(TimerState.self, key: stateKey) }
    public func save(_ state: TimerState) { save(state, key: stateKey) }

    public func loadSettings() -> PomodoroSettings? { load(PomodoroSettings.self, key: settingsKey) }
    public func save(_ settings: PomodoroSettings) { save(settings, key: settingsKey) }

    private func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
