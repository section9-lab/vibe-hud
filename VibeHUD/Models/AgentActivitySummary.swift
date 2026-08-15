import Foundation

enum AgentActivityTint: Equatable, Sendable {
    case claudeOrange
    case white
    case gray
    case workBuddyGreen

    var rgb: UInt32 {
        switch self {
        case .claudeOrange: 0xD97757
        case .white: 0xFFFFFF
        case .gray: 0x8E8E93
        case .workBuddyGreen: 0x0EC8A9
        }
    }
}

extension SessionSource {
    var activityTint: AgentActivityTint {
        switch self {
        case .claude:
            .claudeOrange
        case .codex, .copilot:
            .white
        case .cursor, .pi, .opencode:
            .gray
        case .workbuddy, .qwenWork:
            .workBuddyGreen
        }
    }

    fileprivate var activityRingOrder: Int {
        switch self {
        case .claude: 0
        case .codex: 1
        case .cursor: 2
        case .copilot: 3
        case .pi: 4
        case .opencode: 5
        case .workbuddy: 6
        case .qwenWork: 7
        }
    }
}

struct AgentActivitySummary: Equatable {
    struct Ring: Equatable {
        let source: SessionSource?
        let isActive: Bool
        let lastActivity: Date?

        var hasGap: Bool {
            isActive
        }
    }

    let runningSessionCount: Int
    let activeSources: [SessionSource]
    let rings: [Ring]

    init(sessions: [SessionState]) {
        let groupedSessions = Dictionary(grouping: sessions, by: \.source)
        let activeSessions = sessions.filter(\.phase.isActive)

        let selectedRings = groupedSessions.map { source, sessions in
            let activeSourceSessions = sessions.filter(\.phase.isActive)
            let relevantSessions = activeSourceSessions.isEmpty ? sessions : activeSourceSessions
            return Ring(
                source: source,
                isActive: !activeSourceSessions.isEmpty,
                lastActivity: relevantSessions.map(\.lastActivity).max()
            )
        }
        .sorted { lhs, rhs in
            if lhs.isActive != rhs.isActive {
                return lhs.isActive
            }
            if lhs.lastActivity != rhs.lastActivity {
                return (lhs.lastActivity ?? .distantPast)
                    > (rhs.lastActivity ?? .distantPast)
            }
            return (lhs.source?.activityRingOrder ?? .max)
                < (rhs.source?.activityRingOrder ?? .max)
        }
        .prefix(3)

        var rings = selectedRings
            .sorted {
                ($0.source?.activityRingOrder ?? .max)
                    < ($1.source?.activityRingOrder ?? .max)
            }

        rings.append(
            contentsOf: repeatElement(
                Ring(source: nil, isActive: false, lastActivity: nil),
                count: 3 - rings.count
            )
        )

        runningSessionCount = activeSessions.count
        activeSources = Array(Set(activeSessions.map(\.source)))
            .sorted { $0.activityRingOrder < $1.activityRingOrder }
        self.rings = rings
    }
}
