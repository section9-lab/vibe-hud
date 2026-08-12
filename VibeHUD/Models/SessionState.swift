//
//  SessionState.swift
//  VibeHUD
//
//  Privacy-preserving session state. No conversation or permission data is stored.
//

import Foundation

enum SessionSource: String, Codable, Equatable, Sendable {
    case claude
    case codex
    case opencode

    nonisolated init(rawSource: String?) {
        switch rawSource?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "codex":
            self = .codex
        case "opencode":
            self = .opencode
        default:
            self = .claude
        }
    }

    nonisolated var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .opencode: "OpenCode"
        }
    }
}

struct SessionState: Equatable, Identifiable, Sendable {
    let sessionId: String
    let cwd: String
    let projectName: String
    var source: SessionSource

    var pid: Int?
    var tty: String?
    var terminalBundleId: String?
    var terminalPid: Int?
    var tmuxPane: String?
    var tmuxSocketPath: String?
    var isInTmux: Bool

    var phase: SessionPhase
    var lastActivity: Date
    let createdAt: Date

    var id: String { sessionId }

    nonisolated init(
        sessionId: String,
        cwd: String,
        source: SessionSource = .claude,
        pid: Int? = nil,
        tty: String? = nil,
        terminalBundleId: String? = nil,
        terminalPid: Int? = nil,
        tmuxPane: String? = nil,
        tmuxSocketPath: String? = nil,
        isInTmux: Bool = false,
        phase: SessionPhase = .idle,
        lastActivity: Date = Date(),
        createdAt: Date = Date()
    ) {
        self.sessionId = sessionId
        self.cwd = cwd
        self.projectName = URL(fileURLWithPath: cwd).lastPathComponent
        self.source = source
        self.pid = pid
        self.tty = tty
        self.terminalBundleId = terminalBundleId
        self.terminalPid = terminalPid
        self.tmuxPane = tmuxPane
        self.tmuxSocketPath = tmuxSocketPath
        self.isInTmux = isInTmux
        self.phase = phase
        self.lastActivity = lastActivity
        self.createdAt = createdAt
    }

    var stableId: String {
        pid.map { "\($0)-\(sessionId)" } ?? sessionId
    }

    var displayTitle: String {
        projectName.isEmpty ? source.displayName : projectName
    }

    var needsAttention: Bool {
        phase.needsAttention
    }
}
