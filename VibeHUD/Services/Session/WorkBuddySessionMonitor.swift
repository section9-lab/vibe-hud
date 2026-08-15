import Darwin
import Foundation

struct WorkBuddySessionRecord: Equatable, Sendable {
    let sessionId: String
    let cwd: String
    let pid: Int
}

enum WorkBuddySessionDirectory {
    nonisolated static func sessions(
        at directory: URL,
        isProcessRunning: (Int) -> Bool = isProcessRunning
    ) throws -> [WorkBuddySessionRecord] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }

        return try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "json" }
        .compactMap { url -> WorkBuddySessionRecord? in
            let data = try Data(contentsOf: url)
            let session = try JSONDecoder().decode(SessionFile.self, from: data)
            guard !session.sessionId.lowercased().hasPrefix("prewarm-"),
                  isProcessRunning(session.pid) else {
                return nil
            }
            return WorkBuddySessionRecord(
                sessionId: session.sessionId,
                cwd: session.cwd,
                pid: session.pid
            )
        }
        .sorted { $0.sessionId < $1.sessionId }
    }

    nonisolated private static func isProcessRunning(_ pid: Int) -> Bool {
        guard pid > 0 else { return false }
        return kill(pid_t(pid), 0) == 0 || errno == EPERM
    }

    private struct SessionFile: Decodable {
        let sessionId: String
        let cwd: String
        let pid: Int
    }
}

final class WorkBuddySessionMonitor: @unchecked Sendable {
    static let shared = WorkBuddySessionMonitor()

    private let queue = DispatchQueue(label: "com.vibehud.workbuddy-monitor")
    private var timer: DispatchSourceTimer?
    private var trackedSessions: [String: WorkBuddySessionRecord] = [:]
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
        guard FileManager.default.fileExists(atPath: WorkBuddyPaths.hookScriptPath.path) else {
            endTrackedSessions()
            return
        }
        guard let sessions = try? WorkBuddySessionDirectory.sessions(
            at: WorkBuddyPaths.sessionRuntimeDir
        ) else {
            return
        }

        let nextSessions = Dictionary(uniqueKeysWithValues: sessions.map { ($0.sessionId, $0) })
        let started = nextSessions.keys.filter { trackedSessions[$0] == nil }.sorted()
        let stopped = trackedSessions.keys.filter { nextSessions[$0] == nil }.sorted()

        for sessionId in started {
            if let session = nextSessions[sessionId] {
                eventHandler?(Self.hookEvent(for: session, status: "waiting_for_input"))
            }
        }
        for sessionId in stopped {
            if let session = trackedSessions[sessionId] {
                eventHandler?(Self.hookEvent(for: session, status: "ended"))
            }
        }

        trackedSessions = nextSessions
    }

    private func endTrackedSessions() {
        for session in trackedSessions.values {
            eventHandler?(Self.hookEvent(for: session, status: "ended"))
        }
        trackedSessions.removeAll()
    }

    nonisolated private static func hookEvent(
        for session: WorkBuddySessionRecord,
        status: String
    ) -> HookEvent {
        HookEvent(
            sessionId: session.sessionId,
            cwd: session.cwd,
            event: status == "ended" ? "SessionEnd" : "SessionStart",
            status: status,
            source: "workbuddy",
            pid: session.pid,
            tty: nil,
            transcriptPath: nil,
            terminalBundleId: "com.workbuddy.workbuddy",
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
