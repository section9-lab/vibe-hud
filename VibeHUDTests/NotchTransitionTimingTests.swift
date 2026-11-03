import CoreGraphics
import Testing
@testable import vibe_hud

@Suite("Notch content transitions")
struct NotchTransitionTimingTests {
    @Test("Temporary canvas contains both the old and new panel")
    func canvasContainsBothSizes() {
        #expect(NotchTransitionTiming.contentCanvasSize(
            current: CGSize(width: 422, height: 220),
            target: CGSize(width: 422, height: 480)
        ) == CGSize(width: 422, height: 480))

        #expect(NotchTransitionTiming.contentCanvasSize(
            current: CGSize(width: 518, height: 580),
            target: CGSize(width: 422, height: 220)
        ) == CGSize(width: 518, height: 580))
    }

    @Test("Content transition stays short")
    func transitionDuration() {
        #expect(NotchTransitionTiming.contentDuration == 0.24)
    }
}
