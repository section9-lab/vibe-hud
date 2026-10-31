import AppKit
import SwiftUI
import Testing
@testable import vibe_hud

@MainActor
@Suite("Notch update indicator")
struct NotchUpdateButtonTests {
    @Test("No header indicator during routine checks", arguments: [UpdateState.idle, .checking, .upToDate])
    func hidesRoutineChecks(state: UpdateState) throws {
        let manager = UpdateManager()
        manager.state = state
        #expect(!manager.showsNotchIndicator)
        #expect(try visiblePixels(manager: manager) == 0)
    }

    @Test("Available updates render a compact red arrow")
    func rendersRedArrow() throws {
        let manager = UpdateManager()
        manager.updateFound(version: "2.0", releaseNotes: nil) { _ in }
        #expect(manager.showsNotchIndicator)
        let pixels = try visiblePixels(manager: manager, redOnly: true)
        #expect(pixels > 10)
        // It must be a glyph, not the previous filled text button.
        #expect(pixels < 22 * 22 * 4 / 2)
    }

    @Test("Download, preparation and restart render progress instead of an interactive arrow",
          arguments: [UpdateState.downloading(progress: 0.5), .extracting(progress: 0.75), .installing])
    func rendersBusyProgress(state: UpdateState) throws {
        let manager = UpdateManager()
        manager.state = state
        #expect(manager.showsNotchIndicator)
        #expect(!manager.state.isInteractive)
        #expect(try visiblePixels(manager: manager, redOnly: true) > 5)
    }

    private func visiblePixels(manager: UpdateManager, redOnly: Bool = false) throws -> Int {
        let renderer = ImageRenderer(content: NotchUpdateButton(updateManager: manager)
            .frame(width: 22, height: 22).background(.black))
        renderer.scale = 2
        let image = try #require(renderer.nsImage)
        let cgImage = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        var count = 0
        for x in 0..<bitmap.pixelsWide {
            for y in 0..<bitmap.pixelsHigh {
                guard let color = bitmap.colorAt(x: x, y: y), color.alphaComponent > 0.2,
                      max(color.redComponent, color.greenComponent, color.blueComponent) > 0.05 else { continue }
                if !redOnly || (color.redComponent > color.greenComponent * 1.5 && color.redComponent > color.blueComponent * 1.5) {
                    count += 1
                }
            }
        }
        return count
    }
}
