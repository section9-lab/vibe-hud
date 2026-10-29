import Testing
import Foundation
@testable import vibe_hud

@Suite("Monitoring number presentation")
struct MonitoringNumberTextTests {
    @Test("Small positive generation rates never appear as zero")
    func smallRate() {
        #expect(MonitoringNumberText.speed(0.04) == "<0.1 tok/s")
        #expect(MonitoringNumberText.speed(0.4) == "0.4 tok/s")
    }

    @Test("Missing timing sample has an explicit unit")
    func unavailableRate() {
        #expect(MonitoringNumberText.speed(nil) == "-- tok/s")
    }

    @Test("Ring speed uses the approved compact number without an approximation mark")
    func ringRate() {
        #expect(MonitoringNumberText.ringSpeedNumber(75.2) == "75")
        #expect(MonitoringNumberText.ringSpeedNumber(0.4) == "0.4")
        #expect(MonitoringNumberText.ringSpeedNumber(nil) == "--")
        #expect(MonitoringNumberText.speed(75.2) == "75.2 tok/s")
    }

    @Test("Remaining quota thresholds and unknown state match the ring")
    func ringThresholds() {
        #expect(MonitoringRingTone(remaining: 20.01) == .green)
        #expect(MonitoringRingTone(remaining: 20) == .gold)
        #expect(MonitoringRingTone(remaining: 5.01) == .gold)
        #expect(MonitoringRingTone(remaining: 5) == .red)
        #expect(MonitoringRingTone(remaining: 0) == .red)
        #expect(MonitoringRingTone(remaining: nil) == .unknown)
    }

    @Test("Right ring matches the 26 pt activity ring and stays inside short headers")
    func ringFitsHeader() {
        #expect(MonitoringRingLayout.outerDiameter(notchHeight: 32) == 26)
        #expect(MonitoringRingLayout.outerDiameter(notchHeight: 28) == 24)
        #expect(MonitoringRingLayout.outerDiameter(notchHeight: 32) + 4 <= 32)
        #expect(MonitoringRingLayout.innerDiameter(outerDiameter: 26) == 20)
    }

    @Test("Codex center switches phase at five second boundaries")
    func codexCenterCycle() {
        let origin = Date(timeIntervalSinceReferenceDate: 0)
        #expect(!MonitoringCenterCycle.showsIcon(at: origin.addingTimeInterval(4.99)))
        #expect(MonitoringCenterCycle.showsIcon(at: origin.addingTimeInterval(5)))
        #expect(MonitoringCenterCycle.showsIcon(at: origin.addingTimeInterval(9.99)))
        #expect(!MonitoringCenterCycle.showsIcon(at: origin.addingTimeInterval(10)))
    }
}
