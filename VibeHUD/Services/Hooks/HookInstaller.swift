//
//  HookInstaller.swift
//  VibeHUD
//
//  Auto-installs Claude Code hooks on app launch
//

import Foundation

enum HookAgent: CaseIterable {
    case claude
    case codex
    case cursor
    case githubCopilot
    case pi
    case openCode
}

struct HookInstaller {

    /// Refresh hooks that were already enabled by the user.
    static func installIfNeeded() {
        for agent in HookAgent.allCases where isInstalled(agent) {
            install(agent)
        }
    }

    static func install(_ agent: HookAgent) {
        switch agent {
        case .claude:
            installClaudeHooksIfNeeded()
        case .codex:
            installCodexHooksIfNeeded()
        case .cursor:
            installCursorHooksIfNeeded()
        case .githubCopilot:
            installGitHubCopilotHooksIfNeeded()
        case .pi:
            installPiExtensionIfNeeded()
        case .openCode:
            installOpenCodeHooksIfNeeded()
        }
    }

    static func uninstall(_ agent: HookAgent) {
        switch agent {
        case .claude:
            uninstallClaudeHooks()
        case .codex:
            removeHooks(at: CodexPaths.hooksFile)
            // Keep the script for hooks already loaded by an active Codex session.
            // With its configuration removed, no future session invokes it.
        case .cursor:
            try? FileManager.default.removeItem(at: CursorPaths.hookScriptPath)
            removeCommandHooks(at: CursorPaths.hooksFile)
        case .githubCopilot:
            try? FileManager.default.removeItem(at: CopilotPaths.hookScriptPath)
            try? FileManager.default.removeItem(at: CopilotPaths.hookFile)
        case .pi:
            try? FileManager.default.removeItem(at: PiPaths.extensionFile)
        case .openCode:
            try? FileManager.default.removeItem(at: OpenCodePaths.pluginFile)
            removeOpenCodePlugin(at: OpenCodePaths.configFile)
        }
    }

    static func isInstalled(_ agent: HookAgent) -> Bool {
        switch agent {
        case .claude:
            isInstalled(at: ClaudePaths.settingsFile)
        case .codex:
            isInstalled(at: CodexPaths.hooksFile)
        case .cursor:
            isInstalledCommandHooks(at: CursorPaths.hooksFile, script: CursorPaths.hookScriptPath)
        case .githubCopilot:
            isInstalledCommandHooks(at: CopilotPaths.hookFile, script: CopilotPaths.hookScriptPath)
        case .pi:
            FileManager.default.fileExists(atPath: PiPaths.extensionFile.path)
        case .openCode:
            isInstalledOpenCode(at: OpenCodePaths.configFile)
        }
    }

    private static func installClaudeHooksIfNeeded() {
        let hooksDir = ClaudePaths.hooksDir
        let pythonScript = hooksDir.appendingPathComponent("vibe-hud-state.py")

        try? FileManager.default.createDirectory(
            at: hooksDir,
            withIntermediateDirectories: true
        )

        installScript(resource: "vibe-hud-state", to: pythonScript)
        removeLegacyClaudeInputBridge()

        updateSettings(at: ClaudePaths.settingsFile)
    }

    private static func installCodexHooksIfNeeded() {
        try? FileManager.default.createDirectory(
            at: CodexPaths.hooksDir,
            withIntermediateDirectories: true
        )

        installScript(resource: "vibe-hud-state", to: CodexPaths.hookScriptPath)
        updateCodexHooks(at: CodexPaths.hooksFile)
    }

    private static func installOpenCodeHooksIfNeeded() {
        try? FileManager.default.createDirectory(
            at: OpenCodePaths.pluginDir,
            withIntermediateDirectories: true
        )

        installScript(resource: "vibe-hud", to: OpenCodePaths.pluginFile, extension: "js")
        updateOpenCodeConfig(at: OpenCodePaths.configFile)
    }

    private static func installCursorHooksIfNeeded() {
        try? FileManager.default.createDirectory(
            at: CursorPaths.hooksDir,
            withIntermediateDirectories: true
        )

        installScript(resource: "vibe-hud-state", to: CursorPaths.hookScriptPath)
        updateCommandHooks(
            at: CursorPaths.hooksFile,
            events: ["sessionStart", "beforeSubmitPrompt", "preToolUse", "postToolUse", "stop"],
            command: "python3 \(shellQuote(CursorPaths.hookScriptPath.path)) --source cursor"
        )
    }

