import CoreGraphics

/// Keeps the opened HUD's rendered shape inside the same bounds used by its
/// native interaction window. Adding the corner radius outside these bounds
/// clips the two top outer corners when the NSPanel is narrowed after opening.
enum NotchLayoutMetrics {
    static let openedContentPadding: CGFloat = 12
    static let openedShapePadding: CGFloat = 0

    nonisolated static func openedContentWidth(for outerWidth: CGFloat) -> CGFloat {
        max(0, outerWidth - 2 * openedContentPadding)
    }

    nonisolated static func renderedWidth(for outerWidth: CGFloat) -> CGFloat {
        openedContentWidth(for: outerWidth)
            + 2 * openedContentPadding
            + 2 * openedShapePadding
    }
}
