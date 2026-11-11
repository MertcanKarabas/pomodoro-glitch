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
    /// Shaken on the Mac: spiral eyes, stars circling his head, one hand let go.
    case dizzy
    /// Shaken a lot: angry eyes, steam puffs, shaking a fist.
    case grumpy

    // On a Mac desktop widget.
    /// Sitting on the widget's top edge, swinging his legs.
    case sitting
    /// Sitting on the widget, asleep.
    case sittingAsleep
    /// Sitting on the widget, waving.
    case sittingWaving
    /// Feet stuck under the widget, hanging head-down with arms crossed.
    case upsideDown
    /// Behind the widget, peeking over the top edge and looking around.
    case peeking
    /// Gripping the widget's right side (mirror it for the left).
    case clinging
    /// Walking along the widget's top edge.
    case walking
    /// Walking upside down along the widget's bottom edge.
    case upsideDownWalking
    /// Upside down under the widget, spying on it through binoculars.
    case spying
    /// Sitting on the widget, typing on a laptop, coffee beside him. Work time.
    case sittingWorking
    /// Sitting on the widget, scrolling his phone (and laughing now and then). Break time.
    case sittingScrolling
    /// Hanging from his web with one hand, scrolling his phone with the other. Break time.
    case hangingScrolling
}

/// Just the hero's masked head, for tight spots like the Dynamic Island.
public struct HeroHead: View {
    public var pose: HeroPose
    public var size: CGFloat

    public init(pose: HeroPose, size: CGFloat) {
        self.pose = pose
        self.size = size
    }

    public var body: some View {
        Canvas { context, _ in
            context.scaleBy(x: size / 48, y: size / 48)
            // Head spans x -23...23, y 9...53: shift it into a 48-point square.
            context.translateBy(x: 24, y: -7)
            HeroDrawing.drawHead(pose: pose, in: &context)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
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

    /// The picture's size for a pose, and the point he holds on with: his hands on the web,
    /// or on a widget his seat, feet or hands on its edge.
    public static func layout(for pose: HeroPose) -> (size: CGSize, contact: CGPoint) {
        switch pose {
        case .hanging, .climbing, .waving, .sleeping, .dizzy, .grumpy, .hangingScrolling:
            (baseSize, grip)
        case .sitting, .sittingAsleep, .sittingWaving, .sittingWorking, .sittingScrolling:
            (CGSize(width: 90, height: 136), CGPoint(x: 45, y: 100))
        case .upsideDown, .upsideDownWalking, .spying:
            (CGSize(width: 84, height: 116), CGPoint(x: 42, y: 6))
        case .walking:
            (CGSize(width: 84, height: 118), CGPoint(x: 42, y: 112))
        case .peeking:
            (CGSize(width: 84, height: 60), CGPoint(x: 42, y: 44))
        case .clinging:
            (CGSize(width: 70, height: 116), CGPoint(x: 12, y: 66))
        }
    }

    public var body: some View {
        let layout = Self.layout(for: pose)
        Canvas { context, _ in
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: layout.contact.x, y: layout.contact.y)
            HeroDrawing.drawHero(pose: pose, time: time, in: &context)
        }
        .frame(width: layout.size.width * scale, height: layout.size.height * scale)
        .accessibilityLabel("Spider hero, \(pose.rawValue)")
    }
}

enum HeroDrawing {
    static let outlineWidth: CGFloat = 1.6

