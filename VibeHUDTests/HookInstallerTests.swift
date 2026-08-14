import Foundation
import Testing
@testable import vibe_hud

@Suite("Hook installer", .serialized)
struct HookInstallerTests {
    @Test("Installs Cursor lifecycle hooks without removing user hooks")
    func installsCursorHooks() throws {
        let url = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try writeJSON([
            "hooks": [
                "sessionStart": [
                    ["command": "echo keep-me"],
                    ["command": "python3 old/vibe-hud-state.py --source cursor"],
                ]
            ]
        ], to: url)

        HookInstaller.updateCommandHooks(
            at: url,
            events: HookInstaller.cursorEvents,
            command: "python3 /tmp/vibe-hud-state.py --source cursor"
        )

        let json = try readJSON(at: url)
        let hooks = try #require(json["hooks"] as? [String: Any])
        #expect(Set(hooks.keys) == Set(HookInstaller.cursorEvents))
        let sessionStart = try #require(hooks["sessionStart"] as? [[String: Any]])
        #expect(sessionStart.compactMap { $0["command"] as? String } == [
            "echo keep-me",
            "python3 /tmp/vibe-hud-state.py --source cursor --event sessionStart",
        ])
    }

    @Test("Installs Copilot hooks with the required schema version")
    func installsCopilotHooks() throws {
        let url = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: url) }

        HookInstaller.updateCommandHooks(
            at: url,
            events: HookInstaller.copilotEvents,
            command: "python3 /tmp/vibe-hud-state.py --source copilot",
            includesVersion: true
        )

        let json = try readJSON(at: url)
        #expect(json["version"] as? Int == 1)
        let hooks = try #require(json["hooks"] as? [String: Any])
        #expect(Set(hooks.keys) == Set(HookInstaller.copilotEvents))
    }

    @Test("Declares distinct VS Code Agent lifecycle events")
    func declaresVSCodeAgentEvents() {
        #expect(HookInstaller.vscodeAgentEvents.contains("UserPromptSubmit"))
        #expect(HookInstaller.vscodeAgentEvents.contains("PermissionRequest"))
        #expect(HookInstaller.vscodeAgentEvents.contains("PostToolUseFailure"))
        #expect(HookInstaller.vscodeAgentEvents.contains("SessionEnd"))
    }
}

private func temporaryFileURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("json")
}

private func writeJSON(_ json: [String: Any], to url: URL) throws {
    try JSONSerialization.data(withJSONObject: json).write(to: url)
}

private func readJSON(at url: URL) throws -> [String: Any] {
    let data = try Data(contentsOf: url)
    return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}
