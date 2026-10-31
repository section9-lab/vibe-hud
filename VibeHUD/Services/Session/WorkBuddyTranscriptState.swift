import Foundation

/// Recovery evidence from the user session's own transcript (never subagent files).
/// A completed tool is not a completed turn: generation or a background task may continue.
struct WorkBuddyTranscriptState: Equatable, Sendable {
    let status: String
    let timestamp: TimeInterval

    nonisolated static func read(at url: URL) -> Self? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        let offset = size > 262_144 ? size - 262_144 : 0
        guard (try? handle.seek(toOffset: offset)) != nil,
              let data = try? handle.readToEnd() else { return nil }
        // Drop a possibly truncated first record, and tolerate a partial trailing write.
        let lines = data.split(separator: 10, omittingEmptySubsequences: false)
        let completeLines = offset > 0 ? Array(lines.dropFirst()) : lines
        return parseLines(completeLines)
    }

    nonisolated static func parseContent(_ content: String) -> Self? {
        parseLines(Data(content.utf8).split(separator: 10, omittingEmptySubsequences: false))
    }

    nonisolated private static func parseLines(_ lines: [Data.SubSequence]) -> Self? {
        for line in lines.reversed() {
            guard let json = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let type = json["type"] as? String,
                  let milliseconds = json["timestamp"] as? Double,
                  milliseconds.isFinite, milliseconds > 0 else { continue }
            let status: String
            switch type {
            case "reasoning", "function_call", "function_call_result":
                status = "processing"
            case "message":
                if json["role"] as? String == "user" {
                    status = "processing"
                } else if json["role"] as? String == "assistant" {
                    // WorkBuddy also marks intermediate commentary as completed.
                    // Its final response carries turn usage; a completed message
                    // without that evidence must not finish the whole session.
                    let message = json["message"] as? [String: Any]
                    let provider = json["providerData"] as? [String: Any]
                    let hasTurnUsage = message?["usage"] is [String: Any] || provider?["usage"] is [String: Any]
                    status = json["status"] as? String == "completed" && hasTurnUsage
                        ? "waiting_for_input" : "processing"
                } else {
                    continue
                }
            default:
                continue
            }
            return Self(status: status, timestamp: milliseconds / 1_000)
        }
        return nil
    }

    /// Live hooks win ties, and recovery must never rewind a newer permission/stop event.
    nonisolated func isNewer(than timestamp: TimeInterval?) -> Bool {
        timestamp.map { self.timestamp > $0 } ?? true
    }
}
