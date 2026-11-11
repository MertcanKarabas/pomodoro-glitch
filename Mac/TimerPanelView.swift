import SpiderCore
import SwiftUI

/// The panel that opens when you click the hero in the menu bar.
struct TimerPanelView: View {
    let controller: TimerController
    let heroPrefs: HeroPrefs
    let notifier: PhaseNotifier
    let updates: UpdateChecker?
    @State private var showSettings: Bool

    init(
        controller: TimerController,
        heroPrefs: HeroPrefs,
        notifier: PhaseNotifier,
        updates: UpdateChecker? = nil,
        showSettings: Bool = false
    ) {
        self.controller = controller
        self.heroPrefs = heroPrefs
        self.notifier = notifier
        self.updates = updates
        _showSettings = State(initialValue: showSettings)
    }

    var body: some View {
        let state = controller.state
        let color = state.phase.color

        VStack(alignment: .leading, spacing: 12) {
            if let update = updates?.availableUpdate {
                UpdateBanner(update: update)
            }

            HStack {
                Label(state.phase.title, systemImage: state.phase.symbolName)
                    .font(.headline)
                    .foregroundStyle(color)
                Spacer()
                RoundDots(completed: state.completedRounds, total: controller.settings.rounds, color: color)
            }

            Text(controller.clockText)
                .font(.system(size: 54, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
                .frame(maxWidth: .infinity)

            ProgressView(value: controller.progress)
                .tint(color)

            VStack(alignment: .leading, spacing: 2) {
                Text(state.statusLine(settings: controller.settings))
                Label("Today: \(controller.today.text)", systemImage: "checkmark.seal")
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button {
                    controller.toggle()
                } label: {
                    Label(primaryTitle, systemImage: state.status == .running ? "pause.fill" : "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(color)
                .keyboardShortcut(.defaultAction)

                Button("Skip", systemImage: "forward.end.fill") { controller.skip() }
                    .labelStyle(.iconOnly)
                    .help("Skip to \(state.nextDescription(settings: controller.settings))")

                Button("Reset", systemImage: "arrow.counterclockwise") { controller.reset() }
                    .labelStyle(.iconOnly)
                    .help("Back to round 1")
            }
            .controlSize(.large)

            Divider()

            DisclosureGroup("Settings", isExpanded: $showSettings) {
                SettingsForm(controller: controller, heroPrefs: heroPrefs, notifier: notifier, updates: updates)
            }

            Divider()

            Button("Quit Spider Pomodoro") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.link)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(16)
        .frame(width: 300)
    }

    private var primaryTitle: String { controller.state.primaryActionTitle }
}

private struct SettingsForm: View {
    let controller: TimerController
    @Bindable var heroPrefs: HeroPrefs
    @Bindable var notifier: PhaseNotifier
    let updates: UpdateChecker?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Alert when a phase ends", isOn: $notifier.isEnabled)
            Toggle("Seconds in menu bar", isOn: $heroPrefs.menuBarSeconds)
                .help("Show 24:13 instead of 24m. Uses a little more battery: the menu bar redraws every second.")
            Toggle("Hanging hero on desktop", isOn: $heroPrefs.showHero)
            Picker("Hero size", selection: $heroPrefs.size) {
                ForEach(HeroPrefs.Size.allCases) { size in
                    Text(size.title).tag(size)
                }
            }
            .pickerStyle(.segmented)
            .disabled(!heroPrefs.showHero)
            Picker("Wandering", selection: $heroPrefs.wander) {
                ForEach(HeroPrefs.Wander.allCases) { wander in
                    Text(wander.title).tag(wander)
                }
            }
            .pickerStyle(.segmented)
            .disabled(!heroPrefs.showHero)
            .help("How often he moves round a widget or the pinned card, at random times. Rarely is about twice a day.")
            HStack(alignment: .firstTextBaseline) {
                Text("Drag the hero to move him, or onto the pinned card or a desktop widget to climb it. Click him for a timer card.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                Button("Back under the menu bar") {
                    heroPrefs.perch = nil
                    heroPrefs.customAnchor = nil
                }
                .controlSize(.small)
                .disabled(!heroPrefs.showHero || (heroPrefs.customAnchor == nil && heroPrefs.perch == nil))
            }

            Divider()
                .padding(.vertical, 2)

            minutesRow("Work", \.workMinutes)
            minutesRow("Break", \.shortBreakMinutes)
            minutesRow("Long break", \.longBreakMinutes)
            Stepper(value: binding(\.roundsBeforeLongBreak), in: PomodoroSettings.roundsRange) {
                Text("Long break after \(controller.settings.rounds) rounds")
            }
            Toggle("Auto-start breaks", isOn: binding(\.autoStartBreaks))
            Toggle("Auto-start work", isOn: binding(\.autoStartWork))
            Text("New times apply from the next phase.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let updates {
                Divider()
                    .padding(.vertical, 2)
                UpdateSettings(updates: updates)
            }
        }
        .padding(.top, 8)
    }

    private func minutesRow(_ title: String, _ keyPath: WritableKeyPath<PomodoroSettings, Int>) -> some View {
        Stepper(value: binding(keyPath), in: PomodoroSettings.minuteRange) {
            HStack {
                Text(title)
                Spacer()
                Text("\(controller.settings[keyPath: keyPath]) min")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<PomodoroSettings, Value>) -> Binding<Value> {
        Binding(
            get: { controller.settings[keyPath: keyPath] },
            set: { newValue in
                var settings = controller.settings
                settings[keyPath: keyPath] = newValue
                controller.update(settings: settings)
            }
        )
    }
}

/// "Version 1.1 is available" with a Download button, at the top of the panel.
private struct UpdateBanner: View {
    let update: AvailableUpdate

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text("Version \(update.version.description) is available")
                    .font(.callout.weight(.semibold))
                    .fixedSize()
                Button("See what's new") { NSWorkspace.shared.open(update.pageURL) }
                    .buttonStyle(.link)
                    .font(.caption)
            }
            Spacer(minLength: 4)
            Button("Download") { NSWorkspace.shared.open(update.downloadURL ?? update.pageURL) }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(10)
        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Version, "Check for Updates" and the automatic-check switch.
private struct UpdateSettings: View {
    @Bindable var updates: UpdateChecker

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button("Check for Updates") {
                    Task { await updates.check() }
                }
                .disabled(updates.status == .checking)
                Spacer()
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Toggle("Check for updates automatically", isOn: $updates.checksAutomatically)
        }
    }

    private var statusText: String {
        switch updates.status {
        case .idle: "Version \(updates.currentVersion)"
        case .checking: "Checking…"
        case .upToDate: "Up to date (\(updates.currentVersion))"
        case .available(let update): "\(update.version) available"
        case .failed: "Couldn't check. Try again later."
        }
    }
}
