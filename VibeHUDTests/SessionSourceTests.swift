import Testing
@testable import vibe_hud

@Suite("Session source mapping")
struct SessionSourceTests {
    @Test(
        "Maps hook source aliases",
        arguments: [
            ("claude", SessionSource.claude),
            ("claudecode", SessionSource.claude),
            ("codex", SessionSource.codex),
            ("cursor", SessionSource.cursor),
            ("copilot", SessionSource.copilot),
            ("githubcopilot", SessionSource.copilot),
            ("vscodeagent", SessionSource.copilot),
            ("pi", SessionSource.pi),
            ("opencode", SessionSource.opencode),
        ]
    )
    func mapsSourceAlias(input: String, expected: SessionSource) {
        #expect(SessionSource(rawSource: input) == expected)
    }

    @Test("Infers Codex from its transcript path")
    func infersCodexFromTranscript() {
        let source = SessionSource(
            rawSource: nil,
            transcriptPath: "/Users/test/.codex/sessions/rollout.jsonl"
        )

        #expect(source == .codex)
    }
}
