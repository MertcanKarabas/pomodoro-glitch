import OSLog
import SpiderCore
import SwiftUI
import UIKit
import WidgetKit

@main
struct SpiderPomodoroApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            TimerScreen(controller: appDelegate.model.controller)
                .onChange(of: scenePhase) { _, phase in
                    // Widget buttons or the Mac may have changed the timer while we were away.
                    if phase == .active { appDelegate.model.catchUp() }
                }
                .onOpenURL { url in
                    if let action = TimerAction(url: url) { appDelegate.model.controller.perform(action) }
                }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    let model = AppModel()
    private let log = Logger(subsystem: "SpiderPomodoro", category: "sync")

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // iCloud wakes the app with a silent push when the Mac changes the timer.
        application.registerForRemoteNotifications()
        model.sync?.start()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        log.notice("Registered for iCloud pushes")
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        log.error("Push registration failed: \(error.localizedDescription, privacy: .public)")
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any]
    ) async -> UIBackgroundFetchResult {
        log.notice("iCloud push received")
        guard let sync = model.sync else { return .noData }
        await sync.pull()
        return .newData
    }
}

@MainActor
final class AppModel {
    let controller: TimerController
    let sync: SyncCoordinator?

    init() {
        let controller = TimerController(
            storage: SharedTimer.makeStorage(),
            onPhaseFinished: { _ in
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            },
            onSave: {
                WidgetCenter.shared.reloadAllTimelines()
                SharedTimer.postChange()
            }
        )
        self.controller = controller
        sync = CloudSync.shared.map { SyncCoordinator(controller: controller, cloud: $0) }
        controller.startTicking()
        SharedTimer.observeChanges { [controller] in controller.reload() }
    }

    /// Picks up widget presses, then checks iCloud.
    func catchUp() {
        controller.reload()
        guard let sync else { return }
        Task { await sync.pull() }
    }
}
