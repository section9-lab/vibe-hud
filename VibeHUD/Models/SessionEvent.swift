//
//  SessionEvent.swift
//  VibeHUD
//

enum SessionEvent: Sendable {
    case hookReceived(HookEvent)
    case sessionEnded(sessionId: String)
}

extension SessionEvent: CustomStringConvertible {
    nonisolated var description: String {
        switch self {
        case .hookReceived(let event):
            "hookReceived(\(event.event), session: \(event.sessionId.prefix(8)))"
        case .sessionEnded(let sessionId):
            "sessionEnded(session: \(sessionId.prefix(8)))"
        }
    }
}
