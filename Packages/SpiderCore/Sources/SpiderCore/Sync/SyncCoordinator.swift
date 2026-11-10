import Foundation
import OSLog

/// Connects an app's timer to iCloud: sends this device's button presses and adopts
/// newer ones from other devices.
@MainActor
public final class SyncCoordinator {
    private let controller: TimerController
    private let cloud: CloudSync
    private let log = Logger(subsystem: "SpiderPomodoro", category: "sync")
    private var isPrepared = false
    private var pushTask: Task<Void, Never>?

    public init(controller: TimerController, cloud: CloudSync) {
        self.controller = controller
        self.cloud = cloud
        controller.onUserChange = { [weak self] in self?.localChange() }
    }

    /// Sets up iCloud and catches up with the other devices.
    public func start() {
        Task { await pull() }
    }

    /// A button was pressed on this device: send it shortly (quick taps go as one).
    public func localChange() {
        // Cancelling only skips the wait; a save already on its way to iCloud always finishes.
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            Task { [weak self] in await self?.push() }
        }
    }

    /// Fetches the server copy and keeps whichever side is newer.
    public func pull() async {
        guard await prepareIfNeeded() else { return }
        do {
            let remote = try await cloud.fetch()
            let local = controller.snapshot
            switch SyncSnapshot.decide(local: local, remote: remote) {
            case .takeRemote:
                if let remote { adopt(remote) }
            case .pushLocal:
                await push()
            case .keepLocal:
                log.debug("Up to date")
            }
        } catch {
            log.error("Fetch failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func push() async {
        guard await prepareIfNeeded() else { return }
        let local = controller.snapshot
        do {
            let server = try await cloud.push(local)
            if server == local {
                log.notice("Pushed \(local.state.phase.rawValue, privacy: .public) \(local.state.status.rawValue, privacy: .public)")
            } else if SyncSnapshot.decide(local: controller.snapshot, remote: server) == .takeRemote {
                adopt(server)
            }
        } catch {
            log.error("Push failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func adopt(_ remote: SyncSnapshot) {
        controller.apply(remote)
        log.notice("Took remote \(remote.state.phase.rawValue, privacy: .public) \(remote.state.status.rawValue, privacy: .public)")
    }

    private func prepareIfNeeded() async -> Bool {
        if isPrepared { return true }
        do {
            try await cloud.prepare()
            isPrepared = true
            log.notice("iCloud ready")
        } catch {
            log.error("iCloud setup failed: \(error.localizedDescription, privacy: .public)")
        }
        return isPrepared
    }
}
