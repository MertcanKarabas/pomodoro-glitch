import AppKit

/// Small menu bar picture of the hero hanging on his web line.
/// Template image: macOS colors it to match the menu bar (light or dark).
/// The full hero art comes in step 2.
enum HeroIcon {
    @MainActor static let working = make(resting: false)
    @MainActor static let resting = make(resting: true)

    private static func make(resting: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            draw(resting: resting)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = resting ? "Spider hero resting" : "Spider hero working"
        return image
    }

    static func draw(resting: Bool) {
        NSColor.black.set()

        let web = NSBezierPath()
        web.move(to: NSPoint(x: 9, y: 0))
        web.line(to: NSPoint(x: 9, y: 4.5))
        web.lineWidth = 1.3
        web.stroke()

        NSBezierPath(ovalIn: NSRect(x: 3, y: 4, width: 12, height: 13)).fill()

        // Cut the eyes out so the menu bar shows through.
        NSGraphicsContext.current?.compositingOperation = .destinationOut
        if resting {
            for x in [6.3, 11.7] {
                let lid = NSBezierPath()
                lid.move(to: NSPoint(x: x - 1.9, y: 11))
                lid.curve(to: NSPoint(x: x + 1.9, y: 11),
                          controlPoint1: NSPoint(x: x - 1, y: 9),
                          controlPoint2: NSPoint(x: x + 1, y: 9))
                lid.lineWidth = 1.4
                lid.lineCapStyle = .round
                lid.stroke()
            }
        } else {
            eye(center: NSPoint(x: 6.3, y: 10.4), degrees: 28).fill()
            eye(center: NSPoint(x: 11.7, y: 10.4), degrees: -28).fill()
        }
        NSGraphicsContext.current?.compositingOperation = .sourceOver
    }

    private static func eye(center: NSPoint, degrees: CGFloat) -> NSBezierPath {
        let path = NSBezierPath(ovalIn: NSRect(x: -2.3, y: -1.5, width: 4.6, height: 3))
        var rotate = AffineTransform()
        rotate.rotate(byDegrees: degrees)
        path.transform(using: rotate)
        path.transform(using: AffineTransform(translationByX: center.x, byY: center.y))
        return path
    }
}
