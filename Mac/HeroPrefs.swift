import Foundation
import Observation

/// Mac-only display choices for the hanging hero. Not synced: each device decides for itself.
@MainActor
@Observable
final class HeroPrefs {
    enum Size: String, CaseIterable, Identifiable {
        case small, medium, large

        var id: Self { self }
        var title: String { rawValue.capitalized }
        var scale: CGFloat {
            switch self {
            case .small: 0.5
            case .medium: 0.7
            case .large: 0.95
            }
        }
    }

    var showHero: Bool {
        didSet { defaults.set(showHero, forKey: Keys.show) }
    }

    var size: Size {
        didSet { defaults.set(size.rawValue, forKey: Keys.size) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    private enum Keys {
        static let show = "hero.show"
        static let size = "hero.size"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showHero = defaults.object(forKey: Keys.show) as? Bool ?? true
        size = defaults.string(forKey: Keys.size).flatMap(Size.init(rawValue:)) ?? .medium
    }
}
