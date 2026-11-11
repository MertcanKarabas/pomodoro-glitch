import AppKit
import SpiderCore
import SwiftUI

/// The small timer card that opens when you click the hero.
///
/// - Unpinned: sits beside the hero and closes when you click anywhere else.
/// - Pinned: stays on screen as its own little window you can drag anywhere,
///   and comes back after the app restarts.
@MainActor
final class TimerCardController {
    private let controller: TimerController
    private let prefs: HeroPrefs
    private var panel: NSPanel?
    private var outsideClickMonitors: [Any] = []
    private var dragStart: (mouse: NSPoint, origin: NSPoint)?

    init(controller: TimerController, prefs: HeroPrefs) {
        self.controller = controller
        self.prefs = prefs
    }

    var isShown: Bool { panel?.isVisible ?? false }

    /// The card on screen, or nil while it's closed.
    var frame: NSRect? { isShown ? panel?.frame : nil }

    /// The card appeared, moved or closed (nil), so a hero sitting on it can follow.
    var onFrameChange: ((NSRect?) -> Void)?

    /// Clicking the hero opens the card next to him, or closes it if it's open and not pinned.
    func heroClicked(heroRect: NSRect) {
        if isShown {
            if !prefs.cardPinned { hide() }
            return
        }
        show(beside: heroRect)
    }

    /// The hero started moving: an unpinned card would be left behind, so close it.
    func heroDragBegan() {
        if !prefs.cardPinned { hide() }
    }

    /// Brings back a card that was pinned when the app last quit.
    func restorePinnedCard() {
        guard prefs.cardPinned, let origin = prefs.cardOrigin else { return }
        let panel = makePanel()
        panel.setFrameOrigin(onScreen(origin, size: panel.frame.size))
        panel.orderFrontRegardless()
        onFrameChange?(panel.frame)
    }

    func hide() {
        let wasShown = panel != nil
        closePanel()
        if wasShown { onFrameChange?(nil) }
    }

    private func closePanel() {
        panel?.orderOut(nil)
        panel = nil
        stopWatchingOutsideClicks()
    }

    // MARK: - Showing

    private func show(beside heroRect: NSRect) {
        let panel = makePanel()
        let size = panel.frame.size
        let visible = NSScreen.screens.first { $0.frame.intersects(heroRect) }?.visibleFrame
            ?? NSScreen.main?.visibleFrame ?? .zero
        if prefs.cardPinned, let origin = prefs.cardOrigin {
            panel.setFrameOrigin(onScreen(origin, size: size))
        } else {
            panel.setFrameOrigin(HeroGeometry.cardOrigin(beside: heroRect, cardSize: size, in: visible))
        }
        panel.orderFrontRegardless()
        if !prefs.cardPinned { watchOutsideClicks() }
        onFrameChange?(panel.frame)
    }

    private func makePanel() -> NSPanel {
        closePanel()
        let card = TimerCardView(
            controller: controller,
            prefs: prefs,
            onTogglePin: { [weak self] in self?.togglePin() },
            onClose: { [weak self] in self?.close() },
            onDragChanged: { [weak self] in self?.dragMoved() },
            onDragEnded: { [weak self] in self?.dragEnded() }
        )
        let hosting = FirstClickHostingView(rootView: card)
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)

        let panel = NSPanel(
            contentRect: hosting.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = hosting
        self.panel = panel
        return panel
    }

    /// Keeps a remembered spot fully on a connected display, clear of the menu bar and Dock.
    private func onScreen(_ origin: NSPoint, size: NSSize) -> NSPoint {
        let card = NSRect(origin: origin, size: size)
        let visible = NSScreen.screens.first { $0.visibleFrame.intersects(card) }?.visibleFrame
            ?? NSScreen.main?.visibleFrame ?? card
        return HeroGeometry.keptInside(origin, size: size, visibleFrame: visible)
    }

    // MARK: - Pin, close, drag

    private func togglePin() {
        prefs.cardPinned.toggle()
        if prefs.cardPinned {
            prefs.cardOrigin = panel?.frame.origin
            stopWatchingOutsideClicks()
        } else {
            watchOutsideClicks()
        }
    }

    private func close() {
        prefs.cardPinned = false
        hide()
    }

