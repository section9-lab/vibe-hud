//
//  WindowManager.swift
//  VibeHUD
//
//  Manages the notch window lifecycle
//

import AppKit
import os.log

/// Logger for window management
private let logger = Logger(subsystem: "com.vibehud", category: "Window")

@MainActor
class WindowManager {
    private(set) var windowController: NotchWindowController?
    private var isInitialLaunch: Bool
    private var currentScreenFrame: NSRect?
    private let preferences: AppPreferences
    private let monitoringStore: MonitoringStore

    init(preferences: AppPreferences, monitoringStore: MonitoringStore,
         animateOnLaunch: Bool = true) {
        self.preferences = preferences
        self.monitoringStore = monitoringStore
        self.isInitialLaunch = animateOnLaunch
    }

    /// Set up or recreate the notch window
    func setupNotchWindow() -> NotchWindowController? {
        // Use ScreenSelector for screen selection
        let screenSelector = ScreenSelector.shared
        screenSelector.refreshScreens()

        guard let screen = screenSelector.selectedScreen else {
            logger.warning("No screen found")
            return nil
        }

        // Skip recreation if screen hasn't meaningfully changed
        if let existingController = windowController,
           let existingFrame = currentScreenFrame,
           existingFrame == screen.frame {
            logger.debug("Screen unchanged, skipping window recreation")
            return existingController
        }

        // Only animate on initial app launch, not on screen changes
        let shouldAnimate = isInitialLaunch
        isInitialLaunch = false

        if let existingController = windowController {
            existingController.window?.orderOut(nil)
            existingController.window?.close()
            windowController = nil
        }

        currentScreenFrame = screen.frame
        windowController = NotchWindowController(
            screen: screen,
            animateOnLaunch: shouldAnimate,
            preferences: preferences,
            monitoringStore: monitoringStore
        )
        windowController?.showWindow(nil)

        return windowController
    }
}
