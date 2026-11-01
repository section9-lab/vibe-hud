import CoreGraphics
import Testing
@testable import vibe_hud

@Suite("Notch geometry")
struct NotchGeometryTests {
    private let geometry = NotchGeometry(
        deviceNotchRect: CGRect(x: 0, y: 0, width: 200, height: 32),
        screenRect: CGRect(x: 0, y: 0, width: 1_200, height: 800),
        windowHeight: 760
    )

    @Test("Centers the physical notch on screen")
    func centersPhysicalNotch() {
        #expect(geometry.notchScreenRect == CGRect(x: 500, y: 768, width: 200, height: 32))
    }

    @Test("Opened panel hit testing uses rendered bounds")
    func openedPanelHitTesting() {
        let size = CGSize(width: 384, height: 420)
        let rect = geometry.openedScreenRect(for: size)

        #expect(geometry.isPointInOpenedPanel(CGPoint(x: rect.midX, y: rect.midY), size: size))
        #expect(geometry.isPointOutsidePanel(CGPoint(x: 0, y: 0), size: size))
    }

    @Test("Interactive window is limited to the visible HUD at the top center")
    func interactionWindowDoesNotCoverOtherApps() {
        let size = CGSize(width: 384, height: 420)
        let frame = geometry.interactionWindowFrame(for: size)

        #expect(frame == CGRect(x: 408, y: 380, width: 384, height: 420))
        #expect(!frame.contains(CGPoint(x: 100, y: 700)))
        #expect(!frame.contains(CGPoint(x: 600, y: 100)))
    }

    @Test("Opened hit region includes the settings button at the right edge")
    func openedHitRegionUsesResizedWindowCoordinates() {
        let bounds = CGRect(x: 0, y: 0, width: 384, height: 420)
        let hitRegion = NotchHitTesting.rect(
            status: .opened,
            windowBounds: bounds,
            notchSize: CGSize(width: 200, height: 32)
        )

        #expect(hitRegion == bounds)
        #expect(hitRegion.contains(CGPoint(x: 373, y: 409)))
    }

    @Test("Closed hit region remains centered in the passive window")
    func closedHitRegionUsesLocalWindowCoordinates() {
        let hitRegion = NotchHitTesting.rect(
            status: .closed,
            windowBounds: CGRect(x: 0, y: 0, width: 1_200, height: 750),
            notchSize: CGSize(width: 200, height: 32)
        )

        #expect(hitRegion == CGRect(x: 490, y: 713, width: 220, height: 42))
    }

    @Test("Notch hit target includes interaction padding")
    func notchHitTargetHasPadding() {
        #expect(geometry.isPointInNotch(CGPoint(x: 495, y: 766)))
        #expect(!geometry.isPointInNotch(CGPoint(x: 450, y: 700)))
    }

    @Test("Closed activity keeps its right edge on the physical notch")
    func closedActivityKeepsPhysicalRightEdge() {
        let renderedWidth: CGFloat = 238
        let renderedRightEdge = geometry.screenRect.midX + renderedWidth / 2
            + geometry.closedContentOffset(forRenderedWidth: renderedWidth)

        #expect(renderedRightEdge == geometry.notchScreenRect.maxX)
    }
}
