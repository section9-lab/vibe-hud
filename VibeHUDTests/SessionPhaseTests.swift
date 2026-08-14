import Foundation
import Testing
@testable import vibe_hud

@Suite("Session phase state machine")
struct SessionPhaseTests {
    @Test("SessionStart can move an idle session to ready")
    func idleCanBecomeReady() {
        #expect(SessionPhase.idle.canTransition(to: .waitingForInput))
    }

    @Test("Ended is terminal")
    func endedIsTerminal() {
        #expect(!SessionPhase.ended.canTransition(to: .processing))
        #expect(!SessionPhase.ended.canTransition(to: .waitingForInput))
    }

    @Test("Failures require attention and can recover")
    func failureAttentionAndRecovery() {
        let failed = SessionPhase.failed("Request failed")

        #expect(failed.needsAttention)
        #expect(failed.canTransition(to: .processing))
        #expect(failed.canTransition(to: .waitingForInput))
    }

    @Test("Formats the most relevant permission input")
    func formatsPermissionInput() {
        let context = PermissionContext(
            toolUseId: "tool-1",
            toolName: "Bash",
            toolInput: ["command": AnyCodable("git status")],
            receivedAt: Date(timeIntervalSince1970: 0)
        )

        #expect(context.formattedInput == "git status")
    }
}