    /// Draws the hero with his contact point (see `HeroFigure.layout`) at (0, 0). y grows
    /// downwards. On the web that's the hand grip; he spans roughly x -38...38, y -8...114.
    static func drawHero(pose: HeroPose, time t: Double, in context: inout GraphicsContext) {
        switch pose {
        case .sitting, .sittingAsleep, .sittingWaving, .sittingWorking, .sittingScrolling:
            return drawSitting(pose: pose, time: t, in: &context)
        case .upsideDown: return drawStanding(.armsCrossed, upsideDown: true, time: t, in: &context)
        case .upsideDownWalking: return drawStanding(.walking, upsideDown: true, time: t, in: &context)
        case .spying: return drawStanding(.binoculars, upsideDown: true, time: t, in: &context)
        case .walking: return drawStanding(.walking, upsideDown: false, time: t, in: &context)
        case .peeking: return drawPeeking(time: t, in: &context)
        case .clinging: return drawClinging(time: t, in: &context)
        case .hanging, .climbing, .waving, .sleeping, .dizzy, .grumpy, .hangingScrolling: break
        }
        // Laughing at something on his phone: a little shake.
        if pose == .hangingScrolling, isLaughing(t) {
            context.translateBy(x: 0.8 * sin(t * 2 * .pi / 0.3), y: 0)
        }

        let climbBeat = (sin(t * 2 * .pi / 0.9) + 1) / 2
        let sway: Double = switch pose {
        case .hanging, .hangingScrolling: 1.4 * sin(t * 2 * .pi / 3.4 + 0.8)
        // Legs flop about while he's dizzy and kick while he's cross.
        case .dizzy: 4 * sin(t * 2 * .pi / dizzyCycle)
        case .grumpy: 2 * sin(t * 2 * .pi / 0.3)
        case .climbing, .waving, .sleeping: 0
        case .sitting, .sittingAsleep, .sittingWaving, .upsideDown, .peeking, .clinging,
             .walking, .upsideDownWalking, .spying, .sittingWorking, .sittingScrolling: 0
        }

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
        case .dizzy:
            // One hand let go and dangles limp.
            leftHand.x = -1
            rightHand = CGPoint(x: 20, y: 86 + 2 * sin(t * 2 * .pi / dizzyCycle))
            rightElbow = CGPoint(x: 27, y: 70)
        case .grumpy:
            // Shakes a fist.
            leftHand.x = -1
            rightHand = CGPoint(x: 29, y: 15 + 4 * sin(t * 2 * .pi / 0.3))
            rightElbow = CGPoint(x: 41, y: 44)
        case .hangingScrolling:
            // One hand on the web, the other holding his phone.
            leftHand.x = -1
            rightHand = CGPoint(x: 10, y: 63 + phoneBob(t))
            rightElbow = CGPoint(x: 26, y: 70)
        case .hanging, .sleeping, .sitting, .sittingAsleep, .sittingWaving, .upsideDown, .peeking, .clinging,
             .walking, .upsideDownWalking, .spying, .sittingWorking, .sittingScrolling:
            break
        }

