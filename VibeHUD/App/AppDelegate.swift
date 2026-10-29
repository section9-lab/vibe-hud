import AppKit
import Combine
import Darwin
import IOKit
#if canImport(Mixpanel) && !VIBEHUD_LOCAL
import Mixpanel
#endif
import Sparkle
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowManager: WindowManager?
    private var screenObserver: ScreenObserver?
    private var takeoverTimer: Timer?
    private var updateCheckTimer: Timer?
    private var launchedWithTakeover = false
    private var forcedPreview = false
    private var tiboNetworkingSubscription: AnyCancellable?
    private var didInitializeMixpanel = false

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
        if !AppRuntime.isLocalBuild && !AppRuntime.isPreview
            && Foundation.ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            do { try updater.start() }
            catch { print("Failed to start Sparkle updater: \(error)") }
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

        if !AppRuntime.isLocalBuild && !AppRuntime.isPreview { initializeUpstreamTelemetry() }

        NSApplication.shared.setActivationPolicy(.accessory)

        forcedPreview = Foundation.ProcessInfo.processInfo.arguments.contains("--preview")
            || Foundation.ProcessInfo.processInfo.environment["FDAR_USAGE_PREVIEW"] == "1"
        UserDefaults.standard.synchronize()
        launchedWithTakeover = !forcedPreview && (!AppRuntime.isLocalBuild
            || !AppRuntime.requiresTakeover
            || UserDefaults.standard.bool(forKey: "usageNotch.nativeTakeover"))
        if !launchedWithTakeover {
            setenv("FDAR_USAGE_PREVIEW", "1", 1)
            configurePreviewLanguage()
        }
        let store = launchedWithTakeover ? MonitoringStore.shared : MonitoringStore.preview()
        tiboNetworkingSubscription = AppPreferences.shared.$tiboNetworking.sink { enabled in
            store.collectTibo = enabled
        }
        let hasPreviewPage = Foundation.ProcessInfo.processInfo.arguments.contains {
            $0.hasPrefix("--preview-page=")
        }
        if !AppRuntime.isLocalBuild && launchedWithTakeover { HookInstaller.installIfNeeded() }
        windowManager = WindowManager(
            preferences: AppPreferences.shared,
            monitoringStore: store,
            animateOnLaunch: !hasPreviewPage
        )
        _ = windowManager?.setupNotchWindow()
        if !launchedWithTakeover {
            presentPreviewPage()
        }

        screenObserver = ScreenObserver { [weak self] in
            Task { @MainActor in
                self?.handleScreenChange()
            }
        }

        if launchedWithTakeover {
            MonitoringStore.shared.start()
        }
        if AppRuntime.isLocalBuild && AppRuntime.requiresTakeover {
            takeoverTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) {
                [weak self] _ in
                Task { @MainActor in self?.checkTakeoverChange() }
            }
        } else if !AppRuntime.isLocalBuild && !forcedPreview {
            if updater.canCheckForUpdates { updater.checkForUpdates() }
            updateCheckTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) {
                [weak self] _ in
                guard let updater = self?.updater, updater.canCheckForUpdates else { return }
                updater.checkForUpdates()
            }
        }

    }

    @MainActor
    private func handleScreenChange() {
        _ = windowManager?.setupNotchWindow()
    }

    @MainActor
    private func configurePreviewLanguage() {
        let argument = Foundation.ProcessInfo.processInfo.arguments.first {
            $0.hasPrefix("--preview-language=")
        }
        guard let value = argument?.split(separator: "=", maxSplits: 1).last,
              value == "zh" || value == "en" else { return }
        let language = value == "zh" ? "zh-Hans" : "en"
        UserDefaults(suiteName: AppRuntime.previewSuite)?
            .set(language, forKey: "usageHUD.language")
    }

    @MainActor
    private func presentPreviewPage() {
        guard let argument = Foundation.ProcessInfo.processInfo.arguments.first(where: {
            $0.hasPrefix("--preview-page=")
        }), let page = argument.split(separator: "=", maxSplits: 1).last,
              let model = windowManager?.windowController?.viewModel else { return }
        switch page {
        case "settings":
            model.notchOpen(reason: .click)
            model.toggleMenu()
        case "overview": model.showMonitoring(.overview, reason: .click)
        case "claude": model.showMonitoring(.claude, reason: .click)
        case "codex": model.showMonitoring(.codex, reason: .click)
        case "speed": model.showMonitoring(.speed, reason: .click)
        case "tibo": model.showMonitoring(.tibo, reason: .click)
        default: break
        }
    }

    @MainActor
    private func checkTakeoverChange() {
        guard !forcedPreview, AppRuntime.requiresTakeover else { return }
        UserDefaults.standard.synchronize()
        let enabled = UserDefaults.standard.bool(forKey: "usageNotch.nativeTakeover")
        if enabled != launchedWithTakeover {
            NSApplication.shared.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        #if canImport(Mixpanel) && !VIBEHUD_LOCAL
        if didInitializeMixpanel { Mixpanel.mainInstance().flush() }
        #endif
        takeoverTimer?.invalidate()
        updateCheckTimer?.invalidate()
        tiboNetworkingSubscription = nil
        if launchedWithTakeover {
            MonitoringStore.shared.stop()
        }
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

    private func initializeUpstreamTelemetry() {
        #if canImport(Mixpanel) && !VIBEHUD_LOCAL
        // The upstream Xcode target supplies Mixpanel; local SwiftPM builds omit it.
        Mixpanel.initialize(token: "49814c1436104ed108f3fc4735228496")
        didInitializeMixpanel = true
        Mixpanel.mainInstance().identify(distinctId: getOrCreateDistinctId())
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        let osVersion = Foundation.ProcessInfo.processInfo.operatingSystemVersionString
        Mixpanel.mainInstance().registerSuperProperties([
            "app_version": version, "build_number": build, "macos_version": osVersion,
        ])
        fetchAndRegisterClaudeVersion()
        Mixpanel.mainInstance().people.set(properties: [
            "app_version": version, "build_number": build, "macos_version": osVersion,
        ])
        Mixpanel.mainInstance().track(event: "App Launched")
        Mixpanel.mainInstance().flush()
        #endif
    }

    #if canImport(Mixpanel) && !VIBEHUD_LOCAL
    private func getOrCreateDistinctId() -> String {
        let key = "mixpanel_distinct_id"

        if let existingId = UserDefaults.standard.string(forKey: key) {
            return existingId
        }

        let platformExpert = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPlatformExpertDevice")
        )
        defer { IOObjectRelease(platformExpert) }

        if let uuid = IORegistryEntryCreateCFProperty(
            platformExpert,
            kIOPlatformUUIDKey as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? String {
            UserDefaults.standard.set(uuid, forKey: key)
            return uuid
        }

        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: key)
        return newId
    }

    private func fetchAndRegisterClaudeVersion() {
        let claudeProjectsDir = ClaudePaths.projectsDir

        guard
            let projectDirs = try? FileManager.default.contentsOfDirectory(
                at: claudeProjectsDir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: .skipsHiddenFiles
            )
        else { return }

        var latestFile: URL?
        var latestDate: Date?

        for projectDir in projectDirs {
            guard
                let files = try? FileManager.default.contentsOfDirectory(
                    at: projectDir,
                    includingPropertiesForKeys: [.contentModificationDateKey],
                    options: .skipsHiddenFiles
                )
            else { continue }

            for file in files
            where file.pathExtension == "jsonl" && !file.lastPathComponent.hasPrefix("agent-") {
                if let attrs = try? file.resourceValues(forKeys: [.contentModificationDateKey]),
                    let modDate = attrs.contentModificationDate
                {
                    if latestDate == nil || modDate > latestDate! {
                        latestDate = modDate
                        latestFile = file
                    }
                }
            }
        }

        guard let jsonlFile = latestFile,
            let handle = FileHandle(forReadingAtPath: jsonlFile.path)
        else { return }
        defer { try? handle.close() }

        let data = handle.readData(ofLength: 8192)
        guard let content = String(data: data, encoding: .utf8) else { return }

        for line in content.components(separatedBy: .newlines) where !line.isEmpty {
            guard let lineData = line.data(using: .utf8),
                let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                let version = json["version"] as? String
            else { continue }

            Mixpanel.mainInstance().registerSuperProperties(["claude_code_version": version])
            Mixpanel.mainInstance().people.set(properties: ["claude_code_version": version])
            return
        }
    }

    #endif
}
