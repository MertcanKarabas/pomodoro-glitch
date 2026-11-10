import ActivityKit
import Foundation
import OSLog
import SpiderCore

/// Keeps the Live Activity (Dynamic Island and Lock Screen) in step with the timer.
///
/// - Starts it when the timer runs (iOS only allows this while the app is open).
/// - Updates it on every change, including ones from widgets and other devices.
/// - Ends it when the timer goes back to "not started".
@MainActor
final class LiveActivityManager {
    private typealias SpiderActivity = Activity<SpiderActivityAttributes>
    private typealias State = SpiderActivityAttributes.ContentState

    private let controller: TimerController
    /// Activities aren't safe to pass between threads, so keep the ID and look it up.
    private var activityID: String?
    private let log = Logger(subsystem: "SpiderPomodoro", category: "liveActivity")

    init(controller: TimerController) {
        self.controller = controller
        // Pick up the one left from a previous launch; drop any extras.
        let existing = SpiderActivity.activities.map(\.id)
        activityID = existing.first
        for extra in existing.dropFirst() {
            Task { await Self.end(id: extra) }
        }
        observe()
    }

    /// Call when the app comes to the front: the only time a new activity may start.
    func refresh() {
        sync()
    }

    private func observe() {
        withObservationTracking {
            _ = controller.state
            _ = controller.settings
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.sync()
                self?.observe()
            }
        }
        sync()
    }

    private func sync() {
        let state = controller.state
        // Nothing running and no break waiting: no Live Activity.
        if state.status == .idle && !state.phase.isBreak {
            end()
            return
        }

        let content = State(state: state, settings: controller.settings, now: Date())
        // When this phase ends the views switch to the next phase by themselves.
        let staleDate = state.endsAt

        if let id = activityID, Self.isAlive(id: id) {
            Task { await Self.update(id: id, state: content, staleDate: staleDate) }
        } else {
            start(content, staleDate: staleDate)
        }
    }

    private func start(_ state: State, staleDate: Date?) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            let activity = try SpiderActivity.request(
                attributes: SpiderActivityAttributes(),
                content: ActivityContent(state: state, staleDate: staleDate)
            )
            activityID = activity.id
            log.notice("Live Activity started")
        } catch {
            // Expected when the timer starts from another device while this app is in the background.
            log.notice("Live Activity not started: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func end() {
        guard let id = activityID else { return }
        activityID = nil
        Task { await Self.end(id: id) }
        log.notice("Live Activity ended")
    }

    private static func isAlive(id: String) -> Bool {
        guard let activity = SpiderActivity.activities.first(where: { $0.id == id }) else { return false }
        return activity.activityState == .active || activity.activityState == .stale
    }

    private nonisolated static func update(id: String, state: State, staleDate: Date?) async {
        guard let activity = SpiderActivity.activities.first(where: { $0.id == id }) else { return }
        await activity.update(ActivityContent(state: state, staleDate: staleDate))
    }

    private nonisolated static func end(id: String) async {
        guard let activity = SpiderActivity.activities.first(where: { $0.id == id }) else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
    }
}
