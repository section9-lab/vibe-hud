import CoreGraphics

/// Separates the opened HUD's content width from the full rendered shape.
/// The native panel includes the top shoulder padding so controls keep their
/// intended width and the outer corners are not clipped.
enum NotchLayoutMetrics {
    static let openedContentPadding: CGFloat = 12
    static let openedShapePadding: CGFloat = 19

    nonisolated static func openedContentWidth(for outerWidth: CGFloat) -> CGFloat {
        max(0, outerWidth - 2 * openedContentPadding)
    }

    nonisolated static func renderedWidth(for outerWidth: CGFloat) -> CGFloat {
        openedContentWidth(for: outerWidth)
            + 2 * openedContentPadding
            + 2 * openedShapePadding
    }
}
