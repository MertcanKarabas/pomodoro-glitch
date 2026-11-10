import Foundation
import Observation
import OSLog
import UserNotifications

/// Schedules system notifications for upcoming phase ends, so they show up even when the
/// app is closed. Re-plans whenever the timer changes (on this device or from another one).
@MainActor
@Observable
public final class PhaseNotifier {
    /// Per device: the Mac and iPhone can each be switched off.
    public var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Self.enabledKey)
            if isEnabled { Task { await requestPermission() } }
            reschedule()
        }
    }

    @ObservationIgnored private let controller: TimerController
    @ObservationIgnored private let playsSound: Bool
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let log = Logger(subsystem: "SpiderPomodoro", category: "alerts")
    private static let enabledKey = "alerts.enabled"

    /// - Parameter playsSound: off on the Mac, which plays its own sound while running.
    public init(controller: TimerController, playsSound: Bool, defaults: UserDefaults = .standard) {
        self.controller = controller
        self.playsSound = playsSound
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        observeTimer(controller) { [weak self] in self?.reschedule() }
    }

    public func requestPermission() async {
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        } catch {
            log.error("Notification permission failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Replaces the planned notifications with ones for the timer as it is now.
    public func reschedule() {
        let center = UNUserNotificationCenter.current()
        let alerts = isEnabled
            ? PhaseAlerts.upcoming(state: controller.state, settings: controller.settings, now: Date())
            : []
        let playsSound = playsSound
        Task {
            let pending = await center.pendingNotificationRequests()
                .map(\.identifier)
                .filter { $0.hasPrefix(PhaseAlerts.idPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: pending)

            for alert in alerts {
                let content = UNMutableNotificationContent()
                content.title = alert.title
                content.body = alert.body
                content.sound = playsSound ? .default : nil
                content.interruptionLevel = .active
                let delay = max(1, alert.date.timeIntervalSinceNow)
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
                try? await center.add(UNNotificationRequest(identifier: alert.id, content: content, trigger: trigger))
            }
        }
    }
}

/// Calls `onChange` every time the timer or its settings change.
@MainActor
public func observeTimer(_ controller: TimerController, _ onChange: @escaping @MainActor () -> Void) {
    withObservationTracking {
        _ = controller.state
        _ = controller.settings
    } onChange: {
        Task { @MainActor in
            onChange()
            observeTimer(controller, onChange)
        }
    }
}
