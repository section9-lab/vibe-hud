//
//  NotchHeaderView.swift
//  VibeHUD
//
//  Compact icons used in the notch header and session list.
//

import AppKit
import SwiftUI

enum AgentBrandIconStyle {
    case colored
    case monochrome
}

struct SessionSourceIcon: View {
    let source: SessionSource
    let size: CGFloat

    init(source: SessionSource, size: CGFloat = 16) {
        self.source = source
        self.size = size
    }

    var body: some View {
        AgentBrandIcon(source: source, style: .colored, size: size)
    }
}

struct AgentBrandIcon: View {
    let source: SessionSource
    let style: AgentBrandIconStyle
    let size: CGFloat

    var body: some View {
        Group {
            if let assetName = source.brandAssetName {
                Image(assetName)
                    .resizable()
                    .renderingMode(renderingMode)
            } else if let applicationIcon {
                Image(nsImage: applicationIcon)
                    .resizable()
                    .renderingMode(renderingMode)
            } else {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .resizable()
                    .renderingMode(.template)
            }
        }
        .aspectRatio(contentMode: .fit)
        .foregroundStyle(style == .monochrome ? Color.white.opacity(0.72) : .white)
        .frame(width: size, height: size)
        .accessibilityLabel(source.displayName)
    }

    private var renderingMode: Image.TemplateRenderingMode {
        style == .monochrome ? .template : .original
    }

    private var applicationIcon: NSImage? {
        guard let bundleIdentifier = source.brandApplicationBundleIdentifier else { return nil }
        let applicationURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleIdentifier
        ) ?? URL(fileURLWithPath: "/Applications/WorkBuddy.app")
        guard FileManager.default.fileExists(atPath: applicationURL.path) else { return nil }
        return NSWorkspace.shared.icon(forFile: applicationURL.path)
    }
}

// Pixel art permission indicator icon
struct PermissionIndicatorIcon: View {
    let size: CGFloat
    let color: Color

    init(size: CGFloat = 14, color: Color = Color(red: 0.11, green: 0.12, blue: 0.13)) {
        self.size = size
        self.color = color
    }

    private let pixels: [(CGFloat, CGFloat)] = [
        (7, 7), (7, 11),
        (11, 3),
        (15, 3), (15, 19), (15, 27),
        (19, 3), (19, 15),
        (23, 7), (23, 11),
    ]

    var body: some View {
        Canvas { context, _ in
            let scale = size / 30.0
            let pixelSize: CGFloat = 4 * scale

            for (x, y) in pixels {
                let rect = CGRect(
                    x: x * scale - pixelSize / 2,
                    y: y * scale - pixelSize / 2,
                    width: pixelSize,
                    height: pixelSize
                )
                context.fill(Path(rect), with: .color(color))
            }
        }
        .frame(width: size, height: size)
    }
}

// Pixel art "ready for input" indicator icon
struct ReadyForInputIndicatorIcon: View {
    let size: CGFloat
    let color: Color

    init(size: CGFloat = 14, color: Color = TerminalColors.green) {
        self.size = size
        self.color = color
    }

    private let pixels: [(CGFloat, CGFloat)] = [
        (5, 15),
        (9, 19),
        (13, 23),
        (17, 19),
        (21, 15),
        (25, 11),
        (29, 7),
    ]

    var body: some View {
        Canvas { context, _ in
            let scale = size / 30.0
            let pixelSize: CGFloat = 4 * scale

            for (x, y) in pixels {
                let rect = CGRect(
                    x: x * scale - pixelSize / 2,
                    y: y * scale - pixelSize / 2,
                    width: pixelSize,
                    height: pixelSize
                )
                context.fill(Path(rect), with: .color(color))
            }
        }
        .frame(width: size, height: size)
    }
}
