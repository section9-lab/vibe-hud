import Foundation
import Testing
@testable import vibe_hud

@Suite("WorkBuddy session monitoring")
struct WorkBuddySessionMonitorTests {
    @Test("Restores both live WorkBuddy sessions while ignoring prewarm workers")
    func readsLiveSessions() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try sessionFile(
            sessionId: "interactive-101",
            cwd: "/",
            pid: 101,
            at: directory.appendingPathComponent("main.json")
        )
        try sessionFile(
            sessionId: "task-202",
            cwd: "/tmp/workbuddy-task",
            pid: 202,
            at: directory.appendingPathComponent("task.json")
        )
        try sessionFile(
            sessionId: "prewarm-wb-pool-303",
            cwd: "/",
            pid: 303,
            at: directory.appendingPathComponent("prewarm.json")
        )
        try sessionFile(
            sessionId: "stale-404",
            cwd: "/tmp/stale",
            pid: 404,
            at: directory.appendingPathComponent("stale.json")
        )

        let sessions = try WorkBuddySessionDirectory.sessions(
            at: directory,
            isProcessRunning: { $0 == 101 || $0 == 202 || $0 == 303 }
        )

        #expect(sessions == [
            WorkBuddySessionRecord(sessionId: "interactive-101", cwd: "/", pid: 101),
            WorkBuddySessionRecord(sessionId: "task-202", cwd: "/tmp/workbuddy-task", pid: 202),
        ])
    }

    private func sessionFile(sessionId: String, cwd: String, pid: Int, at url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "sessionId": sessionId,
            "cwd": cwd,
            "pid": pid,
        ])
        try data.write(to: url)
    }
}
