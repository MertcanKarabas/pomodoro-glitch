import SwiftUI

/// The hero hanging from the top center of this view on a web line, for app screens.
///
/// Pose and drop come from the timer. The pose animates as a 4-frames-a-second flip-book;
/// swinging and dropping are SwiftUI animations, so the hero itself is redrawn rarely.
public struct HangingHeroStage: View {
    public var state: TimerState
    public var lastFinished: FinishedPhase?
    /// Web length when all the way up.
    public var shortestWeb: CGFloat
    /// How much longer the web gets at the bottom.
    public var dropDistance: CGFloat
    public var scale: CGFloat

    @State private var swingOut = false

    public init(
        state: TimerState,
        lastFinished: FinishedPhase?,
        shortestWeb: CGFloat = 16,
        dropDistance: CGFloat,
        scale: CGFloat = 1
    ) {
        self.state = state
        self.lastFinished = lastFinished
        self.shortestWeb = shortestWeb
        self.dropDistance = dropDistance
        self.scale = scale
    }

    public var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { timeline in
            let placement = HeroPlacement(state: state, now: timeline.date, lastFinished: lastFinished)
            let webLength = shortestWeb + placement.drop * dropDistance
            let gripY = HeroFigure.grip.y * scale

            ZStack(alignment: .top) {
                Rectangle()
                    .fill(.white.opacity(0.95))
                    .frame(width: 1.4, height: webLength)
                    .overlay(Rectangle().stroke(.black.opacity(0.3), lineWidth: 0.8))
                HeroFigure(pose: placement.pose, time: timeline.date.timeIntervalSinceReferenceDate, scale: scale)
                    .offset(y: webLength - gripY)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .rotationEffect(.degrees(placement.swings ? (swingOut ? 3 : -3) : 0), anchor: .top)
            .animation(.easeInOut(duration: 1.7).repeatForever(autoreverses: true), value: swingOut)
            .animation(.linear(duration: 0.3), value: webLength)
        }
        .onAppear { swingOut = true }
        .accessibilityHidden(true)
    }
}