        if pose == .dizzy {
            drawStars(time: t, front: false, in: &context)
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

        drawHead(pose: pose, time: t, in: &context)
        if pose == .hangingScrolling {
            drawPhoneInHand(phone: CGPoint(x: 10, y: 52 + phoneBob(t)), head: context, time: t, in: &context)
        }

        // Hands on top of everything
        for (index, hand) in [leftHand, rightHand].enumerated() {
            let fist = pose == .grumpy && index == 1
            let radius: CGFloat = fist ? 6.5 : 5
            blob(Path(ellipseIn: CGRect(x: hand.x - radius, y: hand.y - radius, width: radius * 2, height: radius * 2)),
                 color: HeroPalette.red, in: &context)
            if fist {
                // Knuckles.
                var knuckles = Path()
                for dx in [-2.5, 0.5, 3.5] {
                    knuckles.move(to: CGPoint(x: hand.x + dx - 1, y: hand.y - 4))
                    knuckles.addLine(to: CGPoint(x: hand.x + dx - 1, y: hand.y - 1))
                }
                context.stroke(knuckles, with: .color(HeroPalette.outline),
                               style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
            }
        }

        switch pose {
        case .sleeping: drawSnores(time: t, in: &context)
        case .dizzy: drawStars(time: t, front: true, in: &context)
        case .grumpy: drawSteam(time: t, in: &context)
        case .hangingScrolling where isLaughing(t): drawLaugh(time: t, in: &context)
        default: break
        }
    }

    /// One full loop of the dizzy animation (stars go round once, eyes spin twice).
    static let dizzyCycle = 1.6
    /// One full loop of the grumpy animation (steam puffs rise once).
    static let grumpyCycle = 1.2

    /// The mask and eyes. Occupies x -23...23, y 9...53 in hero coordinates.
    static func drawHead(pose: HeroPose, time: Double = 0, in context: inout GraphicsContext) {
        blob(Path(ellipseIn: CGRect(x: -23, y: 9, width: 46, height: 44)), color: HeroPalette.red, in: &context)
        drawEyes(pose: pose, time: time, in: &context)
    }

    private static func drawEyes(pose: HeroPose, time: Double, in context: inout GraphicsContext) {
        for side in [-1.0, 1.0] {
            let center = CGPoint(x: 10 * side, y: 33)
            switch pose {
            case .hanging, .climbing, .sitting, .upsideDown, .peeking, .clinging,
                 .walking, .upsideDownWalking, .spying:
                drawOpenEye(at: center, side: side, in: &context)
            case .waving, .sittingWaving:
                drawHappyEye(at: center, in: &context)
            case .sleeping, .sittingAsleep:
                // Sleepy closed eyes: ∪
                var arc = Path()
                arc.move(to: CGPoint(x: center.x - 6, y: center.y - 1))
                arc.addQuadCurve(to: CGPoint(x: center.x + 6, y: center.y - 1),
                                 control: CGPoint(x: center.x, y: center.y + 5))
                context.stroke(arc, with: .color(HeroPalette.eye),
                               style: StrokeStyle(lineWidth: 3, lineCap: .round))
            case .dizzy:
                drawSpiralEye(at: center, turn: side * time * 2 * .pi / (dizzyCycle / 2), in: &context)
            case .grumpy:
                drawAngryEye(at: center, side: side, in: &context)
            case .sittingWorking:
                drawFocusedEye(at: center, side: side, in: &context)
            case .sittingScrolling, .hangingScrolling:
                if isLaughing(time) {
                    drawHappyEye(at: center, in: &context)
                } else {
                    drawFocusedEye(at: center, side: side, in: &context)
                }
            }
        }
    }

    private static func openEyePath(at center: CGPoint, side: Double) -> Path {
        Path(ellipseIn: CGRect(x: -7.5, y: -5, width: 15, height: 10))
            .applying(CGAffineTransform(rotationAngle: -side * 18 * .pi / 180)
                .concatenating(CGAffineTransform(translationX: center.x, y: center.y)))
    }

    private static func drawOpenEye(at center: CGPoint, side: Double, in context: inout GraphicsContext) {
        let eye = openEyePath(at: center, side: side)
        context.fill(eye, with: .color(HeroPalette.eye))
        context.stroke(eye, with: .color(HeroPalette.outline), lineWidth: 2.2)
    }

    /// Happy closed eyes: ∩
    private static func drawHappyEye(at center: CGPoint, in context: inout GraphicsContext) {
        var arc = Path()
        arc.move(to: CGPoint(x: center.x - 6, y: center.y + 2))
        arc.addQuadCurve(to: CGPoint(x: center.x + 6, y: center.y + 2),
                         control: CGPoint(x: center.x, y: center.y - 7))
        context.stroke(arc, with: .color(HeroPalette.eye),
                       style: StrokeStyle(lineWidth: 3.2, lineCap: .round))
    }

    /// Eyes half closed, looking down at a screen.
    private static func drawFocusedEye(at center: CGPoint, side: Double, in context: inout GraphicsContext) {
        let eye = openEyePath(at: center, side: side)
        context.drawLayer { layer in
            layer.clip(to: Path(CGRect(x: center.x - 10, y: center.y - 0.6, width: 20, height: 10)))
            layer.fill(eye, with: .color(HeroPalette.eye))
            layer.stroke(eye, with: .color(HeroPalette.outline), lineWidth: 2.2)
        }
        var lid = Path()
        lid.move(to: CGPoint(x: center.x - 7.4, y: center.y - 0.6 + side * 1.2))
        lid.addLine(to: CGPoint(x: center.x + 7.4, y: center.y - 0.6 - side * 1.2))
        context.stroke(lid, with: .color(HeroPalette.outline), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
    }

    /// Round white eye with a spinning spiral.
    private static func drawSpiralEye(at center: CGPoint, turn: Double, in context: inout GraphicsContext) {
        let eye = Path(ellipseIn: CGRect(x: center.x - 7, y: center.y - 7, width: 14, height: 14))
        context.fill(eye, with: .color(HeroPalette.eye))
        context.stroke(eye, with: .color(HeroPalette.outline), lineWidth: 2)
        var spiral = Path()
        let turns = 2.6
        let steps = 48
        for step in 0...steps {
            let fraction = Double(step) / Double(steps)
            let angle = fraction * turns * 2 * .pi + turn
            let radius = 0.4 + 5.2 * fraction
            let point = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
            if step == 0 { spiral.move(to: point) } else { spiral.addLine(to: point) }
        }
        context.stroke(spiral, with: .color(HeroPalette.outline),
                       style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
    }

    /// The usual eye with a heavy brow cutting down towards the nose.
    private static func drawAngryEye(at center: CGPoint, side: Double, in context: inout GraphicsContext) {
        let eye = Path(ellipseIn: CGRect(x: -7.5, y: -5, width: 15, height: 10))
            .applying(CGAffineTransform(rotationAngle: -side * 18 * .pi / 180)
                .concatenating(CGAffineTransform(translationX: center.x, y: center.y)))
        context.fill(eye, with: .color(HeroPalette.eye))
        context.stroke(eye, with: .color(HeroPalette.outline), lineWidth: 2.2)

        // Outer end high, inner end (towards the middle of the face) low.
        let outer = CGPoint(x: center.x + 10.5 * side, y: center.y - 7.4)
        let inner = CGPoint(x: center.x - 10.5 * side, y: center.y + 0.3)
        var cover = Path()
        cover.move(to: outer)
        cover.addLine(to: inner)
        cover.addLine(to: CGPoint(x: inner.x, y: center.y - 10))
        cover.addLine(to: CGPoint(x: outer.x, y: center.y - 10))
        cover.closeSubpath()
        context.fill(cover, with: .color(HeroPalette.red))

        var brow = Path()
        brow.move(to: CGPoint(x: center.x + 9 * side, y: center.y - 6.7))
        brow.addLine(to: CGPoint(x: center.x - 8.5 * side, y: center.y - 0.5))
        context.stroke(brow, with: .color(HeroPalette.outline),
                       style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
    }

    /// Three gold stars circling above his head. Drawn in two passes so the ones going
    /// round the back sit behind him.
    private static func drawStars(time t: Double, front: Bool, in context: inout GraphicsContext) {
        for index in 0..<3 {
            let angle = (t / dizzyCycle + Double(index) / 3) * 2 * .pi
            let depth = sin(angle)
            guard (depth >= 0) == front else { continue }
            let center = CGPoint(x: 25 * cos(angle), y: 7 + 6 * depth)
            let radius = 4.2 + 1.2 * depth
            var layer = context
            layer.opacity = 0.75 + 0.25 * depth
            let star = starPath(center: center, radius: radius)
            layer.fill(star, with: .color(HeroPalette.gold))
            layer.stroke(star, with: .color(HeroPalette.outline), lineWidth: 0.9)
        }
    }

    private static func starPath(center: CGPoint, radius: CGFloat) -> Path {
        var path = Path()
        for point in 0..<10 {
            let r = point.isMultiple(of: 2) ? radius : radius * 0.45
            let angle = Double(point) * .pi / 5 - .pi / 2
            let p = CGPoint(x: center.x + r * cos(angle), y: center.y + r * sin(angle))
            if point == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }

    /// Little puffs of steam rising from the left of his head (his fist is on the right).
    private static func drawSteam(time t: Double, in context: inout GraphicsContext) {
        context.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(0.5), radius: 1))
            // Two vents: the side of his head, and higher up near the top.
            for (vent, start, drift) in [(0, CGPoint(x: -21, y: 17), CGVector(dx: -10, dy: -16)),
                                         (1, CGPoint(x: -13, y: 11), CGVector(dx: -6, dy: -18))] {
                for puff in 0..<2 {
                    let phase = (t / grumpyCycle + Double(puff) / 2 + Double(vent) * 0.25)
                        .truncatingRemainder(dividingBy: 1)
                    var cloud = layer
                    cloud.opacity = 0.9 * sin(phase * .pi)
                    let center = CGPoint(x: start.x + drift.dx * phase, y: start.y + drift.dy * phase)
                    let radius = 2.2 + 3.3 * phase
                    var shape = Path()
                    for (dx, dy, scale) in [(0.0, 0.0, 1.0), (-0.8, 0.5, 0.7), (0.8, 0.5, 0.7)] {
                        let r = radius * scale
                        shape.addEllipse(in: CGRect(x: center.x + dx * radius - r, y: center.y + dy * radius - r,
                                                    width: r * 2, height: r * 2))
                    }
                    cloud.fill(shape, with: .color(.white))
                }
            }
        }
    }

    // MARK: - On a desktop widget

    /// Leg swing, look-around, climb, step and spy loops for the widget poses.
    static let walkCycle = 0.6
    static let spyCycle = 2.4
    static let sitCycle = 1.2
    static let peekCycle = 3.0
    static let clingCycle = 1.6

    /// Navy body with belt and badge. Hero coordinates: x -14...14, y 50...82.
    private static func drawTorso(in context: inout GraphicsContext) {
        let torso = Path(roundedRect: CGRect(x: -14, y: 50, width: 28, height: 32), cornerRadius: 10)
        context.fill(torso, with: .color(HeroPalette.navy))
        context.drawLayer { layer in
            layer.clip(to: torso)
            layer.fill(Path(CGRect(x: -15, y: 73, width: 30, height: 4.5)), with: .color(HeroPalette.gold))
        }
        drawBadge(at: CGPoint(x: 0, y: 63), in: &context)
        context.stroke(torso, with: .color(HeroPalette.outline), lineWidth: outlineWidth)
    }

    private static func drawHand(at point: CGPoint, in context: inout GraphicsContext) {
        blob(Path(ellipseIn: CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10)),
             color: HeroPalette.red, in: &context)
    }

    private static func drawLeg(hip: CGPoint, knee: CGPoint, foot: CGPoint, in context: inout GraphicsContext) {
        var leg = Path()
        leg.move(to: hip)
        leg.addLine(to: knee)
        leg.addLine(to: foot)
        limb(leg, color: HeroPalette.navy, width: 10, in: &context)
        blob(Path(ellipseIn: CGRect(x: foot.x - 7, y: foot.y - 3, width: 14, height: 9)),
             color: HeroPalette.red, in: &context)
    }

    /// Seat on the edge at (0, 0): body above, legs swinging over the front of the widget.
    private static func drawSitting(pose: HeroPose, time t: Double, in context: inout GraphicsContext) {
        let asleep = pose == .sittingAsleep
        let working = pose == .sittingWorking
        let scrolling = pose == .sittingScrolling
        let wave = sin(t * 2 * .pi / 0.7)
        // Typing: the hands tap in turn.
        let tap = sin(t * 2 * .pi / typeCycle)
        var leftHand = CGPoint(x: -22, y: -1)
        var rightHand = CGPoint(x: 22, y: -1)
        var leftElbow = CGPoint(x: -27, y: -14)
        var rightElbow = CGPoint(x: 27, y: -14)
        switch pose {
        case .sittingWaving:
            rightHand = CGPoint(x: 31 + 3 * wave, y: -57 - 2 * abs(wave))
            rightElbow = CGPoint(x: 40, y: -26)
        case .sittingWorking:
            leftHand = CGPoint(x: -20, y: -9 - 2.2 * max(0, tap))
            rightHand = CGPoint(x: 20, y: -9 - 2.2 * max(0, -tap))
            leftElbow = CGPoint(x: -27, y: -10)
            rightElbow = CGPoint(x: 27, y: -10)
        case .sittingScrolling:
            rightHand = CGPoint(x: 9, y: -21 + phoneBob(t))
            rightElbow = CGPoint(x: 26, y: -10)
        default:
            break
        }
        if scrolling, isLaughing(t) {
            context.translateBy(x: 0.8 * sin(t * 2 * .pi / 0.3), y: 0)
        }

        // Arms behind the body, hands flat on the edge.
        limb(curve(from: CGPoint(x: -13, y: -24), to: leftHand, control: leftElbow),
             color: HeroPalette.navy, width: 7, in: &context)
        limb(curve(from: CGPoint(x: 13, y: -24), to: rightHand, control: rightElbow),
             color: HeroPalette.navy, width: 7, in: &context)

        // A shorter body: he's sitting.
        let torso = Path(roundedRect: CGRect(x: -14, y: -30, width: 28, height: 30), cornerRadius: 10)
        context.fill(torso, with: .color(HeroPalette.navy))
        context.drawLayer { layer in
            layer.clip(to: torso)
            layer.fill(Path(CGRect(x: -15, y: -9, width: 30, height: 4.5)), with: .color(HeroPalette.gold))
        }
        drawBadge(at: CGPoint(x: 0, y: -19), in: &context)
        context.stroke(torso, with: .color(HeroPalette.outline), lineWidth: outlineWidth)

        // Legs over the edge, swinging one after the other: still while asleep, a gentle
        // jiggle while working, lazy swings on a break.
        let legCycle = scrolling ? 2.4 : sitCycle
        let legSwing = asleep ? 0 : working ? 0.25 : 1
        for (index, side) in [-1.0, 1.0].enumerated() {
            let beat = legSwing * (sin(t * 2 * .pi / legCycle + Double(index) * .pi) + 1) / 2
            drawLeg(hip: CGPoint(x: 7 * side, y: -3),
                    knee: CGPoint(x: 9 * side, y: 5),
                    foot: CGPoint(x: (9 + 1.5 * beat) * side, y: 27 - 7 * beat),
                    in: &context)
        }

        var head = context
        head.translateBy(x: 0, y: -79)
        drawHead(pose: pose, time: t, in: &head)
        if asleep {
            drawSnores(time: t, in: &head)
        }

        if working {
            drawScreenGlow(on: head, center: CGPoint(x: 0, y: 49), in: &head)
            drawLaptop(in: &context)
            drawMug(at: CGPoint(x: 34, y: 0), time: t, in: &context)
        }
        if scrolling {
            drawPhoneInHand(phone: CGPoint(x: 9, y: -31 + phoneBob(t)), head: head, time: t, in: &context)
            if isLaughing(t) {
                drawLaugh(time: t, in: &head)
            }
        }

        drawHand(at: leftHand, in: &context)
        drawHand(at: rightHand, in: &context)
    }

    // MARK: - Laptop, coffee and phone

    /// Typing rhythm, and the loop for scrolling (with a laugh near the end of each).
    static let typeCycle = 0.4
    static let scrollCycle = 4.8

    /// Something funny on his phone, for a moment each loop.
    static func isLaughing(_ t: Double) -> Bool {
        let into = (t / scrollCycle).truncatingRemainder(dividingBy: 1)
        return into >= 0.72 && into < 0.9
    }

    /// The phone drifts a little in his hand.
    private static func phoneBob(_ t: Double) -> Double { 0.6 * sin(t * 2 * .pi / 2.4) }

    /// The back of his laptop on his lap (we see the lid; the screen faces him).
    private static func drawLaptop(in context: inout GraphicsContext) {
        let lid = Path(roundedRect: CGRect(x: -21, y: -33, width: 42, height: 27), cornerRadius: 3.5)
        context.fill(lid, with: .color(Color(white: 0.82)))
        context.stroke(lid, with: .color(HeroPalette.outline), lineWidth: 1.4)
        // A little web on the lid.
        let center = CGPoint(x: 0, y: -19.5)
        var web = Path()
        for radius in [2.6, 5.4] {
            web.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        }
        for spoke in 0..<6 {
            let angle = Double(spoke) * .pi / 3
            web.move(to: center)
            web.addLine(to: CGPoint(x: center.x + 6.4 * cos(angle), y: center.y + 6.4 * sin(angle)))
        }
        context.stroke(web, with: .color(Color(white: 0.55)), lineWidth: 0.8)
        let base = Path(roundedRect: CGRect(x: -23, y: -7, width: 46, height: 4.5), cornerRadius: 1.8)
        context.fill(base, with: .color(Color(white: 0.64)))
        context.stroke(base, with: .color(HeroPalette.outline), lineWidth: 1.2)
    }

    /// A mug on the edge beside him, steam curling up.
    private static func drawMug(at base: CGPoint, time t: Double, in context: inout GraphicsContext) {
        context.drawLayer { steam in
            for puff in 0..<2 {
                let phase = (t / 2.4 + Double(puff) / 2).truncatingRemainder(dividingBy: 1)
                var wisp = Path()
                let x = base.x - 1.5 + 3 * Double(puff)
                let y = base.y - 12 - 7 * phase
                wisp.move(to: CGPoint(x: x, y: y))
                wisp.addCurve(to: CGPoint(x: x, y: y - 8),
                              control1: CGPoint(x: x + 2.5, y: y - 2.5),
                              control2: CGPoint(x: x - 2.5, y: y - 5.5))
                var layer = steam
                layer.opacity = 0.85 * sin(phase * .pi)
                layer.stroke(wisp, with: .color(.white), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
            }
        }
        let handle = Path(ellipseIn: CGRect(x: base.x + 2.2, y: base.y - 8.2, width: 5.6, height: 5.6))
        context.stroke(handle, with: .color(HeroPalette.outline), lineWidth: 2.6)
        context.stroke(handle, with: .color(.white), lineWidth: 1.2)
        let mug = Path(roundedRect: CGRect(x: base.x - 4.5, y: base.y - 10, width: 9, height: 10), cornerRadius: 1.8)
        context.fill(mug, with: .color(.white))
        context.drawLayer { band in
            band.clip(to: mug)
            band.fill(Path(CGRect(x: base.x - 5, y: base.y - 6.5, width: 10, height: 2.2)), with: .color(HeroPalette.red))
        }
        context.stroke(mug, with: .color(HeroPalette.outline), lineWidth: 1.2)
    }

    /// The light from a screen on the lower half of his mask. `head` is the head's coordinates.
    private static func drawScreenGlow(on head: GraphicsContext, center: CGPoint, in context: inout GraphicsContext) {
        context.drawLayer { glow in
            glow.clip(to: Path(ellipseIn: CGRect(x: -23, y: 9, width: 46, height: 44)))
            glow.fill(Path(ellipseIn: CGRect(x: center.x - 17, y: center.y - 8, width: 34, height: 16)),
                      with: .color(Color(red: 0.62, green: 0.86, blue: 1).opacity(0.32)))
        }
    }

    /// His phone (we see its back), the screen's glow on his face, and his thumb flicking up the feed.
    /// `head` is a context in the head's coordinates.
    private static func drawPhoneInHand(phone: CGPoint, head: GraphicsContext, time t: Double,
                                        in context: inout GraphicsContext) {
        var face = head
        // The glow sits on the side the phone is on.
        drawScreenGlow(on: head, center: CGPoint(x: 6, y: 47), in: &face)

        let body = Path(roundedRect: CGRect(x: phone.x - 6.5, y: phone.y - 10.5, width: 13, height: 21), cornerRadius: 3)
        context.fill(body, with: .color(Color(red: 0.17, green: 0.18, blue: 0.24)))
        context.stroke(body, with: .color(HeroPalette.outline), lineWidth: 1.2)
        let bump = Path(roundedRect: CGRect(x: phone.x - 4.6, y: phone.y - 8.6, width: 5.2, height: 5.2), cornerRadius: 1.6)
        context.fill(bump, with: .color(Color(white: 0.36)))
        for (dx, dy) in [(-3.3, -7.3), (-1.1, -5.1)] {
            context.fill(Path(ellipseIn: CGRect(x: phone.x + dx - 0.9, y: phone.y + dy - 0.9, width: 1.8, height: 1.8)),
                         with: .color(.black))
        }
        // Thumb on the screen's edge: a quick flick up, then back down.
        let flick = (t / 0.6).truncatingRemainder(dividingBy: 1)
        let thumbY = flick < 0.35 ? 4 - 9 * (flick / 0.35) : -5 + 9 * ((flick - 0.35) / 0.65)
        blob(Path(ellipseIn: CGRect(x: phone.x + 4.5, y: phone.y + thumbY - 2.5, width: 4.5, height: 5)),
             color: HeroPalette.red, in: &context)
    }

    /// "haha" popping up beside his head. Head coordinates.
    private static func drawLaugh(time t: Double, in context: inout GraphicsContext) {
        let into = ((t / scrollCycle).truncatingRemainder(dividingBy: 1) - 0.72) / 0.18
        context.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(0.6), radius: 1.2))
            layer.opacity = min(1, 3 * sin(into * .pi))
            let text = Text("haha")
                .font(.system(size: 8, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.white)
            layer.translateBy(x: 27, y: 10 - 4 * into)
            layer.rotate(by: .degrees(-14))
            layer.draw(text, at: .zero)
        }
    }

