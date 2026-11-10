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
    private var statusItem: StatusItemController?
    private var heroWindow: HangingHeroWindow?

    override init() {
        controller = TimerController(
            storage: SharedTimer.makeStorage(),
            onPhaseFinished: PhaseSound.play,
            onSave: {
                WidgetCenter.shared.reloadAllTimelines()
                SharedTimer.postChange()
            }
        )
        super.init()
        controller.startTicking()
        // A desktop widget button changed the timer.
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
    }
}
