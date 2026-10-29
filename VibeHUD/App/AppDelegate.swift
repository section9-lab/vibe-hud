import AppKit
import Darwin
import Sparkle
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowManager: WindowManager?
    private var screenObserver: ScreenObserver?

    static var shared: AppDelegate?
    let updater: SPUUpdater
    private let userDriver: NotchUserDriver

    @MainActor
    var windowController: NotchWindowController? {
        windowManager?.windowController
    }

    override init() {
        userDriver = NotchUserDriver()
        updater = SPUUpdater(
            hostBundle: Bundle.main,
            applicationBundle: Bundle.main,
            userDriver: userDriver,
            delegate: nil
        )
        super.init()
        AppDelegate.shared = self

        do {
            try updater.start()
            if Foundation.ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
               updater.automaticallyChecksForUpdates, updater.canCheckForUpdates {
                updater.checkForUpdatesInBackground()
            }
        } catch {
            print("Failed to start Sparkle updater: \(error)")
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if Foundation.ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return
        }

        if !ensureSingleInstance() {
            NSApplication.shared.terminate(nil)
            return
        }

        AppAnalytics.shared.start()

        HookInstaller.installIfNeeded()
        NSApplication.shared.setActivationPolicy(.accessory)

        windowManager = WindowManager()
        _ = windowManager?.setupNotchWindow()

        screenObserver = ScreenObserver { [weak self] in
            Task { @MainActor in
                self?.handleScreenChange()
            }
        }
    }

    @MainActor
    private func handleScreenChange() {
        _ = windowManager?.setupNotchWindow()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppAnalytics.shared.flush()
        screenObserver = nil
    }

    private func ensureSingleInstance() -> Bool {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.section9-lab.VibeHUD"
        let otherInstance = NSWorkspace.shared.runningApplications.first {
            $0.bundleIdentifier == bundleID && $0.processIdentifier != getpid()
        }

        if let existingApp = otherInstance {
            existingApp.activate()
            return false
        }

        return true
    }
}
