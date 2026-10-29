import Foundation
import Testing

@testable import vibe_hud

@Suite("Anonymous daily activity")
@MainActor
struct AnalyticsStateTests {
    @Test("Repeated use and app restarts count only once on the same reporting day")
    func deduplicatesAcrossRestarts() {
        withDefaults { defaults in
            let first = makeState(defaults)
            #expect(first.claimActiveDay(at: date("2026-10-29T08:00:00Z")) == "2026-10-29")
            #expect(first.claimActiveDay(at: date("2026-10-29T23:00:00Z")) == nil)
            let restarted = makeState(defaults)
            #expect(restarted.claimActiveDay(at: date("2026-10-30T06:59:59Z")) == nil)
            #expect(restarted.claimActiveDay(at: date("2026-10-30T07:00:00Z")) == "2026-10-30")
        }
    }

    @Test("Reporting day follows the project timezone instead of the Mac timezone or UTC")
    func respectsReportingTimeZone() {
        withDefaults { defaults in
            let state = makeState(defaults)
            #expect(state.claimActiveDay(at: date("2026-10-29T23:59:59Z")) == "2026-10-29")
            #expect(state.claimActiveDay(at: date("2026-10-30T00:00:00Z")) == nil)
            #expect(state.claimActiveDay(at: date("2026-10-30T07:00:00Z")) == "2026-10-30")
        }
    }

    @Test("Daylight saving fall-back does not count a second active day")
    func handlesDaylightSaving() {
        withDefaults { defaults in
            let state = makeState(defaults)
            #expect(state.claimActiveDay(at: date("2026-11-01T08:30:00Z")) == "2026-11-01")
            #expect(state.claimActiveDay(at: date("2026-11-01T09:30:00Z")) == nil)
            #expect(state.claimActiveDay(at: date("2026-11-02T07:59:59Z")) == nil)
            #expect(state.claimActiveDay(at: date("2026-11-02T08:00:00Z")) == "2026-11-02")
        }
    }

    @Test("Opting out persists and does not consume the next active day")
    func respectsOptOut() {
        withDefaults { defaults in
            let state = makeState(defaults)
            state.isEnabled = false
            #expect(state.claimActiveDay(at: date("2026-10-29T12:00:00Z")) == nil)
            let restarted = makeState(defaults)
            #expect(!restarted.isEnabled)
            restarted.isEnabled = true
            #expect(restarted.claimActiveDay(at: date("2026-10-29T12:00:00Z")) == "2026-10-29")
        }
    }

    @Test("Shared-project apps have independent identifiers, preferences and activity days")
    func isolatesApps() {
        withDefaults { defaults in
            let hud = makeState(defaults)
            let other = makeState(defaults, appID: "another-app")
            #expect(hud.installationID != other.installationID)
            #expect(hud.claimActiveDay(at: date("2026-10-29T12:00:00Z")) != nil)
            #expect(other.claimActiveDay(at: date("2026-10-29T12:00:00Z")) != nil)
            hud.isEnabled = false
            #expect(other.isEnabled)
        }
    }

    @Test("Upgrade discards the hardware UUID and retains a new random installation ID")
    func replacesHardwareIdentifier() {
        withDefaults { defaults in
            let oldID = "OLD-HARDWARE-ID"
            defaults.set(oldID, forKey: "mixpanel_distinct_id")
            let state = makeState(defaults)
            let id = state.installationID
            #expect(id != oldID)
            #expect(UUID(uuidString: id) != nil)
            #expect(defaults.object(forKey: "mixpanel_distinct_id") == nil)
            #expect(makeState(defaults).installationID == id)
        }
    }

    private func makeState(_ defaults: UserDefaults, appID: String = "vibe-hud") -> AnalyticsState {
        AnalyticsState(
            defaults: defaults, appID: appID, timeZone: TimeZone(identifier: "America/Los_Angeles")!
        )
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let name = "AnalyticsStateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        body(defaults)
    }
}
