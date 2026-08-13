//
//  ClaudePaths.swift
//  VibeHUD
//
//  Single source of truth for all Claude config directory paths.
//  Resolves automatically via CLAUDE_CONFIG_DIR or filesystem detection.
//

import Foundation

enum ClaudePaths {

    /// Cached resolved directory to avoid filesystem checks on every access
    nonisolated(unsafe) private static var _cachedDir: URL?

    /// Guards reads/writes to _cachedDir — accessed from the main actor,
    /// the ConversationParser actor, and background watcher
    /// queues, so cross-thread access needs synchronization.
    nonisolated private static let cacheLock = NSLock()

    /// Root Claude config directory, resolved once and cached.
    ///
    /// Resolution order:
    /// 1. CLAUDE_CONFIG_DIR environment variable (if set and exists)
    /// 2. ~/.config/claude/ (new default since Claude Code v2.1.30+, if projects/ exists)
    /// 3. ~/.claude/ (legacy fallback)
    nonisolated static var claudeDir: URL {
        cacheLock.lock()
        if let cached = _cachedDir {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        // Resolve outside the lock — involves filesystem and settings reads
        // that shouldn't block other threads.
        let resolved = resolveClaudeDir()

        cacheLock.lock()
        // Another thread may have populated the cache while we were resolving;
        // prefer theirs for consistency, but either value is correct.
        if let existing = _cachedDir {
            cacheLock.unlock()
            return existing
        }
        _cachedDir = resolved
        cacheLock.unlock()
        return resolved
    }

    nonisolated static var hooksDir: URL {
        claudeDir.appendingPathComponent("hooks")
    }

    nonisolated static var binDir: URL {
        claudeDir.appendingPathComponent("bin")
    }

    nonisolated static var settingsFile: URL {
        claudeDir.appendingPathComponent("settings.json")
    }

    nonisolated static var projectsDir: URL {
        claudeDir.appendingPathComponent("projects")
    }

    /// Shell-safe absolute path for hook commands in settings.json.
    /// Absolute paths keep custom directories and ~/.config/claude working;
    /// quoting keeps paths with spaces from being split by the shell.
    nonisolated static var hookScriptShellPath: String {
        shellQuote(claudeDir.appendingPathComponent("hooks/vibe-hud-state.py").path)
    }

    nonisolated static var bridgeScriptPath: URL {
        hooksDir.appendingPathComponent("vibe-hud-bridge.py")
    }

    nonisolated static var bridgeLauncherPath: URL {
        binDir.appendingPathComponent("claude-vibehud")
    }

    nonisolated static var bridgeScriptShellPath: String {
        shellQuote(bridgeScriptPath.path)
    }

    nonisolated private static func resolveClaudeDir() -> URL {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser

        // 1. CLAUDE_CONFIG_DIR env var takes highest priority
        if let envDir = Foundation.ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"] {
            let expanded = (envDir as NSString).expandingTildeInPath
            let url = URL(fileURLWithPath: expanded)
            if fm.fileExists(atPath: url.path) {
                return url
            }
        }

        // 2. New default ~/.config/claude/ (if projects/ exists there)
        let newDefault = home.appendingPathComponent(".config/claude")
        if fm.fileExists(atPath: newDefault.appendingPathComponent("projects").path) {
            return newDefault
        }

        // 3. Legacy fallback
        return home.appendingPathComponent(".claude")
    }

    nonisolated private static func shellQuote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

enum CodexPaths {
    nonisolated static var codexDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
    }

    nonisolated static var hooksDir: URL {
        codexDir.appendingPathComponent("hooks")
    }

    nonisolated static var hooksFile: URL {
        codexDir.appendingPathComponent("hooks.json")
    }

    nonisolated static var sessionsDir: URL {
        codexDir.appendingPathComponent("sessions")
    }

    nonisolated static var hookScriptPath: URL {
        hooksDir.appendingPathComponent("vibe-hud-state.py")
    }

    nonisolated static var hookScriptShellPath: String {
        shellQuote(hookScriptPath.path)
    }

    nonisolated private static func shellQuote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

enum OpenCodePaths {
    nonisolated static var configDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/opencode")
    }

    nonisolated static var configFile: URL {
        configDir.appendingPathComponent("opencode.json")
    }

    nonisolated static var pluginDir: URL {
        configDir.appendingPathComponent("plugin")
    }

    nonisolated static var pluginFile: URL {
        pluginDir.appendingPathComponent("vibe-hud.js")
    }

    nonisolated static var pluginFileURLString: String {
        pluginFile.absoluteURL.absoluteString
    }

    nonisolated static var dataDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/share/opencode")
    }

    nonisolated static var storageDir: URL {
        dataDir.appendingPathComponent("storage")
    }

    nonisolated static var sessionsDir: URL {
        storageDir.appendingPathComponent("session")
    }

    nonisolated static var messagesDir: URL {
        storageDir.appendingPathComponent("message")
    }

    nonisolated static var partsDir: URL {
        storageDir.appendingPathComponent("part")
    }
}

enum CursorPaths {
    nonisolated static var configDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cursor")
    }

    nonisolated static var hooksFile: URL {
        configDir.appendingPathComponent("hooks.json")
    }

    nonisolated static var hooksDir: URL {
        configDir.appendingPathComponent("hooks")
    }

    nonisolated static var hookScriptPath: URL {
        hooksDir.appendingPathComponent("vibe-hud-state.py")
    }
}

enum CopilotPaths {
    nonisolated static var configDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".copilot")
    }

    nonisolated static var hooksDir: URL {
        configDir.appendingPathComponent("hooks")
    }

    nonisolated static var hookFile: URL {
        hooksDir.appendingPathComponent("vibe-hud.json")
    }

    nonisolated static var hookScriptPath: URL {
        hooksDir.appendingPathComponent("vibe-hud-state.py")
    }
}

enum PiPaths {
    nonisolated static var extensionsDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".pi/agent/extensions")
    }

    nonisolated static var extensionFile: URL {
        extensionsDir.appendingPathComponent("vibe-hud.ts")
    }
}
