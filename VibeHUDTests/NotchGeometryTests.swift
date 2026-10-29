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

    @Test("Closed activity keeps its right edge on the physical notch")
    func closedActivityKeepsPhysicalRightEdge() {
        let renderedWidth: CGFloat = 238
        let renderedRightEdge = geometry.screenRect.midX + renderedWidth / 2
            + geometry.closedContentOffset(forRenderedWidth: renderedWidth)

        #expect(renderedRightEdge == geometry.notchScreenRect.maxX)
    }

    @Test("Closed accessories sit beside the physical notch and stay hittable")
    func closedAccessoriesStayBesidePhysicalNotch() {
        let left: CGFloat = 38
        let right: CGFloat = 92
        let renderedWidth = geometry.deviceNotchRect.width + left + right
        let offset = geometry.closedContentOffset(forRenderedWidth: renderedWidth,
                                                   trailingExtension: right)
        let renderedLeft = geometry.screenRect.midX - renderedWidth / 2 + offset
        #expect(renderedLeft + left == geometry.notchScreenRect.minX)
        #expect(geometry.isPointInClosedContent(
            CGPoint(x: geometry.notchScreenRect.maxX + 45, y: geometry.notchScreenRect.midY),
            leadingExtension: left, trailingExtension: right))
        #expect(!geometry.isPointInClosedContent(
            CGPoint(x: geometry.notchScreenRect.maxX + right + 10,
                    y: geometry.notchScreenRect.midY),
            leadingExtension: left, trailingExtension: right))
    }

    @Test("Native top-right area limits monitoring width")
    func nativeSafeAreaLimitsAccessoryWidth() {
        let narrow = NotchGeometry(deviceNotchRect: geometry.deviceNotchRect,
                                   screenRect: geometry.screenRect,
                                   windowHeight: geometry.windowHeight,
                                   topRightAreaWidth: 90)
        #expect(narrow.maximumTrailingAccessoryWidth == 28)
        #expect(geometry.maximumTrailingAccessoryWidth > narrow.maximumTrailingAccessoryWidth)
    }

    @Test("Idle notch has no left extension and one Codex ring adds exactly 34 pt on the right")
    func idleCodexRingPlacement() {
        let physical = geometry.closedContentScreenRect(leadingExtension: 0, trailingExtension: 0)
        let codex = geometry.closedContentScreenRect(leadingExtension: 0, trailingExtension: 34)
        let offset = geometry.closedContentOffset(forRenderedWidth: 234, trailingExtension: 34)
        let renderedLeft = geometry.screenRect.midX - 117 + offset
        #expect(physical == geometry.notchScreenRect)
        #expect(codex.minX == physical.minX)
        #expect(codex.maxX == physical.maxX + 34)
        #expect(renderedLeft == physical.minX)
    }

    @Test("Codex and nested Claude rings sit outside the camera housing and remain hittable")
    func providerRingsOutsideCamera() {
        let rect = geometry.closedContentScreenRect(leadingExtension: 0, trailingExtension: 64)
        let firstRingX = geometry.notchScreenRect.maxX + NotchGeometry.accessoryInset + 15
        let secondRingX = firstRingX + 30
        #expect(rect.minX == geometry.notchScreenRect.minX)
        #expect(firstRingX > geometry.notchScreenRect.maxX)
        #expect(secondRingX < rect.maxX)
        for x in [firstRingX, secondRingX] {
            #expect(geometry.isPointInClosedContent(
                CGPoint(x: x, y: geometry.notchScreenRect.midY),
                leadingExtension: 0, trailingExtension: 64))
        }
    }

    @Test("Hidden monitoring contracts back to the physical notch")
    func hiddenMonitoringContracts() {
        let rect = geometry.closedContentScreenRect(leadingExtension: 0, trailingExtension: 0)
        #expect(rect == geometry.notchScreenRect)
        #expect(!geometry.isPointInClosedContent(
            CGPoint(x: rect.maxX + 12, y: rect.midY),
            leadingExtension: 0, trailingExtension: 0))
    }
}
