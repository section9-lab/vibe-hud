//
//  NotificationSoundPlayer.swift
//  VibeHUD
//
//  Retains the active NSSound for its full playback lifecycle.
//

import AppKit
import os.log

@MainActor
final class NotificationSoundPlayer {
    static let shared = NotificationSoundPlayer()

    private let logger = Logger(subsystem: "com.vibehud", category: "Sound")
    private var activeSound: NSSound?

    private init() {}

    @discardableResult
    func playSelectedSound() -> Bool {
        play(AppSettings.notificationSound)
    }

    @discardableResult
    func play(_ selection: NotificationSound) -> Bool {
        guard let name = selection.soundName else {
            activeSound?.stop()
            activeSound = nil
            return true
        }

        activeSound?.stop()

        let systemURL = URL(fileURLWithPath: "/System/Library/Sounds")
            .appendingPathComponent(name)
            .appendingPathExtension("aiff")
        let sound = NSSound(contentsOf: systemURL, byReference: true)
            ?? NSSound(named: NSSound.Name(name))

        guard let sound else {
            logger.error("Sound resource not found: \(name, privacy: .public)")
            return false
        }

        activeSound = sound
        let started = sound.play()
        if !started {
            logger.error("Sound playback failed: \(name, privacy: .public)")
        }
        return started
    }
}
