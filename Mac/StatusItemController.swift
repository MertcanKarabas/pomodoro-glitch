import AppKit
import SpiderCore
import SwiftUI

/// The hero icon and time left in the menu bar. Click it to open the timer panel.
///
/// Plain AppKit status item: updating its text every second costs next to nothing,
/// and it tells us exactly where the icon is so the hanging hero can line up under it.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let controller: TimerController
    private let heroPrefs: HeroPrefs
    private let popover = NSPopover()

    init(controller: TimerController, heroPrefs: HeroPrefs) {
        self.controller = controller
        self.heroPrefs = heroPrefs
        super.init()

        popover.behavior = .transient
        popover.delegate = self

        if let button = statusItem.button {
            button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(togglePanel)
        }
        refresh()
    }

    /// Bottom center of the hero icon, in screen coordinates.
    var iconAnchor: NSPoint? {
        guard let button = statusItem.button, let window = button.window, let cell = button.cell,
              window.frame.width > 0, window.frame.height > 0 else { return nil }
        let iconInWindow = button.convert(cell.imageRect(forBounds: button.bounds), to: nil)
        let icon = window.convertToScreen(iconInWindow)
        guard NSScreen.screens.contains(where: { $0.frame.contains(NSPoint(x: icon.midX, y: icon.midY)) }) else {
            return nil
        }
        return NSPoint(x: icon.midX.rounded(), y: window.frame.minY)
    }

    @objc private func togglePanel() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            // Built fresh each time and dropped on close, so it costs nothing while hidden.
            let panel = NSHostingController(rootView: TimerPanelView(controller: controller, heroPrefs: heroPrefs))
            panel.sizingOptions = .preferredContentSize
            popover.contentViewController = panel
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate()
            panel.view.window?.makeKey()
        }
    }

    func popoverDidClose(_ notification: Notification) {
        popover.contentViewController = nil
    }

    /// Redraws whenever the timer changes (once a second while running).
    private func refresh() {
        withObservationTracking {
            render()
        } onChange: { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
    }

    private func render() {
        guard let button = statusItem.button else { return }
        let state = controller.state
        let time = controller.clockText
        let image = state.phase.isBreak ? HeroIcon.resting : HeroIcon.working
        let title = state.status == .idle ? "" : time
        if button.image !== image { button.image = image }
        if button.title != title { button.title = title }
        let description = switch state.status {
        case .idle: "Spider Pomodoro, \(state.phase.title) ready"
        case .running: "\(state.phase.title), \(time) left"
        case .paused: "\(state.phase.title) paused, \(time) left"
        }
        button.setAccessibilityLabel(description)
    }
}
