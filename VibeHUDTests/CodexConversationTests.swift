import Foundation
import Testing
@testable import vibe_hud

@MainActor
@Suite("Codex conversation parsing")
struct CodexConversationTests {
    @Test("Loads response-item messages and conversation previews")
    func loadsResponseItems() async throws {
        let fixture = try makeFixture([
            response(role: "developer", text: "Internal instructions", second: 0),
            response(role: "user", text: "Show the session history", second: 1),
            response(role: "assistant", text: "The history is now visible", second: 2)
        ])
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let parser = ConversationParser()

        let messages = await parser.parseFullConversation(
            sessionId: fixture.id, cwd: "/tmp/project", transcriptPath: fixture.transcript.path
        )
        #expect(messages.map(\.role) == [.user, .assistant])
        #expect(messages.map(\.textContent) == ["Show the session history", "The history is now visible"])

        let info = await parser.parse(
            sessionId: fixture.id, cwd: "/tmp/project", transcriptPath: fixture.transcript.path
        )
        #expect(info.firstUserMessage == "Show the session history")
        #expect(info.lastMessage == "The history is now visible")
        #expect(info.lastMessageRole == "assistant")
        #expect(info.lastUserMessageDate == ISO8601DateFormatter().date(from: "2026-09-11T00:00:01Z"))
    }

    @Test("Uses the first user prompt instead of injected app context")
    func filtersInjectedContext() async throws {
        let context = response(
            role: "user", text: "<recommended_plugins>Available plugins</recommended_plugins>", second: 0,
            kind: "plugins.recommendations"
        )
        let fixture = try makeFixture([
            context,
            response(role: "user", text: "# AGENTS.md instructions", second: 0, kind: "agents_md.instructions"),
            response(role: "user", text: "<environment_context>/tmp/project</environment_context>", second: 0,
                     kind: "environments.environment_context"),
            response(role: "user", text: "Add a GIF demo", second: 1, kind: "user.text"),
            response(role: "assistant", text: "I will create the demo", second: 2, kind: "unknown")
        ])
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let parser = ConversationParser()
        let messages = await parser.parseFullConversation(
            sessionId: fixture.id, cwd: "/tmp/project", transcriptPath: fixture.transcript.path
        )
        #expect(messages.map(\.textContent) == ["Add a GIF demo", "I will create the demo"])

        try append(context, to: fixture.transcript)
        let update = await parser.parseIncremental(
            sessionId: fixture.id, cwd: "/tmp/project", transcriptPath: fixture.transcript.path
        )
        #expect(update.newMessages.isEmpty)
        let info = await parser.parse(
            sessionId: fixture.id, cwd: "/tmp/project", transcriptPath: fixture.transcript.path
        )
        #expect(info.firstUserMessage == "Add a GIF demo")
        #expect(info.lastMessage == "I will create the demo")
        #expect(info.lastUserMessageDate == ISO8601DateFormatter().date(from: "2026-09-11T00:00:01Z"))

        let store = SessionStore(initialSessions: [SessionState(
            sessionId: fixture.id, cwd: "/tmp/project", source: .codex,
            transcriptPath: fixture.transcript.path, phase: .waitingForInput
        )])
        await store.process(.loadHistory(sessionId: fixture.id, cwd: "/tmp/project"))
        let loaded = await store.session(for: fixture.id)
        #expect(loaded?.displayTitle == "Add a GIF demo")
        #expect(loaded?.chatItems.first?.type == .user("Add a GIF demo"))
    }

    @Test("Filters context per block while preserving user-authored markup")
    func filtersMixedContent() async throws {
        let prompt = "Explain <recommended_plugins> in this example"
        var record = response(role: "user", text: prompt, second: 1)
        record["payload"] = [
            "type": "message", "role": "user",
            "content": [
                ["type": "input_text", "text": "Internal plugin catalog"],
                ["type": "input_text", "text": prompt],
                ["type": "input_text", "text": "Internal environment details"]
            ],
            "internal_chat_message_metadata_passthrough": [
                "content_item_kinds": ["plugins.recommendations", "user.text", "environments.environment_context"]
            ]
        ]
        let fixture = try makeFixture([record])
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let messages = await ConversationParser().parseFullConversation(
            sessionId: fixture.id, cwd: "/tmp/project", transcriptPath: fixture.transcript.path
        )
        #expect(messages.map(\.textContent) == [prompt])
    }