    enum StandingArms {
        case armsCrossed, walking, binoculars
    }

    /// Standing on a widget's edge with his soles at (0, 0): on top of the top edge, or turned
    /// over and stuck under the bottom edge.
    private static func drawStanding(_ arms: StandingArms, upsideDown: Bool, time t: Double,
                                     in context: inout GraphicsContext) {
        var body = context
        // Draw him standing in hero coordinates (boots end at y 110), then put the soles at (0, 0).
        if upsideDown {
            body.rotate(by: .radians(.pi))
        }
        body.translateBy(x: 0, y: -110)

        // Legs: one step after the other while walking.
        let step = sin(t * 2 * .pi / walkCycle)
        for side in [-1.0, 1.0] {
            let lift = arms == .walking ? 5 * max(0, side < 0 ? step : -step) : 0
            drawLeg(hip: CGPoint(x: 7 * side, y: 78),
                    knee: CGPoint(x: (6 + lift * 0.5) * side, y: 91 - lift * 0.5),
                    foot: CGPoint(x: (5 + lift * 0.3) * side, y: 104 - lift),
                    in: &body)
        }
        // A little bob in each step.
        if arms == .walking {
            body.translateBy(x: 0, y: abs(step) * 1.2)
        }
        drawTorso(in: &body)

        let look = arms == .binoculars ? 2.5 * sin(t * 2 * .pi / spyCycle) : 0
        var head = body
        head.translateBy(x: look, y: 0)
        drawHead(pose: upsideDown ? .upsideDown : .walking, in: &head)

        switch arms {
        case .armsCrossed:
            limb(curve(from: CGPoint(x: -13, y: 57), to: CGPoint(x: 9, y: 66), control: CGPoint(x: -18, y: 72)),
                 color: HeroPalette.navy, width: 7, in: &body)
            limb(curve(from: CGPoint(x: 13, y: 57), to: CGPoint(x: -9, y: 66), control: CGPoint(x: 18, y: 72)),
                 color: HeroPalette.navy, width: 7, in: &body)
            drawHand(at: CGPoint(x: 9, y: 66), in: &body)
            drawHand(at: CGPoint(x: -9, y: 66), in: &body)
        case .walking:
            // Arms swing opposite to the legs.
            for side in [-1.0, 1.0] {
                let hand = CGPoint(x: 20 * side, y: 79 + 4 * step * side)
                limb(curve(from: CGPoint(x: 13 * side, y: 57), to: hand, control: CGPoint(x: 22 * side, y: 64)),
                     color: HeroPalette.navy, width: 7, in: &body)
                drawHand(at: hand, in: &body)
            }
        case .binoculars:
            for side in [-1.0, 1.0] {
                let hand = CGPoint(x: 13 * side + look, y: 42)
                limb(curve(from: CGPoint(x: 13 * side, y: 57), to: hand, control: CGPoint(x: 24 * side, y: 54)),
                     color: HeroPalette.navy, width: 7, in: &body)
            }
            drawBinoculars(at: CGPoint(x: look, y: 33), in: &body)
            for side in [-1.0, 1.0] {
                drawHand(at: CGPoint(x: 13 * side + look, y: 42), in: &body)
            }
        }
    }

