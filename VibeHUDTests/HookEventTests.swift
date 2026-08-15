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

    @Test("Ignores WorkBuddy prewarm pool sessions")
    func ignoresWorkBuddyPrewarmPool() {
        let prewarm = makeEvent(
            status: "starting",
            sessionId: "prewarm-wb-pool-1786775838603-b72ed2",
            cwd: "/",
            source: "workbuddy"
        )
        let task = makeEvent(
            status: "processing",
            sessionId: "2fc80cc6-725a-45f3-b018-7ffd85f5f2b8",
            cwd: "/Users/test/WorkBuddy/task",
            source: "workbuddy"
        )

        #expect(!prewarm.isDisplayableSession)
        #expect(task.isDisplayableSession)
    }

    @Test("Preserves Codex turn identity and Stop hook state")
    @MainActor
    func preservesCodexTurnMetadata() throws {
        let data = Data("""
        {
          "session_id": "session-1",
          "cwd": "/tmp/project",
          "event": "Stop",
          "status": "waiting_for_input",
          "source": "codex",
          "turn_id": "turn-1",
          "stop_hook_active": true
        }
        """.utf8)

        let event = try JSONDecoder().decode(HookEvent.self, from: data)
        let encoded = try JSONEncoder().encode(event)
        let json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        #expect(json["turn_id"] as? String == "turn-1")
        #expect(json["stop_hook_active"] as? Bool == true)
    }
}

private func makeEvent(
    event: String = "UserPromptSubmit",
    status: String,
    message: String? = nil,
    tool: String? = nil,
    toolUseId: String? = nil,
    sessionId: String = "session-1",
    cwd: String = "/tmp/project",
    source: String = "codex"
) -> HookEvent {
    HookEvent(
        sessionId: sessionId,
        cwd: cwd,
        event: event,
        status: status,
        source: source,
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
