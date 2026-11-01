import Foundation
import Testing
@testable import vibe_hud

@MainActor
@Suite("WorkBuddy state recovery")
struct WorkBuddyStateRecoveryTests {
    @Test("Tools, results and commentary do not complete a turn", arguments: [
        "{\"type\":\"function_call\",\"name\":\"TaskOutput\"}",
        "{\"type\":\"function_call_result\",\"status\":\"completed\"}",
        "{\"type\":\"reasoning\"}",
        "{\"type\":\"message\",\"role\":\"user\"}",
        "{\"type\":\"message\",\"role\":\"assistant\",\"status\":\"completed\"}",
    ])
    func activeEvidence(record: String) throws {
        var json = try #require(JSONSerialization.jsonObject(with: Data(record.utf8)) as? [String: Any])
        json["timestamp"] = 1760000001000.0
        let content = String(decoding: try JSONSerialization.data(withJSONObject: json), as: UTF8.self)
        let recovered = WorkBuddyTranscriptState.parseContent(content)
        #expect(recovered?.status == "processing")
        #expect(recovered?.timestamp == 1760000001)
    }

    @Test("A final response with turn usage returns ready, ignoring metadata and partial writes")
    func finalResponse() {
        let content = """
        {"timestamp":1760000001000,"type":"message","role":"assistant","status":"completed","message":{"usage":{"output_tokens":42}}}
        {"timestamp":1760000002000,"type":"ai-title","aiTitle":"Task"}
        {"type":"function_call",
        """
        #expect(WorkBuddyTranscriptState.parseContent(content)?.status == "waiting_for_input")
    }

    @Test("A new user turn supersedes the previous final response")
    func nextTurn() {
        let content = """
        {"timestamp":1760000001000,"type":"message","role":"assistant","status":"completed","message":{"usage":{}}}
        {"timestamp":1760000002000,"type":"message","role":"user"}
        """
        #expect(WorkBuddyTranscriptState.parseContent(content)?.status == "processing")
    }

    @Test("No usable evidence is unknown, never assumed ready")
    func noEvidence() {
        #expect(WorkBuddyTranscriptState.parseContent("") == nil)
        #expect(WorkBuddyTranscriptState.parseContent("{\"type\":\"ai-title\",\"timestamp\":1760000001000}") == nil)
    }

    @Test("Recovery never rewinds or ties a newer live hook")
    func eventOrdering() {
        let state = WorkBuddyTranscriptState(status: "processing", timestamp: 100)
        #expect(state.isNewer(than: nil))
        #expect(state.isNewer(than: 99))
        #expect(!state.isNewer(than: 100))
        #expect(!state.isNewer(than: 101))
    }

