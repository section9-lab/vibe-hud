//
//  SessionPhase.swift
//  VibeHUD
//
//  Minimal lifecycle states derived only from hook events.
//

import Foundation

enum SessionPhase: String, Equatable, Sendable {
    case idle
    case processing
    case waitingForInput
    case compacting
    case ended

    nonisolated var needsAttention: Bool {
        self == .waitingForInput
    }

    nonisolated var isActive: Bool {
        self == .processing || self == .compacting
    }
}

extension SessionPhase: CustomStringConvertible {
    nonisolated var description: String { rawValue }
}
