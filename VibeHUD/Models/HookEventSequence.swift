import Foundation

struct HookEventSequence: Sendable {
    private let maximumRememberedEventCount: Int
    private var processedEventIds: Set<String> = []
    private var processedEventOrder: [String] = []

    nonisolated init(maximumRememberedEventCount: Int = 2_048) {
        self.maximumRememberedEventCount = max(1, maximumRememberedEventCount)
    }

    nonisolated mutating func shouldAccept(
        source: String?,
        sessionId: String,
        eventId: String?,
        eventTimestamp: TimeInterval?,
        lastEventTimestamp: TimeInterval?
    ) -> Bool {
        if let eventId {
            let eventKey = "\(source ?? "unknown"):\(sessionId):\(eventId)"
            guard !processedEventIds.contains(eventKey) else { return false }

            processedEventIds.insert(eventKey)
            processedEventOrder.append(eventKey)
            if processedEventOrder.count > maximumRememberedEventCount {
                processedEventIds.remove(processedEventOrder.removeFirst())
            }
        }

        if let eventTimestamp, let lastEventTimestamp {
            return eventTimestamp >= lastEventTimestamp
        }
        return true
    }
}
