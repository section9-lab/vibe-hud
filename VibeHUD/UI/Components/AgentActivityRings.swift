import SwiftUI

struct AgentActivityRings: View {
    let summary: AgentActivitySummary
    let size: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(summary: AgentActivitySummary, size: CGFloat = 26) {
        self.summary = summary
        self.size = size
    }

    var body: some View {
        ZStack {
            TimelineView(
                .animation(
                    minimumInterval: 1 / 60,
                    paused: reduceMotion || !summary.rings.contains(where: \.isActive)
                )
            ) { timeline in
                ZStack {
                    ForEach(Array(summary.rings.enumerated()), id: \.offset) { index, ring in
                        AgentActivityRing(
                            ring: ring,
                            diameter: size - CGFloat(index) * (size * 0.21),
                            lineWidth: max(1.4, size * 0.075),
                            duration: 2.6 - Double(index) * 0.45,
                            phaseOffset: Double(index) * 68,
                            timelineDate: timeline.date,
                            isAnimating: ring.isActive && !reduceMotion
                        )
                    }
                }
            }

            Text("\(summary.runningSessionCount)")
                .font(.system(size: size * 0.25, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .frame(width: size * 0.29, height: size * 0.29)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Agent activity")
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        let activeSources = summary.activeSources
            .map(\.displayName)
            .joined(separator: ", ")

        if activeSources.isEmpty {
            return "No running sessions"
        }
        let overflowDescription = summary.activeSources.count > 3
            ? ". Rings show the three most recently active agent types"
            : ""
        return "\(summary.runningSessionCount) running sessions: \(activeSources)\(overflowDescription)"
    }
}

private struct AgentActivityRing: View {
    let ring: AgentActivitySummary.Ring
    let diameter: CGFloat
    let lineWidth: CGFloat
    let duration: TimeInterval
    let phaseOffset: Double
    let timelineDate: Date
    let isAnimating: Bool

    @State private var motion: AgentActivityRingMotion?

    var body: some View {
        Group {
            if ring.hasGap {
                Circle()
                    .trim(from: 0.055, to: 0.925)
                    .stroke(
                        ringGradient,
                        style: StrokeStyle(
                            lineWidth: lineWidth,
                            lineCap: .round
                        )
                    )
                    .rotationEffect(rotation)
            } else {
                Circle()
                    .stroke(ringGradient, lineWidth: lineWidth)
            }
        }
        .frame(width: diameter, height: diameter)
        .onAppear {
            motion = AgentActivityRingMotion(
                isAnimating: isAnimating,
                at: timelineDate,
                phaseOffset: phaseOffset
            )
        }
        .onChange(of: motionKey) { oldValue, newValue in
            let now = Date()
            if oldValue.source != newValue.source || motion == nil {
                motion = AgentActivityRingMotion(
                    isAnimating: newValue.isAnimating,
                    at: now,
                    phaseOffset: phaseOffset
                )
            } else {
                motion?.update(
                    isAnimating: newValue.isAnimating,
                    at: now,
                    duration: duration
                )
            }
        }
    }

    private var ringGradient: AngularGradient {
        let opacity = ring.source == nil ? 0.18 : (ring.isActive ? 1 : 0.72)
        return AngularGradient(
            colors: [
                ringColor.opacity(opacity * 0.58),
                ringColor.opacity(opacity),
                ringColor.opacity(opacity * 0.78),
            ],
            center: .center
        )
    }

    private var ringColor: Color {
        ring.source?.activityTint.color ?? .white
    }

    private var rotation: Angle {
        let currentMotion = motion ?? AgentActivityRingMotion(
            isAnimating: isAnimating,
            at: timelineDate,
            phaseOffset: phaseOffset
        )
        return .degrees(currentMotion.degrees(at: timelineDate, duration: duration))
    }

    private var motionKey: AgentActivityRingMotionKey {
        AgentActivityRingMotionKey(
            source: ring.source,
            isAnimating: isAnimating
        )
    }
}

struct AgentActivityRingMotion: Equatable {
    private var baseDegrees: Double
    private var activeSince: Date?

    init(isAnimating: Bool, at date: Date, phaseOffset: Double) {
        baseDegrees = phaseOffset
        activeSince = isAnimating ? date : nil
    }

    mutating func update(
        isAnimating: Bool,
        at date: Date,
        duration: TimeInterval
    ) {
        if isAnimating {
            if activeSince == nil {
                activeSince = date
            }
        } else if activeSince != nil {
            baseDegrees = degrees(at: date, duration: duration)
            activeSince = nil
        }
    }

    func degrees(at date: Date, duration: TimeInterval) -> Double {
        guard let activeSince, duration > 0 else {
            return baseDegrees
        }
        let elapsed = max(0, date.timeIntervalSince(activeSince))
        return (baseDegrees + elapsed / duration * 360)
            .truncatingRemainder(dividingBy: 360)
    }
}

private struct AgentActivityRingMotionKey: Equatable {
    let source: SessionSource?
    let isAnimating: Bool
}

private extension AgentActivityTint {
    var color: Color {
        Color(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}
