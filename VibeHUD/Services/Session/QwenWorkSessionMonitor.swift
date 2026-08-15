import Foundation
import SQLite3

struct QwenWorkSessionRecord: Equatable, Sendable {
    let sessionId: String
    let cwd: String
    let isActive: Bool

    nonisolated init(sessionId: String, cwd: String, isActive: Bool) {
        self.sessionId = sessionId
        self.cwd = cwd
        self.isActive = isActive
    }
}

enum QwenWorkSessionChange: Equatable, Sendable {
    case started(QwenWorkSessionRecord)
    case stopped(QwenWorkSessionRecord)
}

struct QwenWorkSessionReconciler: Sendable {
    private var activeRecords: [String: QwenWorkSessionRecord] = [:]

    nonisolated mutating func reconcile(
        _ records: [QwenWorkSessionRecord]
    ) -> [QwenWorkSessionChange] {
        let nextActive = Dictionary(
            uniqueKeysWithValues: records
                .filter(\.isActive)
                .map { ($0.sessionId, $0) }
        )
        let startedIds = nextActive.keys.filter { activeRecords[$0] == nil }.sorted()
        let stoppedIds = activeRecords.keys.filter { nextActive[$0] == nil }.sorted()
        let changes = startedIds.compactMap { nextActive[$0].map(QwenWorkSessionChange.started) }
            + stoppedIds.compactMap { activeRecords[$0].map(QwenWorkSessionChange.stopped) }
        activeRecords = nextActive
        return changes
    }

    nonisolated mutating func reset() -> [QwenWorkSessionRecord] {
        let records = activeRecords.values.sorted { $0.sessionId < $1.sessionId }
        activeRecords.removeAll()
        return records
    }
}

enum QwenWorkSessionDatabase {
    nonisolated static func sessions(at databaseURL: URL) throws -> [QwenWorkSessionRecord] {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return [] }

        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(
            databaseURL.path,
            &database,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard openResult == SQLITE_OK, let database else {
            defer { sqlite3_close(database) }
            throw QwenWorkSessionDatabaseError.openFailed(openResult)
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 250)

        let query = """
        SELECT s.session_id,
               COALESCE(NULLIF(c.worktree_path, ''), p.path),
               CASE
                   WHEN COALESCE(s.stream_id, '') <> ''
                     OR COALESCE(json_extract(c.ext, '$.taskStatus'), '') = 'running'
                   THEN 1
                   ELSE 0
               END AS is_active
        FROM sub_chats s
        JOIN chats c ON c.id = s.chat_id
        JOIN projects p ON p.id = c.project_id
        WHERE COALESCE(s.session_id, '') <> ''
        ORDER BY s.session_id
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else {
            throw QwenWorkSessionDatabaseError.queryFailed(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }

        var records: [QwenWorkSessionRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let sessionCString = sqlite3_column_text(statement, 0),
                  let cwdCString = sqlite3_column_text(statement, 1) else {
                continue
            }
            records.append(QwenWorkSessionRecord(
                sessionId: String(cString: sessionCString),
                cwd: String(cString: cwdCString),
                isActive: sqlite3_column_int(statement, 2) == 1
            ))
        }
        return records
    }
}

private enum QwenWorkSessionDatabaseError: Error {
    case openFailed(Int32)
    case queryFailed(String)
}

final class QwenWorkSessionMonitor: @unchecked Sendable {
    static let shared = QwenWorkSessionMonitor()

    private let queue = DispatchQueue(label: "com.vibehud.qwenwork-monitor")
    private var timer: DispatchSourceTimer?
    private var reconciler = QwenWorkSessionReconciler()
    private var eventHandler: HookEventHandler?

    private init() {}

    func start(onEvent: @escaping HookEventHandler) {
        queue.async { [weak self] in
            guard let self, self.timer == nil else { return }
            self.eventHandler = onEvent
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now(), repeating: .seconds(1))
            timer.setEventHandler { [weak self] in self?.poll() }
            self.timer = timer
            timer.resume()
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.timer?.cancel()
            self.timer = nil
            self.endTrackedSessions()
            self.eventHandler = nil
        }
    }

    private func poll() {
        guard FileManager.default.fileExists(atPath: QwenWorkPaths.enabledMarker.path) else {
            endTrackedSessions()
            return
        }
        guard let records = try? QwenWorkSessionDatabase.sessions(at: QwenWorkPaths.databaseFile) else {
            return
        }
        for change in reconciler.reconcile(records) {
            eventHandler?(Self.hookEvent(for: change))
        }
    }

    private func endTrackedSessions() {
        for record in reconciler.reset() {
            eventHandler?(Self.hookEvent(for: record, status: "ended"))
        }
    }

    nonisolated private static func hookEvent(for change: QwenWorkSessionChange) -> HookEvent {
        switch change {
        case .started(let record):
            hookEvent(for: record, status: "processing")
        case .stopped(let record):
            hookEvent(for: record, status: "waiting_for_input")
        }
    }

    nonisolated private static func hookEvent(
        for record: QwenWorkSessionRecord,
        status: String
    ) -> HookEvent {
        HookEvent(
            sessionId: record.sessionId,
            cwd: record.cwd,
            event: status == "processing" ? "UserPromptSubmit" : "Stop",
            status: status,
            source: "qwenwork",
            pid: nil,
            tty: nil,
            transcriptPath: nil,
            terminalBundleId: "cn.qwenwork.desktop.mac",
            terminalPid: nil,
            tmuxPane: nil,
            tmuxSocket: nil,
            tool: nil,
            toolInput: nil,
            toolUseId: nil,
            notificationType: nil,
            message: nil
        )
    }
}
