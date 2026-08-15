import AppKit
import Foundation
import SwiftUI
import Testing
@testable import vibe_hud

@Suite("Agent activity rings")
struct AgentActivityRingsTests {
    @Test("Always provides three rings")
    func alwaysProvidesThreeRings() {
        let summary = AgentActivitySummary(sessions: [])

        #expect(summary.runningSessionCount == 0)
        #expect(summary.rings.count == 3)
        #expect(summary.rings.allSatisfy { !$0.isActive })
    }

    @Test("Counts only processing and compacting sessions")
    func countsOnlyActiveSessions() {
        let summary = AgentActivitySummary(sessions: [
            session("processing", source: .claude, phase: .processing),
            session("compacting", source: .codex, phase: .compacting),
            session("idle", source: .cursor, phase: .idle),
            session("waiting", source: .copilot, phase: .waitingForInput),
            session("failed", source: .pi, phase: .failed(nil)),
            session("ended", source: .opencode, phase: .ended),
        ])

        #expect(summary.runningSessionCount == 2)
        #expect(Set(summary.rings.filter(\.isActive).compactMap(\.source)) == [.claude, .codex])
    }

    @Test("Uses one ring for multiple sessions from the same agent")
    func groupsSessionsBySource() {
        let summary = AgentActivitySummary(sessions: [
            session("claude-1", source: .claude, phase: .processing),
            session("claude-2", source: .claude, phase: .compacting),
        ])

        #expect(summary.runningSessionCount == 2)
        #expect(summary.rings.filter { $0.source == .claude }.count == 1)
        #expect(summary.rings.first { $0.source == .claude }?.isActive == true)
    }

    @Test("Leaves inactive agent rings stationary")
    func leavesInactiveAgentRingsStationary() {
        let summary = AgentActivitySummary(sessions: [
            session("claude", source: .claude, phase: .processing, lastActivity: 2),
            session("workbuddy", source: .workbuddy, phase: .idle, lastActivity: 1),
        ])

        #expect(summary.rings.first { $0.source == .claude }?.isActive == true)
        #expect(summary.rings.first { $0.source == .workbuddy }?.isActive == false)
    }

    @Test("Only active agent rings have a gap")
    func gapsOnlyActiveAgentRings() {
        let summary = AgentActivitySummary(sessions: [
            session("claude", source: .claude, phase: .processing),
            session("workbuddy", source: .workbuddy, phase: .idle),
        ])

        #expect(summary.rings.first { $0.source == .claude }?.hasGap == true)
        #expect(summary.rings.first { $0.source == .workbuddy }?.hasGap == false)
        #expect(AgentActivitySummary(sessions: []).rings.allSatisfy { !$0.hasGap })
    }

