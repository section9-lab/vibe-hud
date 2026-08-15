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

    @Test(
        "Assistant output does not complete an active rollout",
        arguments: [
            "{\"type\":\"event_msg\",\"payload\":{\"type\":\"agent_message\",\"phase\":\"commentary\"}}",
            "{\"type\":\"response_item\",\"payload\":{\"type\":\"message\",\"role\":\"assistant\",\"phase\":\"commentary\"}}"
        ]
    )
    func assistantOutputStaysProcessing(event: String) {
        let recovered = CodexSessionRecovery.parseContent(
            prefix + "\n" + event,
            transcriptPath: "/tmp/rollout.jsonl"
        )

        #expect(recovered?.status == "processing")
    }

    @Test("A new Codex turn supersedes the previous completion")
    func newTurnSupersedesCompletion() {
        let content = prefix + """

        {"type":"event_msg","payload":{"type":"task_complete","turn_id":"turn-1"}}
        {"type":"event_msg","payload":{"type":"task_started","turn_id":"turn-2"}}
        """

        let recovered = CodexSessionRecovery.parseContent(
            content,
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

    @Test("Duplicate child rollouts do not consume the parent session limit")
    func deduplicatesParentSessionsBeforeLimit() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let now = Date(timeIntervalSince1970: 10_000)
        for index in 0..<8 {
            let rollout = directory.appendingPathComponent("rollout-child-\(index).jsonl")
            let content = """
            {"type":"session_meta","payload":{"id":"child-\(index)","cwd":"/tmp/project","source":{"subagent":{"thread_spawn":{"parent_thread_id":"shared-parent"}}}}}
            {"type":"session_meta","payload":{"id":"shared-parent","cwd":"/tmp/project","source":"vscode"}}
            {"type":"event_msg","payload":{"type":"agent_reasoning"}}
            """
            try content.write(to: rollout, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.modificationDate: now.addingTimeInterval(TimeInterval(index + 1))],
                ofItemAtPath: rollout.path
            )
        }
        for index in 0..<8 {
            try writeRollout(index: index, modifiedAt: now.addingTimeInterval(TimeInterval(-index)), to: directory)
        }

        let recovered = CodexSessionRecovery.recentSessions(in: directory, now: now)

        #expect(recovered.count == 8)
        #expect(Set(recovered.map(\.sessionId)).count == 8)
        #expect(recovered.first?.sessionId == "shared-parent")
        #expect(recovered.contains { $0.sessionId == "session-6" })
    }

    @Test("Recovery scans skip rollout files that were already examined")
    func skipsPreviouslyScannedRollouts() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let now = Date()
        try writeRollout(index: 1, modifiedAt: now, to: directory)
        let firstScan = CodexSessionRecovery.scanRecentSessions(in: directory, now: now)
        let secondScan = CodexSessionRecovery.scanRecentSessions(
            in: directory,
            now: now,
            excludingTranscriptPaths: firstScan.examinedTranscriptPaths
        )

        #expect(firstScan.sessions.map(\.sessionId) == ["session-1"])
        #expect(secondScan.sessions.isEmpty)
        #expect(secondScan.examinedTranscriptPaths.isEmpty)
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

    @Test("Rollout completion waits for the fallback delay")
    func rolloutCompletionUsesFallbackDelay() async throws {
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
        let now = Date()

        let completed = prefix + "\n{\"timestamp\":\"2026-08-15T12:00:00Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"task_complete\",\"turn_id\":\"turn-1\"}}"
        try completed.write(to: rollout, atomically: true, encoding: .utf8)
        await store.recheckAllSessions(codexSessionsDirectory: directory, now: now)

        #expect(await store.session(for: "session-1")?.phase == .processing)

        await store.recheckAllSessions(
            codexSessionsDirectory: directory,
            now: now.addingTimeInterval(7)
        )

        #expect(await store.session(for: "session-1")?.phase == .processing)

        await store.recheckAllSessions(
            codexSessionsDirectory: directory,
            now: now.addingTimeInterval(8)
        )

        #expect(await store.session(for: "session-1")?.phase == .waitingForInput)

        let resumed = completed + """

        {"type":"event_msg","payload":{"type":"task_started","turn_id":"turn-2"}}
        {"type":"event_msg","payload":{"type":"user_message"}}
        """
        try resumed.write(to: rollout, atomically: true, encoding: .utf8)
        await store.recheckAllSessions(
            codexSessionsDirectory: directory,
            now: now.addingTimeInterval(9)
        )

        #expect(await store.session(for: "session-1")?.phase == .processing)
    }

    @Test("A newer hook turn cancels a stale rollout completion")
    @MainActor
    func newerHookTurnCancelsCompletion() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let rollout = directory.appendingPathComponent("rollout-live.jsonl")
        let completed = prefix + "\n{\"timestamp\":\"2026-08-15T12:00:00Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"task_complete\",\"turn_id\":\"turn-1\"}}"
        try completed.write(to: rollout, atomically: true, encoding: .utf8)

        let session = SessionState(
            sessionId: "session-1",
            cwd: "/tmp/project",
            source: .codex,
            transcriptPath: rollout.path,
            phase: .processing
        )
        let store = SessionStore(initialSessions: [session])
        let now = Date()

        await store.recheckAllSessions(codexSessionsDirectory: directory, now: now)

        let prompt = try JSONDecoder().decode(HookEvent.self, from: Data("""
        {
          "session_id": "session-1",
          "cwd": "/tmp/project",
          "event": "UserPromptSubmit",
          "status": "processing",
          "source": "codex",
          "turn_id": "turn-2"
        }
        """.utf8))
        await store.process(.hookReceived(prompt))

        await store.recheckAllSessions(
            codexSessionsDirectory: directory,
            now: now.addingTimeInterval(20)
        )

        #expect(await store.session(for: "session-1")?.phase == .processing)
    }

    @Test(
        "Commentary from a stopped hook turn cannot resume the session",
        arguments: [
            "{\"type\":\"event_msg\",\"payload\":{\"type\":\"agent_message\",\"phase\":\"commentary\"}}",
            """
            {"type":"event_msg","payload":{"type":"task_started","turn_id":"turn-1"}}
            {"type":"event_msg","payload":{"type":"agent_message","phase":"commentary"}}
            """
        ]
    )
    @MainActor
    func stoppedTurnCommentaryDoesNotResume(rolloutEvents: String) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let rollout = directory.appendingPathComponent("rollout-live.jsonl")
        let content = prefix + "\n" + rolloutEvents
        try content.write(to: rollout, atomically: true, encoding: .utf8)

        let session = SessionState(
            sessionId: "session-1",
            cwd: "/tmp/project",
            source: .codex,
            transcriptPath: rollout.path,
            phase: .processing
        )
        let store = SessionStore(initialSessions: [session])
        let stop = try JSONDecoder().decode(HookEvent.self, from: Data("""
        {
          "session_id": "session-1",
          "cwd": "/tmp/project",
          "event": "Stop",
          "status": "waiting_for_input",
          "source": "codex",
          "turn_id": "turn-1"
        }
        """.utf8))

        await store.process(.hookReceived(stop))
        await store.recheckAllSessions(codexSessionsDirectory: directory)

        #expect(await store.session(for: "session-1")?.phase == .waitingForInput)
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
