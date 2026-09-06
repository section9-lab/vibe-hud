import Foundation
import Testing
@testable import vibe_hud

@Suite("Session lifecycle during file sync")
struct SessionStoreTests {
    @Test(
        "A file sync cannot overwrite a terminal hook event",
        arguments: ["Stop", "SessionEnd", "StopFailure"], ["claude", "codex", "copilot"]
    )
    @MainActor
    func fileSyncPreservesTerminalEvent(event: String, source: String) async {
        let session = SessionState(
            sessionId: UUID().uuidString,
            cwd: "/tmp/project",
            source: SessionSource(rawSource: source),
            phase: .processing
        )
        let store = SessionStore(initialSessions: [session])
        let hook = makeHook(
            sessionId: session.sessionId,
            event: event,
            status: event == "SessionEnd" ? "ended" : event == "StopFailure" ? "failed" : "waiting_for_input",
            source: source
        )

        let payload = FileUpdatePayload(
            sessionId: session.sessionId,
            cwd: session.cwd,
            transcriptPath: nil,
            messages: [ChatMessage(
                id: "final-message",
                role: .assistant,
                timestamp: Date(),
                content: [.text("Finished")]
            )],
            isIncremental: true,
            completedToolIds: [],
            toolResults: [:],
            structuredResults: [:]
        )
        await syncWhileHandling(.hookReceived(hook), payload: payload, store: store)

        let updated = await store.session(for: session.sessionId)
        if event == "SessionEnd" {
            #expect(updated == nil)
        } else {
            #expect(updated?.phase == (event == "StopFailure" ? .failed(nil) : .waitingForInput))
            #expect(updated?.chatItems.contains { $0.id == "final-message-text-0" } == true)
        }
    }

    @Test("Hooks without process metadata retain process exit detection", arguments: [true, false])
    @MainActor
    func preservesKnownProcess(isRunning: Bool) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try process.run()
        process.waitUntilExit()
        let session = SessionState(
            sessionId: UUID().uuidString,
            cwd: "/tmp/project",
            source: .copilot,
            pid: Int(isRunning ? getpid() : process.processIdentifier),
            phase: .processing
        )
        let store = SessionStore(initialSessions: [session])

        await store.process(.hookReceived(makeHook(sessionId: session.sessionId)))

        #expect(await store.session(for: session.sessionId)?.pid == session.pid)

        await store.recheckAllSessions(
            codexSessionsDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )

        let remaining = await store.session(for: session.sessionId)
        #expect((remaining != nil) == isRunning)
    }

    private func syncWhileHandling(
        _ event: SessionEvent,
        payload: FileUpdatePayload,
        store: isolated SessionStore
    ) async {
        // Queue the hook on the same actor before the file read yields to the parser.
        let hookTask = Task(priority: .high) { await store.process(event) }
        await store.process(.fileUpdated(payload))
        await hookTask.value
    }

    private func makeHook(
        sessionId: String,
        event: String = "PostToolUse",
        status: String = "processing",
        source: String = "copilot"
    ) -> HookEvent {
        HookEvent(
            sessionId: sessionId,
            cwd: "/tmp/project",
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
            tool: nil,
            toolInput: nil,
            toolUseId: nil,
            notificationType: nil,
            message: nil
        )
    }
}
