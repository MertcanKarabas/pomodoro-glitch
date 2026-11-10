import AppIntents
import SpiderCore

/// The button intents live in SpiderCore so the app and this extension share one type.
/// This tells the system to look for them there.
struct SpiderWidgetIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] { [SpiderCoreIntents.self] }
}