    /// Two barrels over his eyes, with a glint on each lens.
    private static func drawBinoculars(at center: CGPoint, in context: inout GraphicsContext) {
        let bridge = Path(roundedRect: CGRect(x: center.x - 6, y: center.y - 3, width: 12, height: 6), cornerRadius: 1.5)
        context.fill(bridge, with: .color(HeroPalette.outline))
        for side in [-1.0, 1.0] {
            let lens = CGRect(x: center.x + 10 * side - 8, y: center.y - 8, width: 16, height: 16)
            context.fill(Path(ellipseIn: lens), with: .color(HeroPalette.outline))
            context.stroke(Path(ellipseIn: lens.insetBy(dx: 1.2, dy: 1.2)), with: .color(HeroPalette.gold), lineWidth: 1.4)
            context.fill(Path(ellipseIn: lens.insetBy(dx: 3, dy: 3)), with: .color(Color(red: 0.35, green: 0.55, blue: 0.85)))
            context.fill(Path(ellipseIn: CGRect(x: lens.minX + 4.5, y: lens.minY + 4, width: 3.2, height: 3.2)),
                         with: .color(.white.opacity(0.9)))
        }
    }

    /// Hands on the top edge at (0, 0), only the top of his head showing above it.
    private static func drawPeeking(time t: Double, in context: inout GraphicsContext) {
        let look = 5 * sin(t * 2 * .pi / peekCycle)
        let bob = 1.2 * sin(t * 2 * .pi / (peekCycle / 2))
        context.drawLayer { above in
            // The rest of him is behind the widget.
            above.clip(to: Path(CGRect(x: -60, y: -80, width: 120, height: 80)))
            above.translateBy(x: look, y: -42 + bob)
            drawHead(pose: .peeking, in: &above)
        }
        // Fingers curled over the edge.
        for side in [-1.0, 1.0] {
            let hand = CGPoint(x: 17 * side, y: 0)
            blob(Path(ellipseIn: CGRect(x: hand.x - 5.5, y: hand.y - 4.5, width: 11, height: 9)),
                 color: HeroPalette.red, in: &context)
            var fingers = Path()
            for dx in [-2.5, 0.0, 2.5] {
                fingers.move(to: CGPoint(x: hand.x + dx, y: hand.y + 0.5))
                fingers.addLine(to: CGPoint(x: hand.x + dx, y: hand.y + 3.5))
            }
            context.stroke(fingers, with: .color(HeroPalette.outline),
                           style: StrokeStyle(lineWidth: 1, lineCap: .round))
        }
    }

