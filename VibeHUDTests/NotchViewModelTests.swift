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

    @Test("Closed monitoring switches to one entry when native space is narrow")
    func closedMonitoringCompacts() {
        let narrow = NotchViewModel(
            deviceNotchRect: CGRect(x: 0, y: 0, width: 200, height: 32),
            screenRect: CGRect(x: 0, y: 0, width: 1_200, height: 800),
            windowHeight: 700, hasPhysicalNotch: true, topRightAreaWidth: 120
        )
        let entries: [NotchAccessory] = [.codex, .claude, .tibo]
        narrow.configureClosedAccessories(entries, leadingExtension: 0)
        #expect(narrow.closedAccessories == [.more])

        let wide = makeModel(screenWidth: 2_000)
        wide.configureClosedAccessories(entries, leadingExtension: 0)
        #expect(wide.closedAccessories == entries)
        wide.configureClosedAccessories([], leadingExtension: 0)
        #expect(wide.closedAccessories.isEmpty)
        #expect(wide.closedTrailingExtension == 0)
        #expect(wide.closedLeadingExtension == 0)

        let builtin = NotchViewModel(
            deviceNotchRect: CGRect(x: 0, y: 0, width: 183, height: 32),
            screenRect: CGRect(x: 0, y: 0, width: 1_470, height: 956),
            windowHeight: 750, hasPhysicalNotch: true, topRightAreaWidth: 645.5
        )
        builtin.configureClosedAccessories(entries, leadingExtension: 0)
        #expect(builtin.closedAccessories == entries)
        #expect(builtin.closedTrailingExtension == 84)
        builtin.configureClosedAccessories([.codex], leadingExtension: 0)
        #expect(builtin.closedTrailingExtension == 34)
    }

    @Test("Each source shares one ring and every hidden item removes its cell")
    func visibleRingCombinations() {
        let both = NotchAccessory.visible(codexQuota: true, codexSpeed: true,
                                          claude5h: true, claude7d: true, claudeSpeed: true,
                                          tiboAlert: false)
        let quotaOnly = NotchAccessory.visible(codexQuota: true, codexSpeed: false,
                                               claude5h: false, claude7d: false, claudeSpeed: false,
                                               tiboAlert: false)
        let speedOnly = NotchAccessory.visible(codexQuota: false, codexSpeed: true,
                                               claude5h: false, claude7d: false, claudeSpeed: false,
                                               tiboAlert: false)
        let hidden = NotchAccessory.visible(codexQuota: false, codexSpeed: false,
                                            claude5h: false, claude7d: false, claudeSpeed: false,
                                            tiboAlert: false)
        let onlyClaude5h = NotchAccessory.visible(codexQuota: false, codexSpeed: false,
                                                  claude5h: true, claude7d: false, claudeSpeed: false,
                                                  tiboAlert: false)
        let onlyClaude7d = NotchAccessory.visible(codexQuota: false, codexSpeed: false,
                                                  claude5h: false, claude7d: true, claudeSpeed: false,
                                                  tiboAlert: false)
        let onlyClaudeSpeed = NotchAccessory.visible(codexQuota: false, codexSpeed: false,
                                                     claude5h: false, claude7d: false, claudeSpeed: true,
                                                     tiboAlert: false)
        #expect(both == [.codex, .claude])
        #expect(quotaOnly == [.codex])
        #expect(speedOnly == [.codex])
        #expect(onlyClaude5h == [.claude])
        #expect(onlyClaude7d == [.claude])
        #expect(onlyClaudeSpeed == [.claude])
        #expect(hidden.isEmpty)
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
