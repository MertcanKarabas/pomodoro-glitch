import CoreGraphics
import Testing
@testable import SpiderCore

@Suite("HeroGeometry")
struct HeroGeometryTests {
    // A 1440×900 screen with a 25 pt menu bar.
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)

    @Test func anchorInsideStaysPut() {
        let anchor = CGPoint(x: 700, y: 800)
        #expect(HeroGeometry.clampedAnchor(anchor, in: screen, hangHeight: 344, halfWidth: 40) == anchor)
    }

    @Test func anchorTooLowIsRaisedSoTheFullDropFits() {
        let result = HeroGeometry.clampedAnchor(CGPoint(x: 700, y: 100), in: screen, hangHeight: 344, halfWidth: 40)
        #expect(result == CGPoint(x: 700, y: 344))
    }

    @Test func anchorOffTheSidesOrTopIsPulledBack() {
        #expect(HeroGeometry.clampedAnchor(CGPoint(x: -50, y: 2000), in: screen, hangHeight: 344, halfWidth: 40)
                == CGPoint(x: 40, y: 875))
        #expect(HeroGeometry.clampedAnchor(CGPoint(x: 1500, y: 600), in: screen, hangHeight: 344, halfWidth: 40)
                == CGPoint(x: 1400, y: 600))
    }

    @Test func screenShorterThanTheDropKeepsTheAnchorAtTheTop() {
        let short = CGRect(x: 0, y: 0, width: 800, height: 300)
        #expect(HeroGeometry.clampedAnchor(CGPoint(x: 400, y: 100), in: short, hangHeight: 344, halfWidth: 40).y == 300)
    }

    @Test func cardGoesRightOfTheHero() {
        let hero = CGRect(x: 600, y: 400, width: 60, height: 90)
        let origin = HeroGeometry.cardOrigin(beside: hero, cardSize: CGSize(width: 240, height: 180), in: screen)
        #expect(origin == CGPoint(x: 672, y: 355))
    }

    @Test func cardFlipsLeftNearTheRightEdge() {
        let hero = CGRect(x: 1300, y: 400, width: 60, height: 90)
        let origin = HeroGeometry.cardOrigin(beside: hero, cardSize: CGSize(width: 240, height: 180), in: screen)
        #expect(origin.x == CGFloat(1300 - 12 - 240))
    }

    @Test func cardStaysOnScreenVertically() {
        let hero = CGRect(x: 600, y: 820, width: 60, height: 90)
        let origin = HeroGeometry.cardOrigin(beside: hero, cardSize: CGSize(width: 240, height: 180), in: screen)
        #expect(origin.y == CGFloat(875 - 180))
    }

    @Test func windowIsKeptBetweenTheMenuBarAndTheDock() {
        // Visible area above an 80 pt Dock.
        let visible = CGRect(x: 0, y: 80, width: 1440, height: 795)
        let size = CGSize(width: 250, height: 200)
        #expect(HeroGeometry.keptInside(CGPoint(x: 1300, y: 20), size: size, visibleFrame: visible)
                == CGPoint(x: 1190, y: 80))
        #expect(HeroGeometry.keptInside(CGPoint(x: -40, y: 800), size: size, visibleFrame: visible)
                == CGPoint(x: 0, y: 675))
        #expect(HeroGeometry.keptInside(CGPoint(x: 600, y: 300), size: size, visibleFrame: visible)
                == CGPoint(x: 600, y: 300))
    }
}
