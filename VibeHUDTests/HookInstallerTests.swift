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
        for event in HookInstaller.copilotEvents {
            let entries = try #require(hooks[event] as? [[String: Any]])
            #expect(entries.allSatisfy { $0["type"] as? String == "command" })
        }
        let permission = try #require((hooks["permissionRequest"] as? [[String: Any]])?.first)
        #expect(permission["timeoutSec"] as? Int == 360)
    }

    @Test("Codex allows time for human approvals and bounds session shutdown")
    func installsCodexTimeouts() throws {
        let url = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try writeJSON(["hooks": ["PermissionRequest": [["hooks": [["type": "command", "command": "echo keep-me"]]]]]], to: url)
        HookInstaller.updateCodexHooks(at: url)
        let hooks = try #require(readJSON(at: url)["hooks"] as? [String: Any])
        for (event, timeout) in [("PermissionRequest", 360), ("SessionEnd", 3), ("PreToolUse", 10)] {
            let groups = try #require(hooks[event] as? [[String: Any]])
            let entries = groups.flatMap { $0["hooks"] as? [[String: Any]] ?? [] }
            let managed = try #require(entries.first { ($0["command"] as? String)?.contains("vibe-hud-state.py") == true })
            #expect(managed["timeout"] as? Int == timeout)
            if event == "PermissionRequest" {
                #expect(entries.contains { $0["command"] as? String == "echo keep-me" })
            }
        }
    }

    @Test("Updating shared Copilot hooks removes duplicate legacy VS Code registrations")
    func removesDuplicateCopilotRegistrations() throws {
        let url = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try writeJSON([
            "hooks": [
                "PreToolUse": [
                    ["command": "echo keep-me"],
                    ["command": "python3 /tmp/vibe-hud-state.py --source vscodeagent --event PreToolUse"],
                ],
                "PostToolUse": [
                    ["command": "python3 /tmp/vibe-hud-state.py --source vscodeagent --event PostToolUse"],
                ],
            ]
        ], to: url)

        HookInstaller.updateCommandHooks(
            at: url,
            events: HookInstaller.copilotEvents,
            command: "python3 /tmp/vibe-hud-state.py --source copilot",
            includesVersion: true
        )

        let hooks = try #require(readJSON(at: url)["hooks"] as? [String: Any])
        let legacyPreToolUse = try #require(hooks["PreToolUse"] as? [[String: Any]])
        #expect(legacyPreToolUse.compactMap { $0["command"] as? String } == ["echo keep-me"])
        #expect(hooks["PostToolUse"] == nil)
        #expect(Set(hooks.keys) == Set(HookInstaller.copilotEvents + ["PreToolUse"]))
    }

    @Test("Installs WorkBuddy hooks without removing other integrations")
    func installsWorkBuddyHooks() throws {
        let url = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try writeJSON([
            "hooks": [
                "SessionStart": [
                    ["hooks": [["type": "command", "command": "echo keep-me"]]],
                    ["hooks": [["type": "command", "command": "python3 old/vibe-hud-state.py --source workbuddy"]]],
                ]
            ]
        ], to: url)

        HookInstaller.updateWorkBuddySettings(
            at: url,
            script: URL(fileURLWithPath: "/tmp/vibe-hud-state.py")
        )

        let json = try readJSON(at: url)
        let hooks = try #require(json["hooks"] as? [String: Any])
        #expect(Set(hooks.keys) == Set(HookInstaller.workBuddyEvents))
        let sessionStart = try #require(hooks["SessionStart"] as? [[String: Any]])
        let commands = sessionStart.flatMap { group in
            (group["hooks"] as? [[String: Any]])?.compactMap { $0["command"] as? String } ?? []
        }
        #expect(commands == [
            "echo keep-me",
            "python3 '/tmp/vibe-hud-state.py' --source workbuddy --event SessionStart",
        ])
        for event in HookInstaller.workBuddyEvents {
            let groups = try #require(hooks[event] as? [[String: Any]])
            let managed = try #require(groups.last?["hooks"] as? [[String: Any]])
            #expect(managed.first?["command"] as? String
                == "python3 '/tmp/vibe-hud-state.py' --source workbuddy --event \(event)")
        }
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
