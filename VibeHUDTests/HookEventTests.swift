import Foundation
import Testing
@testable import vibe_hud

@Suite("Hook event mapping")
struct HookEventTests {
    @Test("Maps lifecycle statuses to session phases")
    func mapsLifecycleStatuses() {
        #expect(makeEvent(status: "processing").determinePhase() == .processing)
        #expect(makeEvent(status: "running_tool").determinePhase() == .processing)
        #expect(makeEvent(status: "waiting_for_input").determinePhase() == .waitingForInput)
        #expect(makeEvent(status: "compacting").determinePhase() == .compacting)
        #expect(makeEvent(status: "ended").determinePhase() == .ended)
        #expect(makeEvent(status: "failed", message: "Rate limited").determinePhase() == .failed("Rate limited"))
    }

    @Test("PreCompact overrides a stale status")
    func preCompactTakesPriority() {
        let event = makeEvent(event: "PreCompact", status: "waiting_for_input")

        #expect(event.determinePhase() == .compacting)
    }

    @Test("Creates approval context for permission events")
    func createsApprovalContext() throws {
        let event = makeEvent(
            event: "PermissionRequest",
            status: "waiting_for_approval",
            tool: "Bash",
            toolUseId: "tool-1"
        )

        let phase = event.determinePhase()
        guard case .waitingForApproval(let context) = phase else {
            Issue.record("Expected waiting-for-approval phase")
            return
        }
        #expect(context.toolUseId == "tool-1")
        #expect(context.toolName == "Bash")
        #expect(event.expectsResponse)
    }

    @Test("Failure events participate in tool handling and transcript sync")
    func failureEventsAreActionable() {
        let toolFailure = makeEvent(event: "PostToolUseFailure", status: "processing")
        let stopFailure = makeEvent(event: "StopFailure", status: "failed")

        #expect(toolFailure.isToolEvent)
        #expect(toolFailure.shouldSyncFile)
        #expect(stopFailure.shouldSyncFile)
    }
}

private func makeEvent(
    event: String = "UserPromptSubmit",
    status: String,
    message: String? = nil,
    tool: String? = nil,
    toolUseId: String? = nil
) -> HookEvent {
    HookEvent(
        sessionId: "session-1",
        cwd: "/tmp/project",
        event: event,
        status: status,
        source: "codex",
        pid: nil,
        tty: nil,
        transcriptPath: nil,
        terminalBundleId: nil,
        terminalPid: nil,
        tmuxPane: nil,
        tmuxSocket: nil,
        tool: tool,
        toolInput: nil,
        toolUseId: toolUseId,
        notificationType: nil,
        message: message
    )
}
