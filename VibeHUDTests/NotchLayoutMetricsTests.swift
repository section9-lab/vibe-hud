import CoreGraphics
import Testing
@testable import vibe_hud

@Suite("Notch layout metrics")
struct NotchLayoutMetricsTests {
    @Test("Opened shape fits its native interaction window")
    func openedShapeFitsWindow() {
        let outerWidth: CGFloat = 384

        #expect(NotchLayoutMetrics.openedContentWidth(for: outerWidth) == 360)
        #expect(NotchLayoutMetrics.renderedWidth(for: outerWidth) == outerWidth)
        #expect(NotchLayoutMetrics.openedShapePadding == 0)
    }

    @Test("Very narrow window never produces a negative content width")
    func narrowWindowIsClamped() {
        #expect(NotchLayoutMetrics.openedContentWidth(for: 12) == 0)
    }
}
