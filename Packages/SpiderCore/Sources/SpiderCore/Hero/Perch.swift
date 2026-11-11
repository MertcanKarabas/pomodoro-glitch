import CoreGraphics
import Foundation

/// Where on a desktop widget the hero settled. Where you drop him picks the spot.
public enum PerchSpot: String, Codable, Sendable, CaseIterable {
    /// Sitting on the top edge, legs dangling over the front.
    case top
    /// Hanging upside down from the bottom edge, feet stuck to it.
    case bottom
    /// Behind the widget, peeking over its top edge.
    case face
    /// Gripping the left side.
    case left
    /// Gripping the right side.
    case right

    /// The pose for this spot, given what the timer has him doing (and the mouse). Sitting on
    /// top he acts it out: a laptop at work, his phone on a break.
    public func pose(task: HeroTask, reaction: HeroReaction?) -> HeroPose {
        switch self {
        case .top:
            if reaction == .hello { return .sittingWaving }
            return switch task {
            case .working: .sittingWorking
            case .onBreak: .sittingScrolling
            case .paused: .sitting
            case .asleep: .sittingAsleep
            case .cheering: .sittingWaving
            }
        case .bottom: return .upsideDown
        case .face: return .peeking
        case .left, .right: return .clinging
        }
    }

    /// Clinging to the left side is the right-side pose mirrored.
    public var isMirrored: Bool { self == .left }
}

/// What the hero is sitting on.
public enum PerchSurface: String, Codable, Sendable {
    /// A macOS desktop widget (any of them: macOS doesn't say which is which).
    case desktopWidget
    /// Our own pinned timer card.
    case timerCard
}

/// The hero settled on a desktop widget or the timer card.
public struct Perch: Codable, Equatable, Sendable {
    public var spot: PerchSpot
    public var surface: PerchSurface
    /// The widget's (or card's) visible rectangle, in screen coordinates (y up).
    public var widget: CGRect
    /// How far along the edge he sits, 0...1: left to right on the top and bottom,
    /// bottom to top on the sides.
    public var along: Double

    public init(spot: PerchSpot, surface: PerchSurface = .desktopWidget, widget: CGRect, along: Double) {
        self.spot = spot
        self.surface = surface
        self.widget = widget
        self.along = along
    }
}

/// Screen math for putting the hero on desktop widgets. Points are screen points, y up.
public enum PerchGeometry {
    /// Desktop widget windows are this much bigger than the widget you see, on every side.
    public static let widgetWindowInset: CGFloat = 5
    /// Dropping him this close to a widget still counts as on it.
    public static let reach: CGFloat = 30
    /// How deep the edge zones are that pick the top, bottom and sides.
    public static let edgeBand: CGFloat = 36

    /// The widget he was dropped on, if any (the nearest one when they're close together).
    public static func widget(at point: CGPoint, among widgets: [CGRect]) -> CGRect? {
        widgets
            .filter { $0.insetBy(dx: -reach, dy: -reach).contains(point) }
            .min { distance(point, $0) < distance(point, $1) }
    }

    /// Picks the spot from where on the widget he was dropped: near the top edge he sits on
    /// it, near the bottom he hangs under it, near a side he grips it, and in the middle he
    /// climbs behind it and peeks over.
    public static func perch(droppedAt point: CGPoint, on widget: CGRect,
                             surface: PerchSurface = .desktopWidget) -> Perch {
        let band = min(edgeBand, widget.height / 4, widget.width / 4)
        let spot: PerchSpot =
            if point.y >= widget.maxY - band { .top }
            else if point.y <= widget.minY + band { .bottom }
            else if point.x <= widget.minX + band { .left }
            else if point.x >= widget.maxX - band { .right }
            else { .face }
        let along: Double = switch spot {
        case .top, .bottom, .face: fraction(point.x, from: widget.minX, length: widget.width)
        case .left, .right: fraction(point.y, from: widget.minY, length: widget.height)
        }
        return Perch(spot: spot, surface: surface, widget: widget, along: along)
    }

    /// The point on the widget's edge he holds on to (seat, feet, hands), kept far enough
    /// from the corners that he stays on the widget.
    /// - Parameters:
    ///   - edgeMargin: distance to keep from the ends of the top and bottom edges.
    ///   - sideMargin: distance to keep from the ends of the side edges.
    public static func contact(for perch: Perch, edgeMargin: CGFloat, sideMargin: CGFloat) -> CGPoint {
        let widget = perch.widget
        switch perch.spot {
        case .top, .face, .bottom:
            let x = clamp(widget.minX + perch.along * widget.width,
                          widget.minX + edgeMargin, widget.maxX - edgeMargin, middle: widget.midX)
            return CGPoint(x: x, y: perch.spot == .bottom ? widget.minY : widget.maxY)
        case .left, .right:
            let y = clamp(widget.minY + perch.along * widget.height,
                          widget.minY + sideMargin, widget.maxY - sideMargin, middle: widget.midY)
            return CGPoint(x: perch.spot == .left ? widget.minX : widget.maxX, y: y)
        }
    }

    /// Finds the widget he was on after the widgets were looked up again: the same size, and
    /// close to where it was (or the only one that size, if it was moved further).
    public static func sameWidget(as old: CGRect, among widgets: [CGRect]) -> CGRect? {
        let sameSize = widgets.filter { abs($0.width - old.width) < 2 && abs($0.height - old.height) < 2 }
        let center = CGPoint(x: old.midX, y: old.midY)
        let nearest = sameSize.min { distance(center, $0) < distance(center, $1) }
        guard let nearest else { return nil }
        if sameSize.count == 1 { return nearest }
        return hypot(nearest.midX - old.midX, nearest.midY - old.midY) < 80 ? nearest : nil
    }

    /// Whether an app window covers this spot (so the widget under it can't be seen).
    public static func isCovered(_ point: CGPoint, by windows: [CGRect]) -> Bool {
        windows.contains { $0.contains(point) }
    }

    /// Converts a window rectangle from the window list (y down from the top of the main
    /// display) to screen coordinates (y up from its bottom).
    public static func screenRect(fromWindowBounds rect: CGRect, mainDisplayHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: mainDisplayHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    // MARK: - Helpers

    private static func distance(_ point: CGPoint, _ rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return hypot(dx, dy)
    }

    private static func fraction(_ value: CGFloat, from start: CGFloat, length: CGFloat) -> Double {
        guard length > 0 else { return 0.5 }
        return min(max(Double((value - start) / length), 0), 1)
    }

    private static func clamp(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat, middle: CGFloat) -> CGFloat {
        low <= high ? min(max(value, low), high) : middle
    }
}
