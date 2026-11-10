import SwiftUI

/// Our own spider hero: red mask with big slanted eyes, navy suit, gold spider badge and belt,
/// red gloves and boots. Cartoon proportions (big head, small body).
public enum HeroPalette {
    public static let red = Color(red: 0.86, green: 0.16, blue: 0.21)
    public static let navy = Color(red: 0.15, green: 0.22, blue: 0.44)
    public static let gold = Color(red: 0.99, green: 0.76, blue: 0.16)
    public static let outline = Color(red: 0.06, green: 0.08, blue: 0.18)
    public static let eye = Color.white
}

public enum HeroPose: String, Sendable, CaseIterable {
    /// Holding the web with both hands, legs dangling. Work time.
    case hanging
    /// Pulling himself up hand over hand. Break time.
    case climbing
    /// One hand on the web, waving. A phase just ended.
    case waving
    /// Eyes closed, z's floating up. Timer not started.
    case sleeping
}

/// The hero alone, hands at the top center. Size scales with `scale`.
public struct HeroFigure: View {
    public static let baseSize = CGSize(width: 84, height: 126)
    /// Where the hands grip the web, inside `baseSize`.
    public static let grip = CGPoint(x: 42, y: 10)

    public var pose: HeroPose
    public var time: Double
    public var scale: CGFloat

    public init(pose: HeroPose, time: Double = 0, scale: CGFloat = 1) {
        self.pose = pose
        self.time = time
        self.scale = scale
    }

    public var body: some View {
        Canvas { context, _ in
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: Self.grip.x, y: Self.grip.y)
            HeroDrawing.drawHero(pose: pose, time: time, in: &context)
        }
        .frame(width: Self.baseSize.width * scale, height: Self.baseSize.height * scale)
        .accessibilityLabel("Spider hero, \(pose.rawValue)")
    }
}

enum HeroDrawing {
    static let outlineWidth: CGFloat = 1.6

    /// Draws the hero with the hand grip at (0, 0). y grows downwards.
    /// Roughly x -38...38, y -8...114.
    static func drawHero(pose: HeroPose, time t: Double, in context: inout GraphicsContext) {
        let climbBeat = (sin(t * 2 * .pi / 0.9) + 1) / 2
        let sway = pose == .hanging ? 1.4 * sin(t * 2 * .pi / 3.4 + 0.8) : 0

        // Hands
        var leftHand = CGPoint(x: -5, y: 1)
        var rightHand = CGPoint(x: 5, y: 1)
        var rightElbow = CGPoint(x: 34, y: 30)
        switch pose {
        case .climbing:
            leftHand.y = 1 - 8 * climbBeat
            rightHand.y = 1 - 8 * (1 - climbBeat)
        case .waving:
            let wave = sin(t * 2 * .pi / 0.7)
            leftHand.x = -1
            rightHand = CGPoint(x: 31 + 3 * wave, y: 22 - 2 * abs(wave))
            rightElbow = CGPoint(x: 38, y: 50)
        case .hanging, .sleeping:
            break
        }

        // Arms go behind the head.
        limb(curve(from: CGPoint(x: -13, y: 57), to: leftHand, control: CGPoint(x: -34, y: 30)),
             color: HeroPalette.navy, width: 7, in: &context)
        limb(curve(from: CGPoint(x: 13, y: 57), to: rightHand, control: rightElbow),
             color: HeroPalette.navy, width: 7, in: &context)

        // Legs and boots
        for side in [-1.0, 1.0] {
            let hip = CGPoint(x: 7 * side, y: 78)
            var lift = 0.0
            if pose == .climbing {
                lift = 11 * (side < 0 ? climbBeat : 1 - climbBeat)
            }
            let foot = CGPoint(x: 8 * side + sway, y: 104 - lift)
            // Straight when dangling; the knee pokes out sideways when the leg is lifted.
            let knee = CGPoint(x: (7.5 + lift * 0.6) * side + sway / 2, y: 91 - lift * 0.4)
            var leg = Path()
            leg.move(to: hip)
            leg.addLine(to: knee)
            leg.addLine(to: foot)
            limb(leg, color: HeroPalette.navy, width: 10, in: &context)
            blob(Path(ellipseIn: CGRect(x: foot.x - 7, y: foot.y - 3, width: 14, height: 9)),
                 color: HeroPalette.red, in: &context)
        }

        // Body with belt and badge
        let torso = Path(roundedRect: CGRect(x: -14, y: 50, width: 28, height: 32), cornerRadius: 10)
        context.fill(torso, with: .color(HeroPalette.navy))
        context.drawLayer { layer in
            layer.clip(to: torso)
            layer.fill(Path(CGRect(x: -15, y: 73, width: 30, height: 4.5)), with: .color(HeroPalette.gold))
        }
        drawBadge(at: CGPoint(x: 0, y: 63), in: &context)
        context.stroke(torso, with: .color(HeroPalette.outline), lineWidth: outlineWidth)

        // Head
        blob(Path(ellipseIn: CGRect(x: -23, y: 9, width: 46, height: 44)), color: HeroPalette.red, in: &context)
        drawEyes(pose: pose, in: &context)

        // Hands on top of everything
        for hand in [leftHand, rightHand] {
            blob(Path(ellipseIn: CGRect(x: hand.x - 5, y: hand.y - 5, width: 10, height: 10)),
                 color: HeroPalette.red, in: &context)
        }

        if pose == .sleeping {
            drawSnores(time: t, in: &context)
        }
    }

