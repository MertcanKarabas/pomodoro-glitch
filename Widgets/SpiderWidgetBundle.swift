import SwiftUI
import WidgetKit

@main
struct SpiderWidgetBundle: WidgetBundle {
    var body: some Widget {
        SpiderTimerWidget()
    }
}

struct SpiderTimerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SpiderTimer", provider: TimerProvider()) { entry in
            TimerWidgetView(entry: entry)
        }
        .configurationDisplayName("Spider Pomodoro")
        .description("Time left to work or rest. The hero drops lower as work time runs out.")
        .supportedFamilies(Self.families)
        .contentMarginsDisabled()
    }

    private static var families: [WidgetFamily] {
        #if os(iOS)
        [.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline]
        #else
        [.systemSmall, .systemMedium]
        #endif
    }
}
