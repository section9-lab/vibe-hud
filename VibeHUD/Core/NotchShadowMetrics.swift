import CoreGraphics

/// Extra non-interactive canvas used only for the shape-following shadow.
enum NotchShadowMetrics {
    static let horizontalMargin: CGFloat = 14
    static let bottomMargin: CGFloat = 18

    nonisolated static func windowFrame(around panelFrame: CGRect) -> CGRect {
        CGRect(
            x: panelFrame.minX - horizontalMargin,
            y: panelFrame.minY - bottomMargin,
            width: panelFrame.width + 2 * horizontalMargin,
            height: panelFrame.height + bottomMargin
        )
    }
}