    @Test("Reads newly appended messages exactly once")
    func readsIncrementally() async throws {
        let fixture = try makeFixture([response(role: "user", text: "Run the checks", second: 1)])
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let parser = ConversationParser()
        _ = await parser.parseFullConversation(
            sessionId: fixture.id, cwd: "/tmp/project", transcriptPath: fixture.transcript.path
        )
        try append(response(role: "assistant", text: "Checks passed", second: 2), to: fixture.transcript)

        let update = await parser.parseIncremental(
            sessionId: fixture.id, cwd: "/tmp/project", transcriptPath: fixture.transcript.path
        )
        #expect(update.newMessages.map(\.textContent) == ["Checks passed"])
        #expect(update.allMessages.count == 2)
        let unchanged = await parser.parseIncremental(
            sessionId: fixture.id, cwd: "/tmp/project", transcriptPath: fixture.transcript.path
        )
        #expect(unchanged.newMessages.isEmpty)
    }

    @Test("Keeps legacy event-message transcripts readable")
    func readsLegacyMessages() async throws {
        let fixture = try makeFixture([
            event(role: "user", text: "Run the checks", second: 1),
            event(role: "assistant", text: "Checks passed", second: 2)
        ])
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let messages = await ConversationParser().parseFullConversation(
            sessionId: fixture.id, cwd: "/tmp/project", transcriptPath: fixture.transcript.path
        )
        #expect(messages.map(\.textContent) == ["Run the checks", "Checks passed"])
    }

    @Test("Does not repeat mirrored legacy messages across incremental reads", arguments: [true, false])
    func deduplicatesMirrors(eventFirst: Bool) async throws {
        let legacy = event(role: "assistant", text: "Checks passed", second: 1)
        let modern = response(role: "assistant", text: "Checks passed", second: 1)
        let fixture = try makeFixture([eventFirst ? legacy : modern])
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let parser = ConversationParser()
        _ = await parser.parseFullConversation(
            sessionId: fixture.id, cwd: "/tmp/project", transcriptPath: fixture.transcript.path
        )
        try append(eventFirst ? modern : legacy, to: fixture.transcript)
        // Repeating the same text in a later turn is a separate message.
        try append(response(role: "assistant", text: "Checks passed", second: 5), to: fixture.transcript)

        let update = await parser.parseIncremental(
            sessionId: fixture.id, cwd: "/tmp/project", transcriptPath: fixture.transcript.path
        )
        #expect(update.newMessages.count == 1)
        #expect(update.allMessages.count == 2)
    }

    @Test("Session history loading populates chat items from a Codex rollout")
    func loadsSessionHistory() async throws {
        let fixture = try makeFixture([response(role: "user", text: "Show the session history", second: 1)])
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let session = SessionState(
            sessionId: fixture.id, cwd: "/tmp/project", source: .codex,
            transcriptPath: fixture.transcript.path, phase: .waitingForInput
        )
        let store = SessionStore(initialSessions: [session])

        await store.process(.loadHistory(sessionId: fixture.id, cwd: session.cwd))

        let loaded = await store.session(for: fixture.id)
        #expect(loaded?.chatItems.map(\.type) == [.user("Show the session history")])
        #expect(loaded?.lastMessage == "Show the session history")
    }

    private func response(role: String, text: String, second: Int, kind: String? = nil) -> [String: Any] {
        var payload: [String: Any] = [
            "type": "message", "role": role,
            "content": [["type": role == "assistant" ? "output_text" : "input_text", "text": text]]
        ]
        if let kind {
            payload["internal_chat_message_metadata_passthrough"] = ["content_item_kinds": [kind]]
        }
        return [
            "timestamp": String(format: "2026-09-11T00:00:%02d.000Z", second),
            "type": "response_item",
            "payload": payload
        ]
    }

    private func event(role: String, text: String, second: Int) -> [String: Any] {
        [
            "timestamp": String(format: "2026-09-11T00:00:%02d.000Z", second),
            "type": "event_msg",
            "payload": ["type": role == "assistant" ? "agent_message" : "user_message", "message": text]
        ]
    }

    private func makeFixture(_ records: [[String: Any]]) throws -> (root: URL, transcript: URL, id: String) {
        let id = UUID().uuidString
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(id)
        let directory = root.appendingPathComponent(".codex/sessions")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let transcript = directory.appendingPathComponent("rollout-\(id).jsonl")
        FileManager.default.createFile(atPath: transcript.path, contents: nil)
        for record in records {
            try append(record, to: transcript)
        }
        return (root, transcript, id)
    }

    private func append(_ record: [String: Any], to transcript: URL) throws {
        let handle = try FileHandle(forWritingTo: transcript)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: JSONSerialization.data(withJSONObject: record) + Data("\n".utf8))
    }
}
