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

    @Test("Notch hit target includes interaction padding")
    func notchHitTargetHasPadding() {
        #expect(geometry.isPointInNotch(CGPoint(x: 495, y: 766)))
        #expect(!geometry.isPointInNotch(CGPoint(x: 450, y: 700)))
    }
}
