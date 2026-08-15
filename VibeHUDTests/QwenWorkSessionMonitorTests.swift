import Foundation
import SQLite3
import Testing
@testable import vibe_hud

@Suite("Qwen Work session monitoring")
struct QwenWorkSessionMonitorTests {
    @Test("Starts and stops only active Qwen Work sessions")
    func reconcilesActiveSessions() {
        let active = QwenWorkSessionRecord(
            sessionId: "active",
            cwd: "/tmp/project",
            isActive: true
        )
        let idle = QwenWorkSessionRecord(
            sessionId: "idle",
            cwd: "/tmp/project",
            isActive: false
        )
        var reconciler = QwenWorkSessionReconciler()

        #expect(reconciler.reconcile([active, idle]) == [.started(active)])
        #expect(reconciler.reconcile([active, idle]).isEmpty)
        #expect(reconciler.reconcile([idle]) == [.stopped(active)])
    }

    @Test("Reads running state from the Qwen Work database")
    func readsDatabase() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
        defer { try? FileManager.default.removeItem(at: databaseURL) }

        var database: OpaquePointer?
        #expect(sqlite3_open(databaseURL.path, &database) == SQLITE_OK)
        defer { sqlite3_close(database) }

        try execute(
            """
            CREATE TABLE projects (id TEXT PRIMARY KEY, path TEXT NOT NULL);
            CREATE TABLE chats (
                id TEXT PRIMARY KEY,
                project_id TEXT NOT NULL,
                ext TEXT,
                worktree_path TEXT
            );
            CREATE TABLE sub_chats (
                id TEXT PRIMARY KEY,
                chat_id TEXT NOT NULL,
                session_id TEXT,
                stream_id TEXT
            );
            INSERT INTO projects VALUES ('project', '/tmp/qwen-project');
            INSERT INTO chats VALUES (
                'running-chat', 'project', '{"taskStatus":"running"}', '/tmp/qwen-worktree'
            );
            INSERT INTO chats VALUES (
                'idle-chat', 'project', '{"taskStatus":"completed"}', NULL
            );
            INSERT INTO sub_chats VALUES ('running', 'running-chat', 'running-session', NULL);
            INSERT INTO sub_chats VALUES ('idle', 'idle-chat', 'idle-session', NULL);
            """,
            in: database
        )

        let records = try QwenWorkSessionDatabase.sessions(at: databaseURL)

        #expect(records == [
            QwenWorkSessionRecord(
                sessionId: "idle-session",
                cwd: "/tmp/qwen-project",
                isActive: false
            ),
            QwenWorkSessionRecord(
                sessionId: "running-session",
                cwd: "/tmp/qwen-worktree",
                isActive: true
            ),
        ])
    }

    private func execute(_ sql: String, in database: OpaquePointer?) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(database, sql, nil, nil, &errorMessage)
        defer { sqlite3_free(errorMessage) }
        guard result == SQLITE_OK else {
            throw TestDatabaseError.executionFailed(
                errorMessage.map { String(cString: $0) } ?? "Unknown SQLite error"
            )
        }
    }
}

private enum TestDatabaseError: Error {
    case executionFailed(String)
}
