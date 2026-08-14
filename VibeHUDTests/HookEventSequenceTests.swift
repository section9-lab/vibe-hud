import Foundation
import Testing
@testable import vibe_hud

@Suite("Hook event ordering")
struct HookEventSequenceTests {
    @Test("Rejects duplicate event IDs within the same source session")
    func rejectsDuplicateIDs() {
        var sequence = HookEventSequence(maximumRememberedEventCount: 4)

        let firstAccepted = sequence.shouldAccept(
            source: "codex",
            sessionId: "session-1",
            eventId: "event-1",
            eventTimestamp: 100,
            lastEventTimestamp: nil
        )
        let duplicateAccepted = sequence.shouldAccept(
            source: "codex",
            sessionId: "session-1",
            eventId: "event-1",
            eventTimestamp: 101,
            lastEventTimestamp: 100
        )

        #expect(firstAccepted)
        #expect(!duplicateAccepted)
    }

    @Test("Allows the same event ID in a different source session")
    func scopesIDsToSourceAndSession() {
        var sequence = HookEventSequence(maximumRememberedEventCount: 4)

        let codexAccepted = sequence.shouldAccept(
            source: "codex",
            sessionId: "session-1",
            eventId: "event-1",
            eventTimestamp: 100,
            lastEventTimestamp: nil
        )
        let piAccepted = sequence.shouldAccept(
            source: "pi",
            sessionId: "session-1",
            eventId: "event-1",
            eventTimestamp: 100,
            lastEventTimestamp: nil
        )

        #expect(codexAccepted)
        #expect(piAccepted)
    }

    @Test("Rejects events older than the current session state")
    func rejectsOutOfOrderTimestamps() {
        var sequence = HookEventSequence(maximumRememberedEventCount: 4)

        let accepted = sequence.shouldAccept(
            source: "cursor",
            sessionId: "session-1",
            eventId: "older",
            eventTimestamp: 99,
            lastEventTimestamp: 100
        )

        #expect(!accepted)
    }

    @Test("Evicts the oldest remembered event ID")
    func evictsOldestID() {
        var sequence = HookEventSequence(maximumRememberedEventCount: 2)
        for index in 1...3 {
            let accepted = sequence.shouldAccept(
                source: "codex",
                sessionId: "session-1",
                eventId: "event-\(index)",
                eventTimestamp: TimeInterval(index),
                lastEventTimestamp: nil
            )
            #expect(accepted)
        }

        let evictedIdAccepted = sequence.shouldAccept(
            source: "codex",
            sessionId: "session-1",
            eventId: "event-1",
            eventTimestamp: 4,
            lastEventTimestamp: nil
        )
        #expect(evictedIdAccepted)
    }
}