    @Test("Freezes and resumes a ring from its current angle")
    func preservesRingRotationWhenActivityChanges() {
        let start = Date(timeIntervalSince1970: 0)
        let stop = Date(timeIntervalSince1970: 1)
        let resume = Date(timeIntervalSince1970: 10)
        var motion = AgentActivityRingMotion(
            isAnimating: true,
            at: start,
            phaseOffset: 30
        )
        let stoppingDegrees = motion.degrees(at: stop, duration: 2)

        motion.update(isAnimating: false, at: stop, duration: 2)
        #expect(motion.degrees(at: resume, duration: 2) == stoppingDegrees)

        motion.update(isAnimating: true, at: resume, duration: 2)
        #expect(motion.degrees(at: resume, duration: 2) == stoppingDegrees)
        #expect(
            motion.degrees(at: Date(timeIntervalSince1970: 11), duration: 2)
                != stoppingDegrees
        )
    }

    @Test("Shows the three most recently active sources without truncating the count")
    func handlesMoreThanThreeActiveSources() {
        let summary = AgentActivitySummary(sessions: [
            session("claude", source: .claude, phase: .processing, lastActivity: 1),
            session("codex", source: .codex, phase: .processing, lastActivity: 2),
            session("cursor", source: .cursor, phase: .processing, lastActivity: 3),
            session("workbuddy", source: .workbuddy, phase: .processing, lastActivity: 4),
        ])

        #expect(summary.runningSessionCount == 4)
        #expect(summary.rings.compactMap(\.source) == [.codex, .cursor, .workbuddy])
        #expect(summary.activeSources == [.claude, .codex, .cursor, .workbuddy])
    }

    @Test("Ranks active sources by their active sessions")
    func ranksSourcesByActiveActivity() {
        let summary = AgentActivitySummary(sessions: [
            session("claude-active", source: .claude, phase: .processing, lastActivity: 1),
            session("claude-idle", source: .claude, phase: .idle, lastActivity: 100),
            session("codex", source: .codex, phase: .processing, lastActivity: 2),
            session("cursor", source: .cursor, phase: .processing, lastActivity: 3),
            session("workbuddy", source: .workbuddy, phase: .processing, lastActivity: 4),
        ])

        #expect(summary.rings.compactMap(\.source) == [.codex, .cursor, .workbuddy])
    }

    @Test("Keeps ring layers stable when activity timestamps change")
    func keepsRingLayersStable() {
        let first = AgentActivitySummary(sessions: [
            session("claude", source: .claude, phase: .processing, lastActivity: 1),
            session("codex", source: .codex, phase: .processing, lastActivity: 2),
            session("workbuddy", source: .workbuddy, phase: .processing, lastActivity: 3),
        ])
        let second = AgentActivitySummary(sessions: [
            session("claude", source: .claude, phase: .processing, lastActivity: 3),
            session("codex", source: .codex, phase: .processing, lastActivity: 2),
            session("workbuddy", source: .workbuddy, phase: .processing, lastActivity: 1),
        ])

        #expect(first.rings.map(\.source) == second.rings.map(\.source))
        #expect(first.rings.compactMap(\.source) == [.claude, .codex, .workbuddy])
    }

    @Test("Maps agents to the requested logo tint families")
    func mapsAgentTints() {
        #expect(SessionSource.claude.activityTint == .claudeOrange)
        #expect(SessionSource.codex.activityTint == .white)
        #expect(SessionSource.copilot.activityTint == .white)
        #expect(SessionSource.cursor.activityTint == .gray)
        #expect(SessionSource.pi.activityTint == .gray)
        #expect(SessionSource.opencode.activityTint == .gray)
        #expect(SessionSource.workbuddy.activityTint == .workBuddyGreen)
        #expect(SessionSource.qwenWork.activityTint == .workBuddyGreen)
        #expect(AgentActivityTint.claudeOrange.rgb == 0xD97757)
        #expect(AgentActivityTint.white.rgb == 0xFFFFFF)
        #expect(AgentActivityTint.gray.rgb == 0x8E8E93)
        #expect(AgentActivityTint.workBuddyGreen.rgb == 0x0EC8A9)
    }

    @Test("Renders as a compact notch component")
    @MainActor
    func rendersCompactComponent() {
        let summary = AgentActivitySummary(sessions: [
            session("claude", source: .claude, phase: .processing),
            session("codex", source: .codex, phase: .processing),
            session("workbuddy", source: .workbuddy, phase: .idle),
        ])
        let renderer = ImageRenderer(
            content: AgentActivityRings(summary: summary, size: 26)
                .frame(width: 26, height: 26)
                .background(.black)
        )
        renderer.scale = 2

        #expect(renderer.nsImage?.size == NSSize(width: 26, height: 26))
    }

    @Test("Renders a readable center count")
    @MainActor
    func rendersReadableCenterCount() throws {
        let sessions = (0..<8).map {
            session("claude-\($0)", source: .claude, phase: .processing)
        }
        let renderer = ImageRenderer(
            content: AgentActivityRings(
                summary: AgentActivitySummary(sessions: sessions),
                size: 26
            )
            .frame(width: 26, height: 26)
            .background(.black)
        )
        renderer.scale = 2

        let image = try #require(renderer.nsImage)
        let cgImage = try #require(
            image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        )
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        let centerX = bitmap.pixelsWide / 2
        let centerY = bitmap.pixelsHigh / 2
        var brightPixels = 0

        for x in (centerX - 10)..<(centerX + 10) {
            for y in (centerY - 10)..<(centerY + 10) {
                guard let color = bitmap.colorAt(x: x, y: y) else { continue }
                if color.brightnessComponent > 0.65, color.alphaComponent > 0.5 {
                    brightPixels += 1
                }
            }
        }

        #expect(brightPixels >= 45)
    }

    private func session(
        _ id: String,
        source: SessionSource,
        phase: SessionPhase,
        lastActivity: TimeInterval = 0
    ) -> SessionState {
        SessionState(
            sessionId: id,
            cwd: "/tmp/\(id)",
            source: source,
            phase: phase,
            lastActivity: Date(timeIntervalSince1970: lastActivity),
            createdAt: Date(timeIntervalSince1970: 0)
        )
    }
}
