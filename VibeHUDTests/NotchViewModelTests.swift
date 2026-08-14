import CoreGraphics
import Testing
@testable import vibe_hud

@Suite("Notch sizing", .serialized)
@MainActor
struct NotchViewModelTests {
    @Test("Uses responsive widths for each content type")
    func responsiveWidths() {
        let model = makeModel(screenWidth: 2_000)

        #expect(model.openedSize.width == 384)
        model.contentType = .menu
        #expect(model.openedSize.width == 384)
        model.contentType = .chat(makeSession())
        #expect(model.openedSize.width == 480)
    }

    @Test("Caps the session list at five visible rows")
    func capsSessionListHeight() {
        let model = makeModel(windowHeight: 800)
        model.updateInstancesContentHeight(2_000)

        #expect(model.instancesContentHeight == 278)
        #expect(model.openedSize.height == 322)
    }

    @Test("Caps menu height to the available window")
    func capsMenuHeight() {
        let model = makeModel(windowHeight: 500)
        model.contentType = .menu
        model.updateMenuContentHeight(1_000)

        #expect(model.openedSize.height == 500)
    }

    @Test("Leaving settings collapses the Agent Hooks list")
    func leavingSettingsCollapsesHooks() {
        let model = makeModel()
        model.toggleMenu()
        model.hookListExpanded = true

        model.toggleMenu()

        #expect(model.contentType == .instances)
        #expect(!model.hookListExpanded)
    }
}

@MainActor
private func makeModel(screenWidth: CGFloat = 1_200, windowHeight: CGFloat = 700) -> NotchViewModel {
    NotchViewModel(
        deviceNotchRect: CGRect(x: 0, y: 0, width: 200, height: 32),
        screenRect: CGRect(x: 0, y: 0, width: screenWidth, height: 800),
        windowHeight: windowHeight,
        hasPhysicalNotch: true
    )
}

private func makeSession() -> SessionState {
    SessionState(sessionId: "session-1", cwd: "/tmp/project")
}
