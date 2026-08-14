//
//  CodexSessionRecovery.swift
//  VibeHUD
//
//  Restores recent Codex sessions from their rollout transcripts after VibeHUD restarts.
//

import Foundation

struct RecoveredCodexSession: Sendable {
    let sessionId: String
    let cwd: String
    let transcriptPath: String
    let status: String

    nonisolated init(sessionId: String, cwd: String, transcriptPath: String, status: String) {
        self.sessionId = sessionId
        self.cwd = cwd
        self.transcriptPath = transcriptPath
        self.status = status
    }
}

enum CodexSessionRecovery {
    nonisolated private static let maximumSessionAge: TimeInterval = 15 * 60
    nonisolated private static let maximumSessionCount = 8

    nonisolated static func recentSessions() -> [RecoveredCodexSession] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: CodexPaths.sessionsDir,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let cutoff = Date().addingTimeInterval(-maximumSessionAge)
        let rollouts = enumerator.compactMap { element -> URL? in
            guard let url = element as? URL,
                  url.pathExtension == "jsonl",
                  url.lastPathComponent.hasPrefix("rollout-"),
                  let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let modifiedAt = values.contentModificationDate,
                  modifiedAt >= cutoff else {
                return nil
            }
            return url
        }
        .sorted {
            let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return left > right
        }

        return rollouts.prefix(maximumSessionCount).compactMap(parse)
    }

    nonisolated private static func parse(_ rollout: URL) -> RecoveredCodexSession? {
        guard let content = try? String(contentsOf: rollout, encoding: .utf8) else {
            return nil
        }

        return parseContent(content, transcriptPath: rollout.path)
    }

    nonisolated static func parseContent(_ content: String, transcriptPath: String) -> RecoveredCodexSession? {

        var sessionId: String?
        var cwd: String?
        var status = "waiting_for_input"

        for line in content.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let payload = json["payload"] as? [String: Any] else {
                continue
            }

            if json["type"] as? String == "session_meta" {
                sessionId = payload["session_id"] as? String ?? payload["id"] as? String
                cwd = payload["cwd"] as? String
                continue
            }

            switch (json["type"] as? String, payload["type"] as? String) {
            case ("event_msg", "user_message"),
                 ("event_msg", "agent_reasoning"),
                 ("response_item", "reasoning"),
                 ("response_item", "custom_tool_call"),
                 ("response_item", "function_call"):
                status = "processing"
            case ("event_msg", "agent_message"):
                status = "waiting_for_input"
            case ("event_msg", "task_complete"),
                 ("event_msg", "turn_aborted"):
                status = "waiting_for_input"
            case ("response_item", "message") where payload["role"] as? String == "assistant":
                status = "waiting_for_input"
            default:
                continue
            }
        }

        guard let sessionId, let cwd, !sessionId.isEmpty, !cwd.isEmpty else {
            return nil
        }

        return RecoveredCodexSession(
            sessionId: sessionId,
            cwd: cwd,
            transcriptPath: transcriptPath,
            status: status
        )
    }
}
