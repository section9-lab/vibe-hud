//
//  HookInstaller.swift
//  VibeHUD
//
//  Installs lifecycle-only hooks. No message, tool input, or permission data is collected.
//

import Foundation

struct HookInstaller {
    static func installIfNeeded() {
        try? FileManager.default.createDirectory(
            at: ClaudePaths.hooksDir,
            withIntermediateDirectories: true
        )
        installScript(
            resource: "vibe-hud-state",
            to: ClaudePaths.hooksDir.appendingPathComponent("vibe-hud-state.py")
        )
        removeLegacyBridgeFiles()
        updateClaudeHooks(at: ClaudePaths.settingsFile)
        installCodexHooks()
        installOpenCodePlugin()
    }

    static func isInstalled() -> Bool {
        isInstalled(at: ClaudePaths.settingsFile)
            || isInstalled(at: CodexPaths.hooksFile)
            || isInstalledOpenCode(at: OpenCodePaths.configFile)
    }

    static func uninstall() {
        try? FileManager.default.removeItem(
            at: ClaudePaths.hooksDir.appendingPathComponent("vibe-hud-state.py")
        )
        try? FileManager.default.removeItem(at: CodexPaths.hookScriptPath)
        try? FileManager.default.removeItem(at: OpenCodePaths.pluginFile)
        removeLegacyBridgeFiles()
        removeHooks(at: ClaudePaths.settingsFile)
        removeHooks(at: CodexPaths.hooksFile)
        removeOpenCodePlugin(at: OpenCodePaths.configFile)
    }

    private static func installCodexHooks() {
        try? FileManager.default.createDirectory(
            at: CodexPaths.hooksDir,
            withIntermediateDirectories: true
        )
        installScript(resource: "vibe-hud-state", to: CodexPaths.hookScriptPath)

        var json = loadJSON(at: CodexPaths.hooksFile)
        var hooks = cleanVibeHUDHooks(in: json["hooks"] as? [String: Any] ?? [:])
        let command = "\(pythonExecutable) \(CodexPaths.hookScriptShellPath) --source codex"
        let entry: [String: Any] = [
            "hooks": [[
                "type": "command",
                "command": command,
                "timeout": 5,
            ]]
        ]

        for event in ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop"] {
            var entries = hooks[event] as? [[String: Any]] ?? []
            entries.append(entry)
            hooks[event] = entries
        }

