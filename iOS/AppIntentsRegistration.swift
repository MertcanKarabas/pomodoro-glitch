import AppIntents
import SpiderCore

/// Registers the widget and Live Activity buttons (defined in SpiderCore) with the app, so
/// iOS can run them inside the app and the Dynamic Island updates right away.
struct SpiderAppIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] { [SpiderCoreIntents.self] }
}