    @Test("Bounded tail reads handle large transcripts and partial trailing records")
    func readsTail() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let content = String(repeating: "x", count: 300_000) + "\n" + """
        {"timestamp":1760000001000,"type":"function_call_result","status":"completed"}
        {"type":
        """
        try content.write(to: url, atomically: true, encoding: .utf8)
        #expect(WorkBuddyTranscriptState.read(at: url)?.status == "processing")
    }

    @Test("Both recovered running sessions contribute to the header count")
    func countsBothSessions() async {
        let store = SessionStore()
        for id in ["first", "second"] {
            await store.process(.hookReceived(hook(id: id, status: "processing", timestamp: 100)))
        }
        let first = await store.session(for: "first")
        let second = await store.session(for: "second")
        let sessions = [first, second].compactMap { $0 }
        #expect(sessions.count == 2)
        #expect(AgentActivitySummary(sessions: sessions).runningSessionCount == 2)
    }

    @Test("Unknown discovery cannot overwrite an existing running session")
    func discoveryPreservesHooks() async {
        let session = SessionState(sessionId: "first", cwd: "/tmp/project", source: .workbuddy, phase: .processing)
        let store = SessionStore(initialSessions: [session])
        await store.process(.hookReceived(hook(id: "first", status: "unknown")))
        #expect(await store.session(for: "first")?.phase == .processing)
        #expect(await store.session(for: "first")?.hasReliableStatus == true)
    }

    @Test("Discovery without evidence is visibly pending sync")
    func unknownDiscovery() async {
        let store = SessionStore()
        await store.process(.hookReceived(hook(id: "first", status: "unknown")))
        #expect(await store.session(for: "first")?.hasReliableStatus == false)
        #expect(await store.session(for: "first")?.phase.isActive == false)
    }

    @Test("Stale transcript recovery preserves newer completion and permission hooks")
    func preservesNewerHooks() async {
        let context = PermissionContext(toolUseId: "tool", toolName: "Bash", toolInput: nil, receivedAt: Date())
        for phase in [SessionPhase.waitingForInput, .waitingForApproval(context)] {
            let session = SessionState(
                sessionId: "first", cwd: "/tmp/project", source: .workbuddy,
                phase: phase, lastEventTimestamp: 200
            )
            let store = SessionStore(initialSessions: [session])
            await store.process(.hookReceived(hook(id: "first", status: "processing", timestamp: 100)))
            #expect(await store.session(for: "first")?.phase == phase)
        }
    }

    @Test("Transcript file updates repair missed hooks even without runtime discovery")
    func fileUpdateRecoversState() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let directory = root.appendingPathComponent(".workbuddy/projects/project")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let transcript = directory.appendingPathComponent("first.jsonl")
        try """
        {"id":"result","timestamp":1760000001000,"type":"function_call_result","callId":"tool","status":"completed"}
        """.write(to: transcript, atomically: true, encoding: .utf8)
        let session = SessionState(
            sessionId: "first", cwd: "/tmp/project", source: .workbuddy,
            transcriptPath: transcript.path, phase: .waitingForInput, lastEventTimestamp: 1760000000
        )
        let store = SessionStore(initialSessions: [session])
        await store.process(.fileUpdated(FileUpdatePayload(
            sessionId: "first", cwd: session.cwd, transcriptPath: transcript.path,
            messages: [], isIncremental: true, completedToolIds: [], toolResults: [:], structuredResults: [:]
        )))
        #expect(await store.session(for: "first")?.phase == .processing)
        #expect(await store.session(for: "first")?.lastEventTimestamp == 1760000001)
    }

    @Test("Informational events preserve both the phase and its evidence clock",
          arguments: ["notification", "unknown", "future-adapter-status"])
    func informationalEventsCannotResetPhase(status: String) async {
        let context = PermissionContext(toolUseId: "tool", toolName: "Bash", toolInput: nil, receivedAt: Date())
        for phase in [SessionPhase.processing, .compacting, .waitingForInput, .waitingForApproval(context), .failed("Error")] {
            let session = SessionState(
                sessionId: "first", cwd: "/tmp/project", source: .workbuddy,
                phase: phase, lastEventTimestamp: 100
            )
            let store = SessionStore(initialSessions: [session])
            await store.process(.hookReceived(hook(
                id: "first", status: status, timestamp: 200, event: "Notification"
            )))
            #expect(await store.session(for: "first")?.phase == phase)
            #expect(await store.session(for: "first")?.lastEventTimestamp == 100)
            #expect(await store.session(for: "first")?.hasReliableStatus == true)
        }
    }

    @Test("Two long-running tools remain active without new transcript records after a notification")
    func longRunningToolsRemainActive() async {
        let store = SessionStore()
        for id in ["first", "second"] {
            await store.process(.hookReceived(hook(id: id, status: "processing", timestamp: 100)))
        }
        await store.process(.hookReceived(hook(
            id: "second", status: "notification", timestamp: 110, event: "Notification"
        )))
        // Recovery repeats the same evidence while a shell command runs for minutes.
        await store.process(.hookReceived(hook(id: "second", status: "processing", timestamp: 100)))
        await store.recheckAllSessions(
            codexSessionsDirectory: URL(fileURLWithPath: "/tmp/\(UUID().uuidString)"),
            now: Date(timeIntervalSince1970: 400)
        )
        let first = await store.session(for: "first")
        let second = await store.session(for: "second")
        #expect(first?.phase == .processing)
        #expect(second?.phase == .processing)
        #expect(second?.lastEventTimestamp == 100)
        #expect(AgentActivitySummary(sessions: [first, second].compactMap { $0 }).runningSessionCount == 2)
    }

    @Test("Unidentified host hooks and unknown events do not create project-named phantom sessions")
    func ignoresPhantomSessions() async {
        let store = SessionStore()
        await store.process(.hookReceived(hook(id: "unknown", status: "waiting_for_input", event: "SessionStart")))
        await store.process(.hookReceived(hook(id: "opaque-host", status: "unknown", event: "")))
        await store.process(.hookReceived(hook(id: "notice", status: "notification", event: "Notification")))
        #expect(await store.session(for: "unknown") == nil)
        #expect(await store.session(for: "opaque-host") == nil)
        #expect(await store.session(for: "notice") == nil)
    }

    @Test("Explicit ready notifications still finish a turn",
          arguments: ["idle_prompt", "agent_needs_input", "agent_completed"])
    func idlePromptIsStillAuthoritative(notificationType: String) async {
        let session = SessionState(
            sessionId: "first", cwd: "/tmp/project", source: .workbuddy,
            phase: .processing, lastEventTimestamp: 100
        )
        let store = SessionStore(initialSessions: [session])
        await store.process(.hookReceived(hook(
            id: "first", status: "notification", timestamp: 200,
            event: "Notification", notificationType: notificationType
        )))
        #expect(await store.session(for: "first")?.phase == .waitingForInput)
        #expect(await store.session(for: "first")?.lastEventTimestamp == 200)
    }

    private func hook(
        id: String, status: String, timestamp: TimeInterval? = nil,
        event: String = "WorkBuddyRecovery", notificationType: String? = nil
    ) -> HookEvent {
        HookEvent(
            sessionId: id, cwd: "/tmp/project", event: event, status: status,
            source: "workbuddy", pid: nil, tty: nil, transcriptPath: nil,
            terminalBundleId: nil, terminalPid: nil, tmuxPane: nil, tmuxSocket: nil,
            tool: nil, toolInput: nil, toolUseId: nil, notificationType: notificationType, message: nil,
            eventTimestamp: timestamp
        )
    }
}
