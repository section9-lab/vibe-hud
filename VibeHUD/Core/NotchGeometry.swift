//
//  NotchGeometry.swift
//  VibeHUD
//
//  Geometry calculations for the notch
//

import CoreGraphics
import Foundation

/// Pure geometry calculations for the notch
struct NotchGeometry: Sendable {
    /// The first ring starts clear of the camera housing, inside the black extension.
    static let accessoryInset: CGFloat = 4
    let deviceNotchRect: CGRect
    let screenRect: CGRect
    let windowHeight: CGFloat
    /// The macOS safe area to the right of the camera housing. It includes menu bar items.
    var topRightAreaWidth: CGFloat? = nil

    /// The notch rect in screen coordinates (for hit testing with global mouse position)
    var notchScreenRect: CGRect {
        CGRect(
            x: screenRect.midX - deviceNotchRect.width / 2,
            y: screenRect.maxY - deviceNotchRect.height,
            width: deviceNotchRect.width,
            height: deviceNotchRect.height
        )
    }

    /// The opened panel rect in screen coordinates for a given size
    func openedScreenRect(for size: CGSize) -> CGRect {
        // Match the actual rendered panel size (tuned to match visual output)
        let width = size.width - 6
        let height = size.height - 30
        return CGRect(
            x: screenRect.midX - width / 2,
            y: screenRect.maxY - height,
            width: width,
            height: height
        )
    }

    /// Check if a point is in the notch area (with padding for easier interaction)
    func isPointInNotch(_ point: CGPoint) -> Bool {
        notchScreenRect.insetBy(dx: -10, dy: -5).contains(point)
    }

    /// Reserve most of the native top-right area for the menu bar. On a display
    /// without a camera housing, use the same conservative fraction of its side.
    var maximumTrailingAccessoryWidth: CGFloat {
        let side = max(0, (screenRect.width - deviceNotchRect.width) / 2)
        let nativeArea = min(side, topRightAreaWidth ?? side)
        return min(220, max(0, floor(nativeArea * 0.32)))
    }

    func closedContentScreenRect(leadingExtension: CGFloat, trailingExtension: CGFloat) -> CGRect {
        let notch = notchScreenRect
        return CGRect(x: notch.minX - max(0, leadingExtension), y: notch.minY,
                      width: notch.width + max(0, leadingExtension) + max(0, trailingExtension),
                      height: notch.height)
    }

    func isPointInClosedContent(_ point: CGPoint, leadingExtension: CGFloat,
                                trailingExtension: CGFloat) -> Bool {
        closedContentScreenRect(leadingExtension: leadingExtension,
                                trailingExtension: trailingExtension)
            .insetBy(dx: -3, dy: -5).contains(point)
    }

    /// Check if a point is in the opened panel area
    func isPointInOpenedPanel(_ point: CGPoint, size: CGSize) -> Bool {
        openedScreenRect(for: size).contains(point)
    }

    /// Check if a point is outside the opened panel (for closing)
    func isPointOutsidePanel(_ point: CGPoint, size: CGSize) -> Bool {
        !openedScreenRect(for: size).contains(point)
    }

    /// Offset wider closed content so its right edge stays on the physical notch.
    func closedContentOffset(forRenderedWidth width: CGFloat) -> CGFloat {
        (deviceNotchRect.width - width) / 2
    }

    /// Keeps the physical notch centered when the capsule extends on both sides.
    func closedContentOffset(forRenderedWidth width: CGFloat,
                             trailingExtension: CGFloat) -> CGFloat {
        closedContentOffset(forRenderedWidth: width) + trailingExtension
    }
}
