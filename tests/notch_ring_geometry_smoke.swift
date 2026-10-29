import CoreGraphics
import Foundation

@main
struct NotchRingGeometrySmoke {
    static func main() {
        let geometry = NotchGeometry(
            deviceNotchRect: CGRect(x: 0, y: 0, width: 200, height: 32),
            screenRect: CGRect(x: 0, y: 0, width: 1_200, height: 800),
            windowHeight: 760
        )
        let notch = geometry.notchScreenRect

        // All five display items hidden: no spare width or phantom hit target.
        let hidden = geometry.closedContentScreenRect(leadingExtension: 0, trailingExtension: 0)
        precondition(hidden == notch)
        precondition(!geometry.isPointInClosedContent(
            CGPoint(x: notch.maxX + 12, y: notch.midY),
            leadingExtension: 0, trailingExtension: 0))

        // Codex only: 4 pt clearance plus a 30 pt cell, wholly outside the camera.
        let codex = geometry.closedContentScreenRect(leadingExtension: 0, trailingExtension: 34)
        let codexOffset = geometry.closedContentOffset(forRenderedWidth: 234,
                                                        trailingExtension: 34)
        precondition(codex.minX == notch.minX && codex.maxX == notch.maxX + 34)
        precondition(geometry.screenRect.midX - 117 + codexOffset == notch.minX)
        precondition(geometry.isPointInClosedContent(
            CGPoint(x: notch.maxX + 19, y: notch.midY),
            leadingExtension: 0, trailingExtension: 34))

        // Codex and Claude occupy two 30 pt cells. Each center clears the camera.
        let both = geometry.closedContentScreenRect(leadingExtension: 0, trailingExtension: 64)
        precondition(both.minX == notch.minX && both.maxX == notch.maxX + 64)
        for center in [CGFloat(19), 49] {
            let point = CGPoint(x: notch.maxX + center, y: notch.midY)
            precondition(point.x > notch.maxX)
            precondition(geometry.isPointInClosedContent(
                point, leadingExtension: 0, trailingExtension: 64))
        }

        // A busy session still uses its existing left cue without shifting rings.
        let busy = geometry.closedContentScreenRect(leadingExtension: 38, trailingExtension: 34)
        let busyOffset = geometry.closedContentOffset(forRenderedWidth: 272,
                                                       trailingExtension: 34)
        precondition(busy.minX == notch.minX - 38 && busy.maxX == codex.maxX)
        precondition(geometry.screenRect.midX - 136 + busyOffset == busy.minX)
        print("notch ring geometry: hidden, Codex, nested pair, busy all passed")
    }
}