    private static func installGitHubCopilotHooksIfNeeded() {
        try? FileManager.default.createDirectory(
            at: CopilotPaths.hooksDir,
            withIntermediateDirectories: true
        )

        installScript(resource: "vibe-hud-state", to: CopilotPaths.hookScriptPath)
        updateCommandHooks(
            at: CopilotPaths.hookFile,
            events: ["sessionStart", "preToolUse", "postToolUse", "agentStop"],
            command: "python3 \(shellQuote(CopilotPaths.hookScriptPath.path)) --source copilot",
            includesVersion: true
        )
    }

    private static func installPiExtensionIfNeeded() {
        try? FileManager.default.createDirectory(
            at: PiPaths.extensionsDir,
            withIntermediateDirectories: true
        )
        try? piExtension.write(to: PiPaths.extensionFile, atomically: true, encoding: .utf8)
    }

    private static func updateSettings(at settingsURL: URL) {
        var json: [String: Any] = [:]
        if let data = try? Data(contentsOf: settingsURL),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            json = existing
        }

        let python = detectPython()
        let command = "\(python) \(ClaudePaths.hookScriptShellPath) --source claude"
        let hookEntry: [[String: Any]] = [["type": "command", "command": command]]
        let hookEntryWithTimeout: [[String: Any]] = [["type": "command", "command": command, "timeout": 86400]]
        let withMatcher: [[String: Any]] = [["matcher": "*", "hooks": hookEntry]]
        let withMatcherAndTimeout: [[String: Any]] = [["matcher": "*", "hooks": hookEntryWithTimeout]]
        let withoutMatcher: [[String: Any]] = [["hooks": hookEntry]]
        let preCompactConfig: [[String: Any]] = [
            ["matcher": "auto", "hooks": hookEntry],
            ["matcher": "manual", "hooks": hookEntry]
        ]

        var hooks = json["hooks"] as? [String: Any] ?? [:]

        let hookEvents: [(String, [[String: Any]])] = [
            ("UserPromptSubmit", withoutMatcher),
            ("PreToolUse", withMatcher),
            ("PostToolUse", withMatcher),
            // PostToolUseFailure fires when a tool errored or was interrupted — we
            // currently miss these signals entirely (v2.0.x+)
            ("PostToolUseFailure", withMatcher),
            ("PermissionRequest", withMatcherAndTimeout),
            // PermissionDenied surfaces auto-mode classifier denials (v2.1.88+)
            ("PermissionDenied", withMatcher),
            ("Notification", withMatcher),
            ("Stop", withoutMatcher),
            // StopFailure fires on API errors (rate limit, auth, billing) — lets
            // us show the failure in the notch instead of appearing stuck (v2.1.78+)
            ("StopFailure", withoutMatcher),
            // SubagentStart pairs with existing SubagentStop (v2.0.43+)
            ("SubagentStart", withoutMatcher),
            ("SubagentStop", withoutMatcher),
            ("SessionStart", withoutMatcher),
            ("SessionEnd", withoutMatcher),
            ("PreCompact", preCompactConfig),
            // PostCompact pairs with PreCompact so the UI can exit the
            // .compacting phase cleanly (v2.1.76+)
            ("PostCompact", preCompactConfig),
        ]

        for (event, config) in hookEvents {
            let existingEvent = hooks[event] as? [[String: Any]] ?? []
            let cleanedEvent = existingEvent.compactMap { removingVibeHUDHooks(from: $0) }
            hooks[event] = cleanedEvent + config
        }

        json["hooks"] = hooks

