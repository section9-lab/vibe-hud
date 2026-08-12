//
//  SessionStore.swift
//  VibeHUD
//
//  Hook-only session state with ordering protection and completion events.
//

import Combine
import Darwin
import Foundation
import Mixpanel
import os.log

actor SessionStore {
    static let shared = SessionStore()
    nonisolated static let logger = Logger(subsystem: "com.vibehud", category: "Session")

    private var sessions: [String: SessionState] = [:]
    private var lastEventSequence: [String: UInt64] = [:]
    private var endedSessions: Set<String> = []
    private var endedOrder: [String] = []
    private var statusCheckTask: Task<Void, Never>?

    private static let endedHistoryLimit = 256

    private nonisolated(unsafe) let sessionsSubject =
        CurrentValueSubject<[SessionState], Never>([])
    private nonisolated(unsafe) let completionSubject =
        PassthroughSubject<SessionState, Never>()

    nonisolated var sessionsPublisher: AnyPublisher<[SessionState], Never> {
        sessionsSubject.eraseToAnyPublisher()
    }

    nonisolated var completionPublisher: AnyPublisher<SessionState, Never> {
        completionSubject.eraseToAnyPublisher()
    }

    private init() {}

    func process(_ event: SessionEvent) {
        switch event {
        case .hookReceived(let hookEvent):
            processHookEvent(hookEvent)
        case .sessionEnded(let sessionId):
            markEnded(sessionId)
            removeSession(sessionId)
        }
        publishState()
    }

    private func processHookEvent(_ event: HookEvent) {
        // Ordering protection only applies when the source supplies a sequence.
        // Synthesizing one here would mix clock units across sources and could
        // permanently reject every later event for that session.
        if let sequence = event.eventSequence {
            if let previous = lastEventSequence[event.sessionId], sequence <= previous {
                Self.logger.debug(
                    "Ignored out-of-order \(event.event, privacy: .public) for \(event.sessionId.prefix(8), privacy: .public)"
                )
                return
            }
            lastEventSequence[event.sessionId] = sequence
        }

        if event.isEnded {
            markEnded(event.sessionId)
            removeSession(event.sessionId)
            return
        }

        if endedSessions.contains(event.sessionId) {
            guard event.event == "SessionStart" else {
                Self.logger.debug(
                    "Ignored late \(event.event, privacy: .public) for ended session \(event.sessionId.prefix(8), privacy: .public)"
                )
                return
            }
            clearEnded(event.sessionId)
        }

        let isNew = sessions[event.sessionId] == nil
        var session = sessions[event.sessionId] ?? SessionState(
            sessionId: event.sessionId,
            cwd: event.cwd,
            source: SessionSource(rawSource: event.source)
        )
        let previousPhase = session.phase

        if let pid = event.pid {
            if session.pid != pid {
                let tree = ProcessTreeBuilder.shared.buildTree()
                session.isInTmux = ProcessTreeBuilder.shared.isInTmux(pid: pid, tree: tree)
            }
            session.pid = pid
        }
        session.tty = event.tty?.replacingOccurrences(of: "/dev/", with: "") ?? session.tty
        session.terminalBundleId = event.terminalBundleId ?? session.terminalBundleId
        session.terminalPid = event.terminalPid ?? session.terminalPid
        session.tmuxPane = event.tmuxPane ?? session.tmuxPane
        session.tmuxSocketPath = event.tmuxSocket ?? session.tmuxSocketPath
        session.source = SessionSource(rawSource: event.source)
        session.lastActivity = Date()

        if let nextPhase = event.phaseUpdate {
            session.phase = nextPhase
        }

        sessions[event.sessionId] = session

        if isNew {
            Mixpanel.mainInstance().track(event: "Session Started")
        }

        if previousPhase != .waitingForInput && session.phase == .waitingForInput {
            completionSubject.send(session)
        }

        Self.logger.debug(
            "\(event.sessionId.prefix(8), privacy: .public): \(String(describing: previousPhase), privacy: .public) -> \(String(describing: session.phase), privacy: .public) via \(event.event, privacy: .public)"
        )
    }

    func startPeriodicStatusCheck() {
        guard statusCheckTask == nil else { return }
        statusCheckTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { break }
                await self?.removeExitedProcesses()
            }
        }
    }

    func stopPeriodicStatusCheck() {
        statusCheckTask?.cancel()
        statusCheckTask = nil
    }

    private func removeExitedProcesses() {
        let exited = sessions.values.compactMap { session -> String? in
            guard let pid = session.pid else { return nil }
            return kill(Int32(pid), 0) == 0 ? nil : session.sessionId
        }
        guard !exited.isEmpty else { return }
        for sessionId in exited {
            markEnded(sessionId)
            removeSession(sessionId)
        }
        publishState()
    }

    /// Records a tombstone so late events cannot resurrect a finished session.
    /// Oldest tombstones are evicted so long-running instances stay bounded.
    private func markEnded(_ sessionId: String) {
        if endedSessions.insert(sessionId).inserted {
            endedOrder.append(sessionId)
        }
        while endedOrder.count > Self.endedHistoryLimit {
            let oldest = endedOrder.removeFirst()
            endedSessions.remove(oldest)
            lastEventSequence.removeValue(forKey: oldest)
        }
    }

    private func clearEnded(_ sessionId: String) {
        guard endedSessions.remove(sessionId) != nil else { return }
        endedOrder.removeAll { $0 == sessionId }
    }

    private func removeSession(_ sessionId: String) {
        sessions.removeValue(forKey: sessionId)
    }

    private func publishState() {
        sessionsSubject.send(
            sessions.values.sorted {
                if $0.phase.isActive != $1.phase.isActive {
                    return $0.phase.isActive
                }
                return $0.lastActivity > $1.lastActivity
            }
        )
    }

    func session(for sessionId: String) -> SessionState? {
        sessions[sessionId]
    }

    func allSessions() -> [SessionState] {
        Array(sessions.values)
    }
}
