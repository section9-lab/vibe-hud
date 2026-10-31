import AppKit
import SwiftUI
import Testing
@testable import vibe_hud

@Suite("Agent brand icons")
struct AgentBrandIconTests {
    @Test(
        "Maps agents to packaged LobeHub assets",
        arguments: [
            (SessionSource.claude, "AgentClaude"),
            (SessionSource.codex, "AgentGPT"),
            (SessionSource.cursor, "AgentCursor"),
            (SessionSource.copilot, "AgentGitHubCopilot"),
            (SessionSource.pi, "AgentPi"),
            (SessionSource.opencode, "AgentOpenCode"),
            (SessionSource.workbuddy, "AgentWorkBuddy"),
        ]
    )
    func mapsPackagedAssets(source: SessionSource, assetName: String) {
        #expect(source.brandAssetName == assetName)
        #expect(NSImage(named: assetName) != nil)
    }

    @Test("WorkBuddy uses a packaged silhouette, not a filled app tile, in monochrome")
    func mapsWorkBuddyMonochromeAsset() {
        #expect(SessionSource.workbuddy.brandMonochromeAssetName == "AgentWorkBuddyMono")
        #expect(NSImage(named: "AgentWorkBuddyMono") != nil)
    }

    @Test("Renders the GPT mark instead of a filled tile in settings")
    @MainActor
    func rendersUnframedGPTMark() throws {
        let renderer = ImageRenderer(
            content: AgentBrandIcon(source: .codex, style: .monochrome, size: 24)
        )
        renderer.scale = 2
        let image = try #require(renderer.nsImage)
        let cgImage = try #require(
            image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        )
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        var visiblePixels = 0

        for x in 0..<bitmap.pixelsWide {
            for y in 0..<bitmap.pixelsHigh {
                if bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0 > 0.2 {
                    visiblePixels += 1
                }
            }
        }

        #expect(visiblePixels * 3 < bitmap.pixelsWide * bitmap.pixelsHigh * 2)
    }

    @Test(
        "Renders settings icons as white templates",
        arguments: [
            SessionSource.claude,
            .codex,
            .cursor,
            .copilot,
            .pi,
            .opencode,
            .workbuddy,
        ]
    )
    @MainActor
    func rendersMonochromeSettingsIcon(source: SessionSource) throws {
        let renderer = ImageRenderer(
            content: AgentBrandIcon(source: source, style: .monochrome, size: 24)
        )
        renderer.scale = 2
        let image = try #require(renderer.nsImage)
        let cgImage = try #require(
            image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        )
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        var visiblePixels = 0

        for x in 0..<bitmap.pixelsWide {
            for y in 0..<bitmap.pixelsHigh {
                guard let color = bitmap.colorAt(x: x, y: y),
                      color.alphaComponent > 0.2 else { continue }
                visiblePixels += 1
                #expect(abs(color.redComponent - color.greenComponent) < 0.03)
                #expect(abs(color.greenComponent - color.blueComponent) < 0.03)
            }
        }

        #expect(visiblePixels > 40)
    }
}