        json["hooks"] = hooks
        writeJSON(json, to: CodexPaths.hooksFile)
    }

    private static func installOpenCodePlugin() {
        try? FileManager.default.createDirectory(
            at: OpenCodePaths.pluginDir,
            withIntermediateDirectories: true
        )
        installScript(resource: "vibe-hud", to: OpenCodePaths.pluginFile, extension: "js")

        var json = loadJSON(
            at: OpenCodePaths.configFile,
            fallback: ["$schema": "https://opencode.ai/config.json"]
        )
        var plugins = json["plugin"] as? [String] ?? []
        plugins.removeAll(where: isVibeHUDOpenCodePlugin)
        plugins.append(OpenCodePaths.pluginFileURLString)
        json["plugin"] = plugins
        writeJSON(json, to: OpenCodePaths.configFile)
    }

    private static func updateClaudeHooks(at settingsURL: URL) {
        var json = loadJSON(at: settingsURL)
        var hooks = cleanVibeHUDHooks(in: json["hooks"] as? [String: Any] ?? [:])
        let command = "\(pythonExecutable) \(ClaudePaths.hookScriptShellPath) --source claude"
        let commandHook: [String: Any] = [
            "type": "command",
            "command": command,
            "timeout": 5,
        ]

        func add(_ event: String, matcher: String? = nil) {
            var eventEntries = hooks[event] as? [[String: Any]] ?? []
            var entry: [String: Any] = ["hooks": [commandHook]]
            if let matcher {
                entry["matcher"] = matcher
            }
            eventEntries.append(entry)
            hooks[event] = eventEntries
        }

        add("SessionStart", matcher: "startup|resume|clear")
        add("UserPromptSubmit")
        add("PreToolUse", matcher: "*")
        add("PostToolUse", matcher: "*")
        add("PostToolUseFailure", matcher: "*")
        add("SubagentStart")
        add("SubagentStop")
        // Claude's Notification matcher does not filter on notification_type,
        // so subscribe broadly and let the hook script drop everything but idle_prompt.
        add("Notification", matcher: "*")
        add("Stop")
        add("StopFailure")
        add("SessionEnd")
        add("PreCompact", matcher: "manual|auto")
        add("PostCompact", matcher: "manual|auto")

        json["hooks"] = hooks
        writeJSON(json, to: settingsURL)
    }

    private static func cleanVibeHUDHooks(in hooks: [String: Any]) -> [String: Any] {
        var result = hooks
        for (event, value) in hooks {
            guard let entries = value as? [[String: Any]] else { continue }
            let cleaned = entries.compactMap(removingVibeHUDHooks)
            if cleaned.isEmpty {
                result.removeValue(forKey: event)
            } else {
                result[event] = cleaned
            }
        }
        return result
    }

    private static func removeHooks(at url: URL) {
        var json = loadJSON(at: url)
        guard let hooks = json["hooks"] as? [String: Any] else { return }
        let cleaned = cleanVibeHUDHooks(in: hooks)
        if cleaned.isEmpty {
            json.removeValue(forKey: "hooks")
        } else {
            json["hooks"] = cleaned
        }
        writeJSON(json, to: url)
    }

    private static func removeOpenCodePlugin(at url: URL) {
        var json = loadJSON(at: url)
        var plugins = json["plugin"] as? [String] ?? []
        plugins.removeAll(where: isVibeHUDOpenCodePlugin)
        if plugins.isEmpty {
            json.removeValue(forKey: "plugin")
        } else {
            json["plugin"] = plugins
        }
        writeJSON(json, to: url)
    }

    private static func isInstalled(at url: URL) -> Bool {
        guard let hooks = loadJSON(at: url)["hooks"] as? [String: Any] else { return false }
        return hooks.values.contains { value in
            guard let entries = value as? [[String: Any]] else { return false }
            return entries.contains { entry in
                (entry["hooks"] as? [[String: Any]])?.contains(where: isVibeHUDHook) == true
            }
        }
    }

    private static func isInstalledOpenCode(at url: URL) -> Bool {
        let plugins = loadJSON(at: url)["plugin"] as? [String] ?? []
        return plugins.contains(where: isVibeHUDOpenCodePlugin)
    }

    private static func installScript(
        resource: String,
        to destination: URL,
        extension ext: String = "py"
    ) {
        guard let bundled = Bundle.main.url(forResource: resource, withExtension: ext) else {
            return
        }
        try? FileManager.default.removeItem(at: destination)
        try? FileManager.default.copyItem(at: bundled, to: destination)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: destination.path
        )
    }

    private static func removeLegacyBridgeFiles() {
        let legacyFiles = [
            ClaudePaths.hooksDir.appendingPathComponent("vibe-hud-bridge.py"),
            ClaudePaths.hooksDir.appendingPathComponent("vibe-hud-tty-bridge.py"),
            ClaudePaths.claudeDir.appendingPathComponent("bin/claude-vibehud"),
        ]
        for file in legacyFiles {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private static func loadJSON(
        at url: URL,
        fallback: [String: Any] = [:]
    ) -> [String: Any] {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return fallback
        }
        return json
    }

    private static func writeJSON(_ json: [String: Any], to url: URL) {
        guard let data = try? JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys]
        ) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static var pythonExecutable: String {
        let candidates = [
            "/usr/bin/python3",
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
        ]
        return candidates.first {
            FileManager.default.isExecutableFile(atPath: $0)
        } ?? "python3"
    }

    nonisolated private static func removingVibeHUDHooks(
        from entry: [String: Any]
    ) -> [String: Any]? {
        guard var entryHooks = entry["hooks"] as? [[String: Any]] else { return entry }
        entryHooks.removeAll(where: isVibeHUDHook)
        guard !entryHooks.isEmpty else { return nil }
        var updated = entry
        updated["hooks"] = entryHooks
        return updated
    }

    nonisolated private static func isVibeHUDHook(_ hook: [String: Any]) -> Bool {
        (hook["command"] as? String)?.contains("vibe-hud-state.py") == true
    }

    nonisolated private static func isVibeHUDOpenCodePlugin(_ plugin: String) -> Bool {
        plugin == OpenCodePaths.pluginFileURLString || plugin.contains("/plugin/vibe-hud.js")
    }
}
