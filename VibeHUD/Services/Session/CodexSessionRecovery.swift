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
    nonisolated static let maximumSessionAge: TimeInterval = 15 * 60
    nonisolated static let maximumSessionCount = 8
    private nonisolated static let statusTailSize: UInt64 = 256 * 1024

    nonisolated static func recentSessions() -> [RecoveredCodexSession] {
        recentSessions(in: CodexPaths.sessionsDir, now: Date())
    }

    nonisolated static func recentSessions(in directory: URL, now: Date) -> [RecoveredCodexSession] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let cutoff = now.addingTimeInterval(-maximumSessionAge)
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

        var recoveredSessions: [RecoveredCodexSession] = []
        var recoveredIds = Set<String>()
        for rollout in rollouts {
            guard let recovered = parse(rollout),
                  recoveredIds.insert(recovered.sessionId).inserted else {
                continue
            }
            recoveredSessions.append(recovered)
            if recoveredSessions.count == maximumSessionCount {
                break
            }
        }
        return recoveredSessions
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

            if let newStatus = eventStatus(for: json, payload: payload) {
                status = newStatus
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

    nonisolated static func currentStatus(at transcriptPath: String) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: transcriptPath)) else {
            return nil
        }
        defer { try? handle.close() }

        guard let size = try? handle.seekToEnd() else { return nil }
        let offset = size > statusTailSize ? size - statusTailSize : 0
        do {
            try handle.seek(toOffset: offset)
            guard let data = try handle.readToEnd() else { return nil }

            var latestStatus: String?
            for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
                guard let lineData = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                      let payload = json["payload"] as? [String: Any],
                      let status = eventStatus(for: json, payload: payload) else {
                    continue
                }
                latestStatus = status
            }
            return latestStatus
        } catch {
            return nil
        }
    }

    nonisolated private static func eventStatus(
        for json: [String: Any],
        payload: [String: Any]
    ) -> String? {
        switch (json["type"] as? String, payload["type"] as? String) {
        case ("event_msg", "user_message"),
             ("event_msg", "agent_reasoning"),
             ("response_item", "reasoning"),
             ("response_item", "custom_tool_call"),
             ("response_item", "function_call"):
            return "processing"
        case ("event_msg", "agent_message"),
             ("event_msg", "task_complete"),
             ("event_msg", "turn_aborted"):
            return "waiting_for_input"
        case ("response_item", "message") where payload["role"] as? String == "assistant":
            return "waiting_for_input"
        default:
            return nil
        }
    }
}