        if let data = try? JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys]
        ) {
            try? data.write(to: settingsURL)
        }
    }

    private static func updateCodexHooks(at hooksURL: URL) {
        var json: [String: Any] = [:]
        if let data = try? Data(contentsOf: hooksURL),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            json = existing
        }

        let python = detectPython()
        let command = "\(python) \(CodexPaths.hookScriptShellPath) --source codex"
        let hookEntry: [[String: Any]] = [[
            "type": "command",
            "command": command,
            "timeout": 10
        ]]
        let vibeHUDEventEntry: [String: Any] = ["hooks": hookEntry]

        var hooks = json["hooks"] as? [String: Any] ?? [:]
        let hookEvents = ["SessionStart", "UserPromptSubmit", "Stop", "PreToolUse", "PostToolUse"]

        for event in hookEvents {
            let existingEvent = hooks[event] as? [[String: Any]] ?? []
            let cleanedEvent = existingEvent.compactMap { removingVibeHUDHooks(from: $0) }
            hooks[event] = cleanedEvent + [vibeHUDEventEntry]
        }

        json["hooks"] = hooks

        if let data = try? JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys]
        ) {
            try? data.write(to: hooksURL)
        }
    }

    private static func updateOpenCodeConfig(at configURL: URL) {
        var json: [String: Any] = [
            "$schema": "https://opencode.ai/config.json"
        ]
        if let data = try? Data(contentsOf: configURL),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            json = existing
        }

        var plugins = json["plugin"] as? [String] ?? []
        plugins.removeAll(where: isVibeHUDOpenCodePlugin)
        plugins.append(OpenCodePaths.pluginFileURLString)
        json["plugin"] = plugins

        if let data = try? JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys]
        ) {
            try? data.write(to: configURL)
        }
    }

    /// Check if hooks are currently installed
    static func isInstalled() -> Bool {
        HookAgent.allCases.contains { agent in
            isInstalled(agent)
        }
    }

    /// Uninstall hooks from settings.json and remove script
    static func uninstall() {
        for agent in HookAgent.allCases {
            uninstall(agent)
        }
    }

    private static func uninstallClaudeHooks() {
        let hooksDir = ClaudePaths.hooksDir
        let pythonScript = hooksDir.appendingPathComponent("vibe-hud-state.py")
        let settings = ClaudePaths.settingsFile

        try? FileManager.default.removeItem(at: pythonScript)
        removeLegacyClaudeInputBridge()

        removeHooks(at: settings)
    }

    private static func removeLegacyClaudeInputBridge() {
        let legacyPaths = [
            ClaudePaths.hooksDir.appendingPathComponent("vibe-hud-bridge.py"),
            ClaudePaths.hooksDir.appendingPathComponent("vibe-hud-tty-bridge.py"),
            ClaudePaths.claudeDir.appendingPathComponent("bin/claude-vibehud"),
        ]
        for path in legacyPaths {
            try? FileManager.default.removeItem(at: path)
        }
    }

    private static func isInstalled(at url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else {
            return false
        }

        for (_, value) in hooks {
            if let entries = value as? [[String: Any]] {
                for entry in entries {
                    if let entryHooks = entry["hooks"] as? [[String: Any]] {
                        for hook in entryHooks {
                            if let cmd = hook["command"] as? String,
                               cmd.contains("vibe-hud-state.py") {
                                return true
                            }
                        }
                    }
                }
            }
        }
        return false
    }

    private static func removeHooks(at url: URL) {
        guard let data = try? Data(contentsOf: url),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var hooks = json["hooks"] as? [String: Any] else {
            return
        }

        for (event, value) in hooks {
            if var entries = value as? [[String: Any]] {
                entries = entries.compactMap { removingVibeHUDHooks(from: $0) }

                if entries.isEmpty {
                    hooks.removeValue(forKey: event)
                } else {
                    hooks[event] = entries
                }
            }
        }

        if hooks.isEmpty {
            json.removeValue(forKey: "hooks")
        } else {
            json["hooks"] = hooks
        }

        if let updated = try? JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys]
        ) {
            try? updated.write(to: url)
        }
    }

    private static func removeOpenCodePlugin(at url: URL) {
        guard let data = try? Data(contentsOf: url),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        var plugins = json["plugin"] as? [String] ?? []
        plugins.removeAll(where: isVibeHUDOpenCodePlugin)

        if plugins.isEmpty {
            json.removeValue(forKey: "plugin")
        } else {
            json["plugin"] = plugins
        }

        if let updated = try? JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys]
        ) {
            try? updated.write(to: url)
        }
    }

    private static func isInstalledOpenCode(at url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let plugins = json["plugin"] as? [String] else {
            return false
        }

        return plugins.contains(where: isVibeHUDOpenCodePlugin)
    }

    private static func updateCommandHooks(
        at url: URL,
        events: [String],
        command: String,
        includesVersion: Bool = false
    ) {
        var json: [String: Any] = includesVersion ? ["version": 1] : [:]
        if let data = try? Data(contentsOf: url),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            json = existing
        }

        if includesVersion {
            json["version"] = 1
        }

        var hooks = json["hooks"] as? [String: Any] ?? [:]
        for event in events {
            let existingEvent = hooks[event] as? [[String: Any]] ?? []
            let cleanedEvent = existingEvent.filter { !isManagedCommandHook($0) }
            hooks[event] = cleanedEvent + [["command": command]]
        }
        json["hooks"] = hooks

        if let data = try? JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys]
        ) {
            try? data.write(to: url)
        }
    }

    private static func isInstalledCommandHooks(at url: URL, script: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: script.path),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else {
            return false
        }

        return hooks.values.contains { value in
            guard let entries = value as? [[String: Any]] else { return false }
            return entries.contains { entry in
                let command = entry["command"] as? String ?? ""
                return command.contains(script.path)
            }
        }
    }

    private static func removeCommandHooks(at url: URL) {
        guard let data = try? Data(contentsOf: url),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var hooks = json["hooks"] as? [String: Any] else {
            return
        }

        for (event, value) in hooks {
            guard let entries = value as? [[String: Any]] else { continue }
            let cleaned = entries.filter { !isManagedCommandHook($0) }
            if cleaned.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = cleaned
            }
        }

        if hooks.isEmpty {
            json.removeValue(forKey: "hooks")
        } else {
            json["hooks"] = hooks
        }

        if let updated = try? JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys]
        ) {
            try? updated.write(to: url)
        }
    }

    private static func installScript(resource: String, to destination: URL, extension ext: String = "py") {
        guard let bundled = Bundle.main.url(forResource: resource, withExtension: ext) else { return }
        try? FileManager.default.removeItem(at: destination)
        try? FileManager.default.copyItem(at: bundled, to: destination)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
    }

    private static func shellQuote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func isManagedCommandHook(_ entry: [String: Any]) -> Bool {
        let command = entry["command"] as? String ?? ""
        return command.contains("vibe-hud-state.py") ||
            (command.contains("shellQuote(") &&
                (command.contains("--source cursor") || command.contains("--source copilot")))
    }

    private static let piExtension = """
    import net from "node:net"
    import type { ExtensionAPI } from "@earendil-works/pi-coding-agent"

    const socketPath = "/tmp/vibe-hud.sock"

    function send(state: Record<string, unknown>) {
      const socket = net.createConnection(socketPath)
      socket.on("connect", () => socket.end(JSON.stringify(state)))
      socket.on("error", () => socket.destroy())
    }

    function state(ctx: any, event: string, status: string) {
      return {
        session_id: ctx.sessionManager.getSessionFile() ?? `pi-${process.pid}`,
        cwd: ctx.cwd,
        event,
        status,
        source: "pi",
      }
    }

    export default function (pi: ExtensionAPI) {
      pi.on("session_start", (_event, ctx) => send(state(ctx, "SessionStart", "starting")))
      pi.on("agent_start", (_event, ctx) => send(state(ctx, "UserPromptSubmit", "processing")))
      pi.on("agent_settled", (_event, ctx) => send(state(ctx, "Stop", "waiting_for_input")))
      pi.on("tool_call", (event, ctx) => send({
        ...state(ctx, "PreToolUse", "running_tool"),
        tool: event.toolName,
        tool_input: event.input,
        tool_use_id: event.toolCallId,
      }))
      pi.on("tool_result", (event, ctx) => send({
        ...state(ctx, "PostToolUse", "processing"),
        tool: event.toolName,
        tool_input: event.input,
        tool_use_id: event.toolCallId,
      }))
    }
    """

    private static func detectPython() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["python3"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                return "python3"
            }
        } catch {}

        return "python"
    }

    nonisolated private static func removingVibeHUDHooks(from entry: [String: Any]) -> [String: Any]? {
        guard var entryHooks = entry["hooks"] as? [[String: Any]] else {
            return entry
        }

        entryHooks.removeAll(where: isVibeHUDHook)
        guard !entryHooks.isEmpty else { return nil }

        var updatedEntry = entry
        updatedEntry["hooks"] = entryHooks
        return updatedEntry
    }

    nonisolated private static func isVibeHUDHook(_ hook: [String: Any]) -> Bool {
        let cmd = hook["command"] as? String ?? ""
        return cmd.contains("vibe-hud-state.py")
    }

    nonisolated private static func isVibeHUDOpenCodePlugin(_ plugin: String) -> Bool {
        plugin == OpenCodePaths.pluginFileURLString || plugin.contains("/plugin/vibe-hud.js")
    }
}
