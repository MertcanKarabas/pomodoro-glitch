import SpiderCore
import SwiftUI

/// The panel that opens when you click the hero in the menu bar.
struct TimerPanelView: View {
    let controller: TimerController
    let heroPrefs: HeroPrefs
    let notifier: PhaseNotifier
    @State private var showSettings: Bool

    init(controller: TimerController, heroPrefs: HeroPrefs, notifier: PhaseNotifier, showSettings: Bool = false) {
        self.controller = controller
        self.heroPrefs = heroPrefs
        self.notifier = notifier
        _showSettings = State(initialValue: showSettings)
    }

    var body: some View {
        let state = controller.state
        let color = state.phase.color

        VStack(alignment: .leading, spacing: 12) {
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
                SettingsForm(controller: controller, heroPrefs: heroPrefs, notifier: notifier)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Alert when a phase ends", isOn: $notifier.isEnabled)
            Toggle("Hanging hero on desktop", isOn: $heroPrefs.showHero)
            Picker("Hero size", selection: $heroPrefs.size) {
                ForEach(HeroPrefs.Size.allCases) { size in
                    Text(size.title).tag(size)
                }
            }
            .pickerStyle(.segmented)
            .disabled(!heroPrefs.showHero)

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
