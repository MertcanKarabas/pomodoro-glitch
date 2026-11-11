import CoreGraphics
import Foundation
import Testing
@testable import SpiderCore

@Suite("Perch")
struct PerchTests {
    // A large widget and a small one beside it.
    let large = CGRect(x: 100, y: 300, width: 350, height: 350)
    let small = CGRect(x: 460, y: 480, width: 170, height: 170)

    @Test func findsTheWidgetUnderTheDrop() {
        #expect(PerchGeometry.widget(at: CGPoint(x: 200, y: 400), among: [large, small]) == large)
        #expect(PerchGeometry.widget(at: CGPoint(x: 500, y: 600), among: [large, small]) == small)
    }

    @Test func aDropJustOutsideStillCounts() {
        #expect(PerchGeometry.widget(at: CGPoint(x: 200, y: 670), among: [large]) == large)
        #expect(PerchGeometry.widget(at: CGPoint(x: 200, y: 700), among: [large]) == nil)
    }

    @Test func betweenTwoWidgetsPicksTheNearest() {
        // 4 pt right of the large widget, 6 pt left of the small one.
        #expect(PerchGeometry.widget(at: CGPoint(x: 454, y: 600), among: [large, small]) == large)
        #expect(PerchGeometry.widget(at: CGPoint(x: 457, y: 600), among: [large, small]) == small)
    }

    @Test func whereHeIsDroppedPicksTheSpot() {
        func spot(_ x: CGFloat, _ y: CGFloat) -> PerchSpot { PerchGeometry.perch(droppedAt: CGPoint(x: x, y: y), on: large).spot }
        #expect(spot(275, 640) == .top)
        #expect(spot(275, 660) == .top)      // a little above the widget
        #expect(spot(275, 310) == .bottom)
        #expect(spot(110, 475) == .left)
        #expect(spot(440, 475) == .right)
        #expect(spot(275, 475) == .face)
        #expect(spot(110, 640) == .top)      // corners go to the top or bottom
    }

    @Test func theSurfaceIsKept() {
        let card = CGRect(x: 600, y: 500, width: 250, height: 196)
        let perch = PerchGeometry.perch(droppedAt: CGPoint(x: 700, y: 690), on: card, surface: .timerCard)
        #expect(perch.surface == .timerCard)
        #expect(perch.spot == .top)
        #expect(PerchGeometry.perch(droppedAt: CGPoint(x: 700, y: 690), on: card).surface == .desktopWidget)
    }

    @Test func alongFollowsTheDropPoint() {
        let top = PerchGeometry.perch(droppedAt: CGPoint(x: 100 + 350 * 0.25, y: 640), on: large)
        #expect(abs(top.along - 0.25) < 0.0001)
        let side = PerchGeometry.perch(droppedAt: CGPoint(x: 445, y: 300 + 350 * 0.75), on: large)
        #expect(side.spot == .right)
        #expect(abs(side.along - 0.75) < 0.0001)
    }

    @Test func contactSitsOnTheRightEdge() {
        let top = Perch(spot: .top, widget: large, along: 0.5)
        #expect(PerchGeometry.contact(for: top, edgeMargin: 30, sideMargin: 40) == CGPoint(x: 275, y: 650))
        let bottom = Perch(spot: .bottom, widget: large, along: 0.5)
        #expect(PerchGeometry.contact(for: bottom, edgeMargin: 30, sideMargin: 40) == CGPoint(x: 275, y: 300))
        let left = Perch(spot: .left, widget: large, along: 0.5)
        #expect(PerchGeometry.contact(for: left, edgeMargin: 30, sideMargin: 40) == CGPoint(x: 100, y: 475))
        let right = Perch(spot: .right, widget: large, along: 0.5)
        #expect(PerchGeometry.contact(for: right, edgeMargin: 30, sideMargin: 40) == CGPoint(x: 450, y: 475))
    }

    @Test func contactStaysAwayFromCorners() {
        let corner = Perch(spot: .top, widget: large, along: 0)
        #expect(PerchGeometry.contact(for: corner, edgeMargin: 30, sideMargin: 40).x == 130)
        let low = Perch(spot: .left, widget: large, along: 0)
        #expect(PerchGeometry.contact(for: low, edgeMargin: 30, sideMargin: 40).y == 340)
        // Narrower than both margins: the middle.
        let tiny = Perch(spot: .top, widget: CGRect(x: 0, y: 0, width: 40, height: 40), along: 1)
        #expect(PerchGeometry.contact(for: tiny, edgeMargin: 30, sideMargin: 40).x == 20)
    }

    @Test func findsHisWidgetAgainAfterItMoves() {
        let moved = large.offsetBy(dx: 30, dy: -20)
        #expect(PerchGeometry.sameWidget(as: large, among: [small, moved]) == moved)
        // Two widgets of that size: only a nearby one is his.
        let other = CGRect(x: 900, y: 100, width: 350, height: 350)
        #expect(PerchGeometry.sameWidget(as: large, among: [other, moved]) == moved)
        let farMoved = large.offsetBy(dx: 400, dy: 0)
        #expect(PerchGeometry.sameWidget(as: large, among: [other, farMoved]) == nil)
        #expect(PerchGeometry.sameWidget(as: large, among: [small]) == nil)
    }

    @Test func coveredByAWindow() {
        let window = CGRect(x: 0, y: 0, width: 300, height: 500)
        #expect(PerchGeometry.isCovered(CGPoint(x: 200, y: 400), by: [window]))
        #expect(!PerchGeometry.isCovered(CGPoint(x: 400, y: 400), by: [window]))
    }

    @Test func windowListBoundsFlipToScreenCoordinates() {
        // 360×360 at 8, 42 from the top-left of a 1107 pt tall main display.
        let rect = PerchGeometry.screenRect(fromWindowBounds: CGRect(x: 8, y: 42, width: 360, height: 360),
                                            mainDisplayHeight: 1107)
        #expect(rect == CGRect(x: 8, y: 705, width: 360, height: 360))
    }

    @Test func posesFollowTheSpotAndTheTimer() {
        #expect(PerchSpot.top.pose(task: .paused, reaction: nil) == .sitting)
        #expect(PerchSpot.top.pose(task: .asleep, reaction: nil) == .sittingAsleep)
        #expect(PerchSpot.top.pose(task: .cheering, reaction: nil) == .sittingWaving)
        #expect(PerchSpot.top.pose(task: .asleep, reaction: .hello) == .sittingWaving)
        #expect(PerchSpot.top.pose(task: .working, reaction: nil) == .sittingWorking)
        #expect(PerchSpot.top.pose(task: .onBreak, reaction: nil) == .sittingScrolling)
        #expect(PerchSpot.bottom.pose(task: .onBreak, reaction: nil) == .upsideDown)
        #expect(PerchSpot.face.pose(task: .working, reaction: nil) == .peeking)
        #expect(PerchSpot.left.pose(task: .working, reaction: nil) == .clinging)
        #expect(PerchSpot.right.pose(task: .working, reaction: nil) == .clinging)
        #expect(PerchSpot.left.isMirrored && !PerchSpot.right.isMirrored)
    }

    @Test func perchSurvivesSaving() throws {
        let perch = Perch(spot: .right, surface: .timerCard, widget: large, along: 0.3)
        let data = try JSONEncoder().encode(perch)
        #expect(try JSONDecoder().decode(Perch.self, from: data) == perch)
    }
}
