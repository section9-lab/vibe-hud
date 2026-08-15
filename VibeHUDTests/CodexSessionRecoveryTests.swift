import Foundation
import Testing
@testable import vibe_hud

@Suite("Codex rollout recovery")
struct CodexSessionRecoveryTests {
    private let prefix = """
    {"type":"session_meta","payload":{"id":"session-1","cwd":"/tmp/project"}}
    {"type":"event_msg","payload":{"type":"user_message"}}
    """

    @Test(
        "Terminal rollout events return the session to ready",
        arguments: ["task_complete", "turn_aborted"]
    )
    func terminalEventsReturnReady(eventType: String) throws {
        let content = prefix + "\n{\"type\":\"event_msg\",\"payload\":{\"type\":\"\(eventType)\"}}"

        let recovered = CodexSessionRecovery.parseContent(
            content,
            transcriptPath: "/tmp/rollout.jsonl"
        )

        #expect(recovered?.sessionId == "session-1")
        #expect(recovered?.cwd == "/tmp/project")
        #expect(recovered?.status == "waiting_for_input")
    }

    @Test("An active rollout is recovered as processing")
    func activeRolloutIsProcessing() {
        let recovered = CodexSessionRecovery.parseContent(
            prefix,
            transcriptPath: "/tmp/rollout.jsonl"
        )

        #expect(recovered?.status == "processing")
    }

    @Test("Rollouts without metadata are ignored")
    func missingMetadataIsIgnored() {
        let recovered = CodexSessionRecovery.parseContent(
            "{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_complete\"}}",
            transcriptPath: "/tmp/rollout.jsonl"
        )

        #expect(recovered == nil)
    }

    @Test("Recovers only the eight most recent rollouts from the last 15 minutes")
    func filtersAndLimitsRollouts() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let now = Date(timeIntervalSince1970: 10_000)
        for index in 0..<10 {
            try writeRollout(index: index, modifiedAt: now.addingTimeInterval(TimeInterval(-index)), to: directory)
        }
        for index in 0..<5 {
            let internalRollout = directory.appendingPathComponent("rollout-internal-\(index).jsonl")
            try "{\"type\":\"response_item\",\"payload\":{\"type\":\"reasoning\"}}"
                .write(to: internalRollout, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.modificationDate: now.addingTimeInterval(TimeInterval(index + 1))],
                ofItemAtPath: internalRollout.path
            )
        }
        try writeRollout(index: 99, modifiedAt: now.addingTimeInterval(-901), to: directory)

        let recovered = CodexSessionRecovery.recentSessions(in: directory, now: now)

        #expect(recovered.count == 8)
        #expect(recovered.map(\.sessionId) == (0..<8).map { "session-\($0)" })
        #expect(!recovered.contains { $0.sessionId == "session-99" })
    }

    @Test("Detects a stale recovered Codex session without a pid")
    func detectsStalePidlessSession() throws {
        let (session, now, directory) = try makeStaleSession(pid: nil)
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(SessionStore.isStaleCodexSession(session, now: now))
    }

    @Test("Detects a stale Codex session with a live shared host pid")
    func detectsStaleSessionWithSharedHostPid() throws {
        let (session, now, directory) = try makeStaleSession(pid: Int(getpid()))
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(SessionStore.isStaleCodexSession(session, now: now))
    }

    @Test("Detects a Codex session whose rollout was moved to the archive")
    func detectsMissingRollout() {
        let session = SessionState(
            sessionId: "archived-session",
            cwd: "/tmp/project",
            source: .codex,
            transcriptPath: "/tmp/\(UUID().uuidString)/rollout.jsonl",
            phase: .waitingForInput
        )

        #expect(SessionStore.isStaleCodexSession(session))
    }

    @Test("Periodic checks refresh a Codex session after its turn completes")
    func periodicCheckRefreshesCompletedTurn() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let rollout = directory.appendingPathComponent("rollout-live.jsonl")
        try prefix.write(to: rollout, atomically: true, encoding: .utf8)

        let session = SessionState(
            sessionId: "session-1",
            cwd: "/tmp/project",
            source: .codex,
            transcriptPath: rollout.path,
            phase: .processing
        )
        let store = SessionStore(initialSessions: [session])

        let completed = prefix + "\n{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_complete\"}}"
        try completed.write(to: rollout, atomically: true, encoding: .utf8)
        await store.recheckAllSessions()

        #expect(await store.session(for: "session-1")?.phase == .waitingForInput)

        let resumed = completed + "\n{\"type\":\"event_msg\",\"payload\":{\"type\":\"user_message\"}}"
        try resumed.write(to: rollout, atomically: true, encoding: .utf8)
        await store.recheckAllSessions()

        #expect(await store.session(for: "session-1")?.phase == .processing)
    }

    private func makeStaleSession(pid: Int?) throws -> (SessionState, Date, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let rollout = directory.appendingPathComponent("rollout-stale.jsonl")
        try "".write(to: rollout, atomically: true, encoding: .utf8)
        let now = Date()
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-CodexSessionRecovery.maximumSessionAge - 1)],
            ofItemAtPath: rollout.path
        )

        let session = SessionState(
            sessionId: "stale-session",
            cwd: "/tmp/project",
            source: .codex,
            pid: pid,
            transcriptPath: rollout.path,
            phase: .processing
        )

        return (session, now, directory)
    }

    private func writeRollout(index: Int, modifiedAt: Date, to directory: URL) throws {
        let url = directory.appendingPathComponent("rollout-\(index).jsonl")
        let content = """
        {"type":"session_meta","payload":{"id":"session-\(index)","cwd":"/tmp/project-\(index)"}}
        {"type":"event_msg","payload":{"type":"task_complete"}}
        """
        try content.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: url.path)
    }
}
