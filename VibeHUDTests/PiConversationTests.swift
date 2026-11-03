import Foundation
import Testing
@testable import vibe_hud

@Suite("Pi conversation parsing", .serialized)
@MainActor
struct PiConversationTests {
    @Test("Finds a Pi transcript by its prefixed session ID")
    func findsTranscript() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vibehud-pi-path-\(UUID().uuidString)")
        let project = root.appendingPathComponent("--Users-jack-Documents-GitHub-pi-work--")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let expected = project.appendingPathComponent(
            "2026-11-03T07-55-39-303Z_01a1a068-19a6-7073-a678-cdfce723c9f7.jsonl"
        )
        try Data().write(to: expected)

        let result = PiPaths.transcriptFile(
            sessionId: "pi-01a1a068-19a6-7073-a678-cdfce723c9f7",
            cwd: "/Users/jack/Documents/GitHub/pi-work",
            sessionsDirectory: root
        )

        #expect(result?.standardizedFileURL == expected.standardizedFileURL)
    }

    @Test("Uses Pi session name and real conversation activity")
    func parsesConversationInfo() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.url) }

        let info = await ConversationParser.shared.parse(
            sessionId: fixture.sessionId,
            cwd: "/Users/jack/Documents/GitHub/pi-work",
            transcriptPath: fixture.url.path
        )

        #expect(info.summary == "分析当前项目中的未提交代码")
        #expect(info.firstUserMessage == "请分析一下当前项目中有哪些代码没提交。")
        #expect(info.lastMessage == "已完成分析，共有 3 个修改文件。")
        #expect(info.lastMessageRole == "assistant")
        #expect(info.usage.inputTokens == 120)
        #expect(info.usage.outputTokens == 35)
    }

    @Test("Parses Pi messages and completed tools for chat")
    func parsesFullConversation() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.url) }

        let messages = await ConversationParser.shared.parseFullConversation(
            sessionId: fixture.sessionId,
            cwd: "/Users/jack/Documents/GitHub/pi-work",
            transcriptPath: fixture.url.path
        )
        let completed = await ConversationParser.shared.completedToolIds(for: fixture.sessionId)

        #expect(messages.map(\.role) == [.user, .assistant, .assistant])
        #expect(messages.first?.textContent == "请分析一下当前项目中有哪些代码没提交。")
        #expect(messages[1].content.contains { block in
            if case .toolUse(let tool) = block {
                return tool.id == "call-1" && tool.name == "bash"
            }
            return false
        })
        #expect(messages.last?.textContent == "已完成分析，共有 3 个修改文件。")
        #expect(completed.contains("call-1"))
    }

    private func makeFixture() throws -> (url: URL, sessionId: String) {
        let sessionId = "pi-test-\(UUID().uuidString)"
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vibehud-pi-fixture-\(UUID().uuidString)/.pi/agent/sessions/project")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(sessionId).jsonl")
        let records = [
            #"{"type":"session","version":3,"id":"test","timestamp":"2026-11-03T07:55:39.303Z","cwd":"/Users/jack/Documents/GitHub/pi-work"}"#,
            #"{"type":"message","id":"user-1","timestamp":"2026-11-03T07:55:50.774Z","message":{"role":"user","content":[{"type":"text","text":"请分析一下当前项目中有哪些代码没提交。"}],"timestamp":1793692550770}}"#,
            #"{"type":"message","id":"assistant-1","timestamp":"2026-11-03T07:55:54.803Z","message":{"role":"assistant","content":[{"type":"thinking","thinking":"Checking"},{"type":"toolCall","id":"call-1","name":"bash","arguments":{"command":"git status --short"}}],"usage":{"input":120,"output":20,"cacheRead":80,"cacheWrite":0}}}"#,
            #"{"type":"message","id":"tool-1","timestamp":"2026-11-03T07:55:54.907Z","message":{"role":"toolResult","toolCallId":"call-1","toolName":"bash","content":[{"type":"text","text":" M file.swift"}],"isError":false}}"#,
            #"{"type":"session_info","id":"info-1","timestamp":"2026-11-03T07:56:19.640Z","name":"分析当前项目中的未提交代码"}"#,
            #"{"type":"message","id":"assistant-2","timestamp":"2026-11-03T07:56:20.000Z","message":{"role":"assistant","content":[{"type":"text","text":"已完成分析，共有 3 个修改文件。"}],"usage":{"input":0,"output":15,"cacheRead":0,"cacheWrite":0}}}"#,
        ]
        try (records.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        return (url, sessionId)
    }
}