    private static func drawEyes(pose: HeroPose, in context: inout GraphicsContext) {
        for side in [-1.0, 1.0] {
            let center = CGPoint(x: 10 * side, y: 33)
            switch pose {
            case .hanging, .climbing:
                let eye = Path(ellipseIn: CGRect(x: -7.5, y: -5, width: 15, height: 10))
                    .applying(CGAffineTransform(rotationAngle: -side * 18 * .pi / 180)
                        .concatenating(CGAffineTransform(translationX: center.x, y: center.y)))
                context.fill(eye, with: .color(HeroPalette.eye))
                context.stroke(eye, with: .color(HeroPalette.outline), lineWidth: 2.2)
            case .waving:
                // Happy closed eyes: ∩
                var arc = Path()
                arc.move(to: CGPoint(x: center.x - 6, y: center.y + 2))
                arc.addQuadCurve(to: CGPoint(x: center.x + 6, y: center.y + 2),
                                 control: CGPoint(x: center.x, y: center.y - 7))
                context.stroke(arc, with: .color(HeroPalette.eye),
                               style: StrokeStyle(lineWidth: 3.2, lineCap: .round))
            case .sleeping:
                // Sleepy closed eyes: ∪
                var arc = Path()
                arc.move(to: CGPoint(x: center.x - 6, y: center.y - 1))
                arc.addQuadCurve(to: CGPoint(x: center.x + 6, y: center.y - 1),
                                 control: CGPoint(x: center.x, y: center.y + 5))
                context.stroke(arc, with: .color(HeroPalette.eye),
                               style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
        }
    }

    /// Small gold spider on the chest.
    private static func drawBadge(at center: CGPoint, in context: inout GraphicsContext) {
        var legs = Path()
        for side in [-1.0, 1.0] {
            for (dy, reach, bend) in [(-2.0, 5.5, -2.5), (-0.5, 6.5, -0.8), (1.0, 6.5, 0.8), (2.5, 5.5, 2.5)] {
                let start = CGPoint(x: center.x + 1.2 * side, y: center.y + dy)
                legs.move(to: start)
                legs.addLine(to: CGPoint(x: center.x + reach * 0.6 * side, y: center.y + dy + bend - 1.2))
                legs.addLine(to: CGPoint(x: center.x + reach * side, y: center.y + dy + bend * 1.6))
            }
        }
        context.stroke(legs, with: .color(HeroPalette.gold), style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
        context.fill(Path(ellipseIn: CGRect(x: center.x - 2.4, y: center.y - 1.5, width: 4.8, height: 6.5)),
                     with: .color(HeroPalette.gold))
        context.fill(Path(ellipseIn: CGRect(x: center.x - 1.7, y: center.y - 4.6, width: 3.4, height: 3.4)),
                     with: .color(HeroPalette.gold))
    }

    private static func drawSnores(time t: Double, in context: inout GraphicsContext) {
        context.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(0.6), radius: 1.2))
            for index in 0..<3 {
                let phase = (t / 2.4 + Double(index) / 3).truncatingRemainder(dividingBy: 1)
                var z = layer
                z.opacity = sin(phase * .pi)
                let text = Text("z")
                    .font(.system(size: 8 + 6 * phase, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.white)
                z.draw(text, at: CGPoint(x: 25 + 10 * phase, y: 16 - 24 * phase))
            }
        }
    }

    // MARK: - Helpers

    private static func curve(from start: CGPoint, to end: CGPoint, control: CGPoint) -> Path {
        var path = Path()
        path.move(to: start)
        path.addQuadCurve(to: end, control: control)
        return path
    }

    /// Thick round stroke with a dark outline (arms, legs).
    private static func limb(_ path: Path, color: Color, width: CGFloat, in context: inout GraphicsContext) {
        context.stroke(path, with: .color(HeroPalette.outline),
                       style: StrokeStyle(lineWidth: width + outlineWidth * 2, lineCap: .round, lineJoin: .round))
        context.stroke(path, with: .color(color),
                       style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }

    /// Filled shape with a dark outline (head, hands, boots).
    private static func blob(_ path: Path, color: Color, in context: inout GraphicsContext) {
        context.fill(path, with: .color(color))
        context.stroke(path, with: .color(HeroPalette.outline), lineWidth: outlineWidth)
    }
}