    /// Dragging the card moves it, and pins it: you put it there, so it stays.
    /// It stays whole on the display under the mouse: it stops at the edges and above the Dock.
    private func dragMoved() {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        if dragStart == nil {
            dragStart = (mouse, panel.frame.origin)
        }
        guard let start = dragStart else { return }
        let wanted = NSPoint(x: start.origin.x + mouse.x - start.mouse.x,
                             y: start.origin.y + mouse.y - start.mouse.y)
        let visible = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }?.visibleFrame
            ?? panel.screen?.visibleFrame
        panel.setFrameOrigin(visible.map { HeroGeometry.keptInside(wanted, size: panel.frame.size, visibleFrame: $0) } ?? wanted)
        onFrameChange?(panel.frame)
    }

    private func dragEnded() {
        dragStart = nil
        guard let panel else { return }
        if !prefs.cardPinned {
            prefs.cardPinned = true
            stopWatchingOutsideClicks()
        }
        prefs.cardOrigin = panel.frame.origin
    }

    // MARK: - Clicks elsewhere

    private func watchOutsideClicks() {
        stopWatchingOutsideClicks()
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
        // Clicks in other apps.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: clicks, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.closeUnlessPinned() }
        }) {
            outsideClickMonitors.append(global)
        }
        // Clicks in our other windows (the menu bar panel). Clicks on the hero toggle the card themselves.
        if let local = NSEvent.addLocalMonitorForEvents(matching: clicks, handler: { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, event.window !== self.panel,
                      event.window?.contentView is HangingHeroView == false else { return }
                self.closeUnlessPinned()
            }
            return event
        }) {
            outsideClickMonitors.append(local)
        }
    }

    private func stopWatchingOutsideClicks() {
        outsideClickMonitors.forEach(NSEvent.removeMonitor)
        outsideClickMonitors.removeAll()
    }

    private func closeUnlessPinned() {
        if !prefs.cardPinned { hide() }
    }
}

/// Buttons work on the first click, even while another app is in front.
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Phase, countdown, progress, Start/Pause and Skip, with pin and close buttons.
struct TimerCardView: View {
    let controller: TimerController
    let prefs: HeroPrefs
    let onTogglePin: () -> Void
    let onClose: () -> Void
    let onDragChanged: () -> Void
    let onDragEnded: () -> Void

    var body: some View {
        let state = controller.state
        let color = state.phase.color
        let pinned = prefs.cardPinned

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Label(state.phase.title, systemImage: state.phase.symbolName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color)
                Spacer()
                Button(action: onTogglePin) {
                    Image(systemName: pinned ? "pin.fill" : "pin")
                        .foregroundStyle(pinned ? AnyShapeStyle(color) : AnyShapeStyle(.secondary))
                }
                .buttonStyle(.plain)
                .help(pinned ? "Unpin: close when I click elsewhere" : "Pin: keep this card on screen")
                .accessibilityLabel(pinned ? "Unpin card" : "Pin card")
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close")
                .accessibilityLabel("Close card")
            }

            Text(controller.clockText)
                .font(.system(size: 42, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
                .frame(maxWidth: .infinity)

            CardProgressBar(value: controller.progress, color: color)

            HStack(spacing: 8) {
                Button {
                    controller.toggle()
                } label: {
                    Label(state.primaryActionTitle, systemImage: state.status == .running ? "pause.fill" : "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CardButtonStyle(fill: color, foreground: .white))

                Button {
                    controller.skip()
                } label: {
                    Image(systemName: "forward.end.fill")
                        .frame(width: 34)
                }
                .buttonStyle(CardButtonStyle(fill: .primary.opacity(0.1), foreground: .primary))
                .help("Skip to \(state.nextDescription(settings: controller.settings))")
                .accessibilityLabel("Skip")
            }

            Text("Next: \(state.nextDescription(settings: controller.settings)) · Today: \(controller.today.text)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(14)
        .frame(width: 250)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.12))
        )
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        // Drag the card by any empty spot to move it (that also pins it).
        .gesture(
            DragGesture(minimumDistance: 3, coordinateSpace: .global)
                .onChanged { _ in onDragChanged() }
                .onEnded { _ in onDragEnded() }
        )
    }
}

/// The card's window never becomes the key window, and macOS greys out tinted controls in
/// such windows, so the card draws its own button and bar to keep the phase color.
private struct CardButtonStyle<Fill: ShapeStyle>: ButtonStyle {
    let fill: Fill
    let foreground: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(fill, in: Capsule())
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Capsule())
    }
}

private struct CardProgressBar: View {
    let value: Double
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.1))
                Capsule().fill(color)
                    .frame(width: max(6, geometry.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: 6)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int((value * 100).rounded())) percent")
    }
}
