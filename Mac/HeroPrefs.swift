import Foundation
import Observation
import SpiderCore

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

    /// How often he moves round a widget or the card he's sitting on, at random times.
    enum Wander: String, CaseIterable, Identifiable {
        case rarely, hourly, often

        var id: Self { self }
        var title: String { rawValue.capitalized }
        /// The average wait between moves.
        var seconds: Double {
            switch self {
            case .rarely: 12 * 60 * 60
            case .hourly: 60 * 60
            case .often: 5 * 60
            }
        }
    }

    var showHero: Bool {
        didSet { defaults.set(showHero, forKey: Keys.show) }
    }

    var size: Size {
        didSet { defaults.set(size.rawValue, forKey: Keys.size) }
    }

    /// Where the top of the web is after the hero was dragged somewhere (screen coordinates).
    /// Nil: he hangs under the menu bar icon.
    var customAnchor: CGPoint? {
        didSet { save(customAnchor, key: Keys.anchor) }
    }

    /// Menu bar shows "24:13" instead of "24m". Off by default: a time that changes every
    /// second makes macOS redraw the menu bar (on every display) every second.
    var menuBarSeconds: Bool {
        didSet { defaults.set(menuBarSeconds, forKey: Keys.menuBarSeconds) }
    }

    var wander: Wander {
        didSet { defaults.set(wander.rawValue, forKey: Keys.wander) }
    }

    /// The desktop widget he's sitting on, or nil while he's on his web.
    var perch: Perch? {
        didSet { defaults.set(perch.flatMap { try? JSONEncoder().encode($0) }, forKey: Keys.perch) }
    }

    /// The timer card stays on screen as its own window.
    var cardPinned: Bool {
        didSet { defaults.set(cardPinned, forKey: Keys.cardPinned) }
    }

    /// Bottom-left corner of the pinned card (screen coordinates).
    var cardOrigin: CGPoint? {
        didSet { save(cardOrigin, key: Keys.cardOrigin) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    private enum Keys {
        static let show = "hero.show"
        static let size = "hero.size"
        static let anchor = "hero.anchor"
        static let perch = "hero.perch"
        static let wander = "hero.wander"
        static let menuBarSeconds = "menuBar.seconds"
        static let cardPinned = "card.pinned"
        static let cardOrigin = "card.origin"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showHero = defaults.object(forKey: Keys.show) as? Bool ?? true
        size = defaults.string(forKey: Keys.size).flatMap(Size.init(rawValue:)) ?? .medium
        wander = defaults.string(forKey: Keys.wander).flatMap(Wander.init(rawValue:)) ?? .rarely
        menuBarSeconds = defaults.bool(forKey: Keys.menuBarSeconds)
        customAnchor = Self.load(defaults, key: Keys.anchor)
        perch = defaults.data(forKey: Keys.perch).flatMap { try? JSONDecoder().decode(Perch.self, from: $0) }
        cardPinned = defaults.bool(forKey: Keys.cardPinned)
        cardOrigin = Self.load(defaults, key: Keys.cardOrigin)
    }

    private func save(_ point: CGPoint?, key: String) {
        if let point {
            defaults.set([point.x, point.y], forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private static func load(_ defaults: UserDefaults, key: String) -> CGPoint? {
        guard let values = defaults.array(forKey: key) as? [Double], values.count == 2 else { return nil }
        return CGPoint(x: values[0], y: values[1])
    }
}
