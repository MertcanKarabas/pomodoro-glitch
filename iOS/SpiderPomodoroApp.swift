import SpiderCore
import SwiftUI
import UIKit
import WidgetKit

@main
struct SpiderPomodoroApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            TimerScreen(controller: model.controller)
                .onChange(of: scenePhase) { _, phase in
                    // Widget buttons may have changed the timer while we were in the background.
                    if phase == .active { model.controller.reload() }
                }
        }
    }
}

@MainActor
final class AppModel {
    let controller: TimerController

    init() {
        controller = TimerController(
            storage: SharedTimer.makeStorage(),
            onPhaseFinished: { _ in
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            },
            onSave: {
                WidgetCenter.shared.reloadAllTimelines()
                SharedTimer.postChange()
            }
        )
        controller.startTicking()
        SharedTimer.observeChanges { [controller] in controller.reload() }
    }
}
