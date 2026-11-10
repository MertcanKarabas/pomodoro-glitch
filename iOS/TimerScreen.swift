import SpiderCore
import SwiftUI

/// The iPhone app's one screen: the hero hangs from the top (right below the
/// Dynamic Island) and drops as work time runs out; the timer sits at the bottom.
struct TimerScreen: View {
    let controller: TimerController
    let notifier: PhaseNotifier
    @State private var showSettings = false

    var body: some View {
        let state = controller.state
        let color = state.phase.color

        GeometryReader { geometry in
            ZStack(alignment: .top) {
                HeroPalette.night.ignoresSafeArea()

                HangingHeroStage(
                    state: state,
                    lastFinished: controller.lastFinished,
                    shortestWeb: geometry.safeAreaInsets.top + 6,
                    dropDistance: geometry.size.height * 0.4,
                    scale: 1.1
                )
                .ignoresSafeArea(edges: .top)

                VStack(alignment: .leading, spacing: 14) {
                    Spacer()

                    HStack {
                        Label(state.phase.title, systemImage: state.phase.symbolName)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(color)
                        Spacer()
                        RoundDots(completed: state.completedRounds, total: controller.settings.rounds, color: color, size: 9)
                    }

                    Text(controller.clockText)
                        .font(.system(size: 84, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("\(controller.clockText) left")

                    ProgressView(value: controller.progress)
                        .tint(color)

                    HStack {
                        Text(state.statusLine(settings: controller.settings))
                        Spacer()
                        Label("Today: \(controller.today.text)", systemImage: "checkmark.seal")
                            .labelStyle(.titleAndIcon)
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                    HStack(spacing: 12) {
                        Button {
                            controller.toggle()
                        } label: {
                            Label(state.primaryActionTitle, systemImage: state.status == .running ? "pause.fill" : "play.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(color)

                        Button {
                            controller.skip()
                        } label: {
                            Image(systemName: "forward.end.fill")
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Skip to \(state.nextDescription(settings: controller.settings))")

                        Button {
                            controller.reset()
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Back to round 1")
                    }
                    .controlSize(.large)
                    .tint(.white)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .padding(20)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(controller: controller, notifier: notifier)
                .presentationDetents([.medium, .large])
        }
        .preferredColorScheme(.dark)
    }
}
