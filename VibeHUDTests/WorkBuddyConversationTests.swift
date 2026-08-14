import Foundation
import Testing
@testable import vibe_hud

@MainActor
@Suite("WorkBuddy conversation parsing", .serialized)
struct WorkBuddyConversationTests {
    @Test("Parses WorkBuddy title and latest activity")
    func parsesConversationInfo() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let parser = ConversationParser()

        let info = await parser.parse(
            sessionId: "workbuddy-session",
            cwd: "/tmp/project",
            transcriptPath: fixture.transcript.path
        )

        #expect(info.summary == "Fix WorkBuddy status")
        #expect(info.firstUserMessage == "Show every active session")
        #expect(info.lastMessage == "pwd")
        #expect(info.lastMessageRole == "tool")
        #expect(info.lastToolName == "Bash")
    }

    @Test("Parses WorkBuddy messages, reasoning, and completed tools")
    func parsesFullConversation() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let parser = ConversationParser()

        let messages = await parser.parseFullConversation(
            sessionId: "workbuddy-session",
            cwd: "/tmp/project",
            transcriptPath: fixture.transcript.path
        )

        #expect(messages.count == 4)
        guard messages.count == 4 else {
            Issue.record("Expected four WorkBuddy messages")
            return
        }
        #expect(messages[0].role == .user)
        #expect(messages[0].textContent == "Show every active session")
        #expect(messages[1].content == [.thinking("Inspect the hook payload")])
        #expect(messages[2].textContent == "I am checking it now")
        guard case .toolUse(let tool) = messages[3].content.first else {
            Issue.record("Expected a WorkBuddy tool call")
            return
        }
        #expect(tool.id == "call-1")
        #expect(tool.name == "Bash")
        #expect(tool.input["command"] == "pwd")
        #expect(await parser.completedToolIds(for: "workbuddy-session") == ["call-1"])
        #expect(await parser.toolResults(for: "workbuddy-session")["call-1"]?.content == "/tmp/project")
    }
}

private func makeFixture() throws -> (root: URL, transcript: URL) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let directory = root.appendingPathComponent(".workbuddy/projects/project")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let transcript = directory.appendingPathComponent("workbuddy-session.jsonl")
    let content = """
    {"timestamp":1760000000000,"type":"ai-title","aiTitle":"Fix WorkBuddy status","sessionId":"workbuddy-session","cwd":"/tmp/project"}
    {"id":"user-1","timestamp":1760000001000,"type":"message","role":"user","content":[{"type":"input_text","text":"Injected context"},{"type":"input_text","text":"Show every active session"}],"sessionId":"workbuddy-session","cwd":"/tmp/project"}
    {"id":"reasoning-1","timestamp":1760000002000,"type":"reasoning","content":[],"rawContent":[{"type":"reasoning_text","text":"Inspect the hook payload"}],"sessionId":"workbuddy-session","cwd":"/tmp/project"}
    {"id":"assistant-1","timestamp":1760000003000,"type":"message","role":"assistant","status":"completed","content":[{"type":"output_text","text":"I am checking it now"}],"sessionId":"workbuddy-session","cwd":"/tmp/project"}
    {"id":"tool-1","timestamp":1760000004000,"type":"function_call","callId":"call-1","name":"Bash","arguments":"{\\\"command\\\":\\\"pwd\\\"}","sessionId":"workbuddy-session","cwd":"/tmp/project"}
    {"id":"result-1","timestamp":1760000005000,"type":"function_call_result","callId":"call-1","name":"Bash","status":"completed","output":{"type":"text","text":"/tmp/project"},"sessionId":"workbuddy-session","cwd":"/tmp/project"}
    """
    try content.write(to: transcript, atomically: true, encoding: .utf8)
    return (root, transcript)
}
