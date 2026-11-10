import SpiderCore
import SwiftUI

struct SettingsSheet: View {
    let controller: TimerController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Minutes") {
                    minutesRow("Work", \.workMinutes)
                    minutesRow("Break", \.shortBreakMinutes)
                    minutesRow("Long break", \.longBreakMinutes)
                }
                Section {
                    Stepper(value: binding(\.roundsBeforeLongBreak), in: PomodoroSettings.roundsRange) {
                        Text("Long break after \(controller.settings.rounds) rounds")
                    }
                    Toggle("Auto-start breaks", isOn: binding(\.autoStartBreaks))
                    Toggle("Auto-start work", isOn: binding(\.autoStartWork))
                } footer: {
                    Text("New times apply from the next phase.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
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
