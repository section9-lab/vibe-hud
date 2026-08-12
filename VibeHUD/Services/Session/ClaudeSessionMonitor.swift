//
//  ClaudeSessionMonitor.swift
//  VibeHUD
//

import Combine
import Foundation

@MainActor
final class ClaudeSessionMonitor: ObservableObject {
    @Published var instances: [SessionState] = []
    @Published var pendingInstances: [SessionState] = []

    private var cancellables = Set<AnyCancellable>()

    init() {
        SessionStore.shared.sessionsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sessions in
                self?.instances = sessions
                self?.pendingInstances = sessions.filter(\.needsAttention)
            }
            .store(in: &cancellables)

        SessionStore.shared.completionPublisher
            .receive(on: DispatchQueue.main)
            .sink { _ in
                NotificationSoundPlayer.shared.playSelectedSound()
            }
            .store(in: &cancellables)
    }

    func startMonitoring() {
        Task { await SessionStore.shared.startPeriodicStatusCheck() }
        HookSocketServer.shared.start { event in
            Task { await SessionStore.shared.process(.hookReceived(event)) }
        }
    }

    func stopMonitoring() {
        HookSocketServer.shared.stop()
        Task { await SessionStore.shared.stopPeriodicStatusCheck() }
    }

    func archiveSession(sessionId: String) {
        Task { await SessionStore.shared.process(.sessionEnded(sessionId: sessionId)) }
    }
}
