import CoreGraphics
import Testing
@testable import vibe_hud

@Suite("Notch layout metrics")
struct NotchLayoutMetricsTests {
    @Test("Opened window includes content and both outer shoulders")
    func openedWindowIncludesShoulders() {
        let outerWidth: CGFloat = 384

        #expect(NotchLayoutMetrics.openedContentWidth(for: outerWidth) == 360)
        #expect(NotchLayoutMetrics.renderedWidth(for: outerWidth) == 422)
        #expect(NotchLayoutMetrics.openedShapePadding == 19)
    }

    @Test("Very narrow window never produces a negative content width")
    func narrowWindowIsClamped() {
        #expect(NotchLayoutMetrics.openedContentWidth(for: 12) == 0)
    }
}
