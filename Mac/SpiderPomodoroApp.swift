import AppKit
import OSLog
import SpiderCore
import SwiftUI
import WidgetKit

@main
struct SpiderPomodoroApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Everything lives in the menu bar and the hanging hero window (see AppDelegate).
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller: TimerController
    private let heroPrefs = HeroPrefs()
    private let sync: SyncCoordinator?
    private var statusItem: StatusItemController?
    private var heroWindow: HangingHeroWindow?
    private var pullTimer: Timer?
    private let log = Logger(subsystem: "SpiderPomodoro", category: "sync")

    override init() {
        let controller = TimerController(
            storage: SharedTimer.makeStorage(),
            onPhaseFinished: PhaseSound.play,
            onSave: {
                WidgetCenter.shared.reloadAllTimelines()
                SharedTimer.postChange()
            }
        )
        self.controller = controller
        sync = CloudSync.shared.map { SyncCoordinator(controller: controller, cloud: $0) }
        super.init()
        controller.startTicking()
        // A desktop widget button changed the timer (the widget sends it to iCloud itself).
        SharedTimer.observeChanges { [controller] in controller.reload() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let statusItem = StatusItemController(controller: controller, heroPrefs: heroPrefs)
        let heroView = HangingHeroView(
            frame: NSRect(origin: .zero, size: HangingHeroWindow.size),
            controller: controller,
            prefs: heroPrefs
        )
        let heroWindow = HangingHeroWindow(heroView: heroView) { [weak statusItem] in statusItem?.iconAnchor }
        heroWindow.start()
        self.statusItem = statusItem
        self.heroWindow = heroWindow

        // iCloud should wake us with a silent push when the iPhone changes the timer, but on the
        // Mac those pushes don't always arrive, so also check every minute (one tiny fetch),
        // after the Mac wakes up, and when the panel opens.
        NSApp.registerForRemoteNotifications()
        sync?.start()
        statusItem.onOpen = { [weak self] in self?.pullFromCloud() }
        pullTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pullFromCloud() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.pullFromCloud() }
        }
    }

    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        log.notice("Registered for iCloud pushes")
    }

    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        log.error("Push registration failed: \(error.localizedDescription, privacy: .public)")
    }

    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {
        log.notice("iCloud push received")
        pullFromCloud()
    }

    /// `spiderpomodoro://start`, `pause`, `toggle`, `skip`, `reset` (handy for Shortcuts or scripts).
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if let action = TimerAction(url: url) { controller.perform(action) }
        }
    }

    private func pullFromCloud() {
        guard let sync else { return }
        Task { await sync.pull() }
    }
}
