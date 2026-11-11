import CoreGraphics

/// Screen math for the movable desktop hero and his timer card.
/// Points are in screen coordinates with y going up (as on the Mac).
public enum HeroGeometry {
    /// Keeps the top of the web where the hero, hanging at his lowest, stays on screen.
    /// - Parameters:
    ///   - hangHeight: from the top of the web down to the hero's feet at the end of work.
    ///   - halfWidth: half the hero's width.
    public static func clampedAnchor(
        _ anchor: CGPoint,
        in visibleFrame: CGRect,
        hangHeight: CGFloat,
        halfWidth: CGFloat
    ) -> CGPoint {
        let x = min(max(anchor.x, visibleFrame.minX + halfWidth), visibleFrame.maxX - halfWidth)
        let lowest = min(visibleFrame.minY + hangHeight, visibleFrame.maxY)
        let y = min(max(anchor.y, lowest), visibleFrame.maxY)
        return CGPoint(x: x, y: y)
    }

    /// Moves a window's bottom-left corner so the whole window fits inside `visibleFrame`
    /// (the part of a display between the menu bar and the Dock).
    public static func keptInside(_ origin: CGPoint, size: CGSize, visibleFrame: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(origin.x, visibleFrame.minX), visibleFrame.maxX - size.width),
            y: min(max(origin.y, visibleFrame.minY), visibleFrame.maxY - size.height)
        )
    }

    /// Where a card goes next to the hero: to his right if it fits, otherwise to his left,
    /// level with his middle and kept on screen.
    public static func cardOrigin(
        beside hero: CGRect,
        cardSize: CGSize,
        in visibleFrame: CGRect,
        gap: CGFloat = 12
    ) -> CGPoint {
        var x = hero.maxX + gap
        if x + cardSize.width > visibleFrame.maxX {
            x = hero.minX - gap - cardSize.width
        }
        return keptInside(CGPoint(x: x, y: hero.midY - cardSize.height / 2), size: cardSize, visibleFrame: visibleFrame)
    }
}
