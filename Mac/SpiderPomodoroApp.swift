import AppKit
import OSLog
import SpiderCore
import SwiftUI
import UserNotifications
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
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private let controller: TimerController
    private let heroPrefs = HeroPrefs()
    private let sync: SyncCoordinator?
    private let notifier: PhaseNotifier
    /// Looks for newer releases on GitHub (nil if the build doesn't name a repository).
    private let updates: UpdateChecker?
    private var statusItem: StatusItemController?
    private var heroWindow: HangingHeroWindow?
    private var timerCard: TimerCardController?
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
        // Banners only: the Mac plays its own sound while the app runs.
        notifier = PhaseNotifier(controller: controller, playsSound: false)
        updates = UpdateChecker(onNewUpdate: AppDelegate.announce)
        super.init()
        controller.startTicking()
        // A desktop widget button changed the timer (the widget sends it to iCloud itself).
        SharedTimer.observeChanges { [controller] in controller.reload() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        if notifier.isEnabled {
            Task { await notifier.requestPermission() }
        }

        updates?.startAutomaticChecks()

        let statusItem = StatusItemController(
            controller: controller, heroPrefs: heroPrefs, notifier: notifier, updates: updates
        )
        let heroView = HangingHeroView(
            frame: NSRect(origin: .zero, size: HangingHeroWindow.size),
            controller: controller,
            prefs: heroPrefs
        )
        let heroWindow = HangingHeroWindow(heroView: heroView, prefs: heroPrefs) { [weak statusItem] in
            statusItem?.iconAnchor
        }
        let timerCard = TimerCardController(controller: controller, prefs: heroPrefs)
        heroWindow.onHeroClick = { [weak timerCard] heroRect in timerCard?.heroClicked(heroRect: heroRect) }
        heroWindow.onHeroDragBegan = { [weak timerCard] in timerCard?.heroDragBegan() }
        // He can climb the pinned card, and follows it when it moves.
        heroWindow.cardFrame = { [weak timerCard] in timerCard?.frame }
        timerCard.onFrameChange = { [weak heroWindow] frame in heroWindow?.cardFrameChanged(frame) }
        timerCard.restorePinnedCard()
        heroWindow.start()
        self.statusItem = statusItem
        self.heroWindow = heroWindow
        self.timerCard = timerCard

        // iCloud should wake us with a silent push when the iPhone changes the timer, but on the
        // Mac those pushes don't always arrive, so also check every minute (one tiny fetch),
        // after the Mac wakes up, and when the panel opens.
        NSApp.registerForRemoteNotifications()
        sync?.start()
        statusItem.onOpen = { [weak self] in self?.pullFromCloud() }
        pullTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pullFromCloud() }
        }
        pullTimer?.tolerance = 10
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.pullFromCloud() }
        }
    }

    /// Show phase-end banners even though the app counts as "running".
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    /// Clicking the "new version" notification opens its release page.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let link = response.notification.request.content.userInfo["url"] as? String,
              let url = URL(string: link) else { return }
        await MainActor.run { _ = NSWorkspace.shared.open(url) }
    }

    /// One notification per new version.
    private static func announce(_ update: AvailableUpdate) {
        let content = UNMutableNotificationContent()
        content.title = "Spider Pomodoro \(update.version) is available"
        content.body = "Click to see what's new and download it."
        content.userInfo = ["url": update.pageURL.absoluteString]
        let request = UNNotificationRequest(identifier: "update-\(update.version)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
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
