import CoreGraphics
import Testing
@testable import vibe_hud

@Suite("Notch shadow geometry")
struct NotchShadowMetricsTests {
    @Test("Shadow canvas expands sideways and downward without moving the top edge")
    func expandsAroundPanel() {
        let panel = CGRect(x: 100, y: 500, width: 422, height: 220)
        let shadow = NotchShadowMetrics.windowFrame(around: panel)

        #expect(shadow.minX == 86)
        #expect(shadow.minY == 482)
        #expect(shadow.width == 450)
        #expect(shadow.height == 238)
        #expect(shadow.maxY == panel.maxY)
    }
}