    /// The widget's right edge runs through (0, 0) with the widget to the left; he hangs on
    /// beside it with both hands and one foot against it.
    private static func drawClinging(time t: Double, in context: inout GraphicsContext) {
        let climb = 3 * sin(t * 2 * .pi / clingCycle)
        let sway = 1.5 * sin(t * 2 * .pi / clingCycle + 1)
        var body = context
        // Hero coordinates, moved beside the edge: the edge is at x -26 here.
        body.translateBy(x: 26, y: -66)
        let upperHand = CGPoint(x: -27, y: 26 - climb)
        let lowerHand = CGPoint(x: -27, y: 70 + climb)

        // Foot braced on the edge, the other leg hanging.
        drawLeg(hip: CGPoint(x: -7, y: 78), knee: CGPoint(x: -15, y: 86), foot: CGPoint(x: -23, y: 98), in: &body)
        drawLeg(hip: CGPoint(x: 7, y: 78), knee: CGPoint(x: 8, y: 91), foot: CGPoint(x: 9 + sway, y: 104), in: &body)

        // Upper arm reaches past his head to the edge.
        limb(curve(from: CGPoint(x: -13, y: 57), to: upperHand, control: CGPoint(x: -31, y: 50)),
             color: HeroPalette.navy, width: 7, in: &body)
        drawTorso(in: &body)
        drawHead(pose: .clinging, in: &body)
        // Lower arm crosses in front of him.
        limb(curve(from: CGPoint(x: 13, y: 57), to: lowerHand, control: CGPoint(x: 2, y: 82)),
             color: HeroPalette.navy, width: 7, in: &body)
        drawHand(at: upperHand, in: &body)
        drawHand(at: lowerHand, in: &body)
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
