import AppKit
import Combine
import Darwin
import Foundation

struct MonitoringPaths: Sendable {
    let runtimeRoot: URL
    let cacheRoot: URL

    static var live: MonitoringPaths {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let defaultCache = support.appendingPathComponent("VibeHUD/Monitoring", isDirectory: true)
        let configuredCache = Bundle.main.object(forInfoDictionaryKey: "VibeHUDMonitoringCachePath") as? String
        let cache = configuredCache.flatMap { path -> URL? in
            guard !path.isEmpty else { return nil }
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        } ?? defaultCache
        return MonitoringPaths(runtimeRoot: Bundle.main.resourceURL ?? support,
                               cacheRoot: cache)
    }

    var scripts: URL { runtimeRoot }
    var claudeCache: URL { cacheRoot.appendingPathComponent("claude.json") }
    var codexCache: URL { cacheRoot.appendingPathComponent("codex.json") }
    var tiboCache: URL { cacheRoot.appendingPathComponent("tibo-reset.json") }
}

@MainActor
final class MonitoringStore: ObservableObject {
    static let shared = MonitoringStore()

    @Published private(set) var claude = QuotaSnapshot.empty
    @Published private(set) var codex = QuotaSnapshot.empty
    @Published private(set) var tibo = TiboMonitorState.empty

    /// Collection switches are independent of menu and card visibility.
    @Published var collectCodex = true
    @Published var collectClaude = true
    @Published var collectTibo = true {
        didSet {
            if !collectTibo {
                tiboTask?.cancel()
            } else if !oldValue, timer != nil {
                lastTiboStart = nil
                tick()
            }
        }
    }

    let isPreview: Bool
    private let paths: MonitoringPaths?
    private let defaults: UserDefaults?
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var codexTask: Task<Void, Never>?
    private var claudeTask: Task<Void, Never>?
    private var tiboTask: Task<Void, Never>?
    private var lastCodexStart: Date?
    private var lastClaudeStart: Date?
    private var lastTiboStart: Date?
    private var dismissedTiboID: String?
    private var pendingTiboID: String?
    private var observedTiboID: String?
    private var hasLoadedTibo = false

    private enum Keys {
        static let tiboDismissed = "monitoring.tibo.dismissedID"
        static let tiboPending = "monitoring.tibo.pendingID"
    }

    init(paths: MonitoringPaths = .live, defaults: UserDefaults = .standard,
         legacyDefaults: UserDefaults? = nil,
         preview: Bool = false) {
        isPreview = preview
        self.paths = preview ? nil : paths
        self.defaults = preview ? nil : defaults
        if preview {
            dismissedTiboID = nil
            pendingTiboID = nil
        } else {
            dismissedTiboID = defaults.string(forKey: Keys.tiboDismissed) ??
                              legacyDefaults?.string(forKey: "usageHUD.resetDismissed")
            if let dismissedTiboID { defaults.set(dismissedTiboID, forKey: Keys.tiboDismissed) }
            pendingTiboID = defaults.string(forKey: Keys.tiboPending)
        }
    }

    private init(previewOnly: Void) {
        isPreview = true
        paths = nil
        defaults = nil
    }

    static func preview() -> MonitoringStore {
        let store = MonitoringStore(previewOnly: ())
        let now = Date()
        store.claude = QuotaSnapshot(
            updatedAt: now,
            windows: [
                .fiveHour: QuotaWindow(usedPercent: 32, remainingPercent: 68,
                                       resetsAt: now.addingTimeInterval(7200), isStale: false),
                .sevenDay: QuotaWindow(usedPercent: 61, remainingPercent: 39,
                                       resetsAt: now.addingTimeInterval(4 * 86400), isStale: false)
            ],
            tokensPerSecond: nil,
            errorCode: nil
        )
        store.codex = QuotaSnapshot(
            updatedAt: now,
            windows: [
                .sevenDay: QuotaWindow(usedPercent: 47, remainingPercent: 53,
                                       resetsAt: now.addingTimeInterval(3 * 86400), isStale: false)
            ],
            tokensPerSecond: 74.4,
            errorCode: nil
        )
        store.tibo = TiboMonitorState(
            alert: TiboAlert(
                id: "1234567890123456789",
                kind: "reported",
                text: "Preview sample: a Codex quota reset was reported.",
                url: URL(string: "https://x.com/thsottiaux/status/1234567890123456789")!,
                postedAt: now.addingTimeInterval(-1800)
            ),
            shouldPresent: false,
            lastSuccess: now,
            isStale: false,
            errorCode: nil
        )
        return store
    }

    func start() {
        guard !isPreview, timer == nil else { return }
        reloadFromDisk()
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
        codexTask?.cancel()
        claudeTask?.cancel()
        tiboTask?.cancel()
    }

    /// Read caches without starting processes. Safe to call when the view reopens.
    func reloadFromDisk(now: Date = Date()) {
        guard let paths else { return }
        if let data = try? Data(contentsOf: paths.claudeCache),
           let snapshot = try? MonitoringDecoder.quota(data, now: now) {
            claude = snapshot
        } else {
            claude = .empty
        }
        if let data = try? Data(contentsOf: paths.codexCache),
           let snapshot = try? MonitoringDecoder.quota(data, now: now) {
            codex = snapshot
        } else {
            codex = .empty
        }
        reloadTibo(now: now)
    }

    func tick(now: Date = Date()) {
        guard !isPreview, let paths else { return }
        reloadFromDisk(now: now)
        if collectCodex && codexTask == nil && due(lastCodexStart, interval: 120, now: now) {
            lastCodexStart = now
            codexTask = Task { [weak self] in
                let result = await MonitoringProcess.run(script: paths.scripts.appendingPathComponent("codex_usage.py"),
                                                         arguments: ["--write", "--cache", paths.codexCache.path], timeout: 30)
                guard let self else { return }
                self.codexTask = nil
                if Task.isCancelled { return }
                if case .success(let data) = result,
                   let snapshot = try? MonitoringDecoder.quota(data) { self.codex = snapshot }
                else if self.codex.windows.isEmpty {
                    self.codex = QuotaSnapshot(updatedAt: nil, windows: [:], tokensPerSecond: nil,
                                               errorCode: "collector_failed")
                }
            }
        }
        if collectClaude && claudeTask == nil && due(lastClaudeStart, interval: 120, now: now) {
            lastClaudeStart = now
            claudeTask = Task { [weak self] in
                let result = await MonitoringProcess.run(script: paths.scripts.appendingPathComponent("claude_speed.py"),
                                                         arguments: ["--write", "--cache", paths.claudeCache.path], timeout: 30)
                guard let self else { return }
                self.claudeTask = nil
                if Task.isCancelled { return }
                if case .success(let data) = result,
                   let snapshot = try? MonitoringDecoder.quota(data) { self.claude = snapshot }
                else if self.claude.windows.isEmpty {
                    self.claude = QuotaSnapshot(updatedAt: nil, windows: [:], tokensPerSecond: nil,
                                               errorCode: "collector_failed")
                }
            }
        }
        if collectTibo && tiboTask == nil && due(lastTiboStart, interval: 120, now: now) {
            lastTiboStart = now
            tiboTask = Task { [weak self] in
                let result = await MonitoringProcess.run(script: paths.scripts.appendingPathComponent("tibo_reset.py"),
                                                         arguments: ["--cache", paths.tiboCache.path], timeout: 18)
                guard let self else { return }
                self.tiboTask = nil
                if Task.isCancelled { return }
                self.reloadTibo()
                if case .failure = result {
                    self.tibo = TiboMonitorState(alert: self.tibo.alert,
                                                 shouldPresent: self.tibo.shouldPresent,
                                                 lastSuccess: self.tibo.lastSuccess,
                                                 isStale: self.tibo.isStale,
                                                 errorCode: "collector_failed")
                }
            }
        }
    }

    func dismissTiboAlert(_ id: String) {
        guard !isPreview, tibo.alert?.id == id else { return }
        dismissedTiboID = id
        defaults?.set(id, forKey: Keys.tiboDismissed)
        if pendingTiboID == id {
            pendingTiboID = nil
            defaults?.removeObject(forKey: Keys.tiboPending)
        }
        tibo = TiboMonitorState(alert: tibo.alert, shouldPresent: false,
                                lastSuccess: tibo.lastSuccess, isStale: tibo.isStale,
                                errorCode: tibo.errorCode)
        reloadTibo()
    }

    /// Settings migration calls this once with Hammerspoon's stored keys.
    func importLegacyState(tiboDismissedID: String?) {
        guard !isPreview else { return }
        if dismissedTiboID == nil, let tiboDismissedID {
            dismissedTiboID = tiboDismissedID
            defaults?.set(tiboDismissedID, forKey: Keys.tiboDismissed)
        }
        reloadTibo()
    }

    private func reloadTibo(now: Date = Date()) {
        guard let paths, let data = try? Data(contentsOf: paths.tiboCache),
              var state = try? MonitoringDecoder.tibo(data, now: now) else { return }
        let isNewAlert = hasLoadedTibo && state.alert != nil && state.alert?.id != observedTiboID
        if state.alert != nil { observedTiboID = state.alert?.id }
        hasLoadedTibo = true
        if isNewAlert, let id = state.alert?.id, id != dismissedTiboID {
            pendingTiboID = id
            defaults?.set(id, forKey: Keys.tiboPending)
        }
        state = TiboMonitorState(alert: state.alert,
                                 shouldPresent: state.alert.map {
                                     $0.id == pendingTiboID && $0.id != dismissedTiboID
                                 } == true,
                                 lastSuccess: state.lastSuccess, isStale: state.isStale,
                                 errorCode: state.errorCode)
        tibo = state
    }

    private func due(_ last: Date?, interval: TimeInterval, now: Date) -> Bool {
        last.map { now.timeIntervalSince($0) >= interval } ?? true
    }

}

private enum MonitoringProcess {
    enum ProcessFailure: Error { case collectorFailed }

    private final class OutputBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()

        func drain(_ handle: FileHandle, limit: Int) {
            while true {
                let chunk = handle.readData(ofLength: 4096)
                if chunk.isEmpty { break }
                lock.lock()
                if data.count < limit { data.append(chunk.prefix(limit - data.count)) }
                lock.unlock()
            }
        }

        var value: Data {
            lock.lock()
            defer { lock.unlock() }
            return data
        }
    }

    private final class ProcessBox: @unchecked Sendable {
        private let lock = NSLock()
        private var process: Process?
        private var cancelled = false

        func attach(_ process: Process) {
            lock.lock()
            self.process = process
            let shouldCancel = cancelled
            lock.unlock()
            if shouldCancel { stop(process) }
        }

        func cancel() {
            lock.lock()
            cancelled = true
            let process = self.process
            lock.unlock()
            if let process { stop(process) }
        }

        private func stop(_ process: Process) {
            guard process.isRunning else { return }
            process.terminate()
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) {
                if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
            }
        }
    }

    static func run(script: URL, arguments: [String], timeout: TimeInterval) async -> Result<Data, ProcessFailure> {
        let box = ProcessBox()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
                    process.arguments = ["-I", script.path] + arguments
                    let output = Pipe()
                    let errors = Pipe()
                    process.standardOutput = output
                    process.standardError = errors
                    do {
                        try process.run()
                        box.attach(process)
                        let group = DispatchGroup()
                        let stdout = OutputBuffer()
                        group.enter()
                        DispatchQueue.global(qos: .utility).async {
                            stdout.drain(output.fileHandleForReading, limit: 1_048_576)
                            group.leave()
                        }
                        group.enter()
                        DispatchQueue.global(qos: .utility).async {
                            // Never retain or log collector stderr content.
                            OutputBuffer().drain(errors.fileHandleForReading, limit: 0)
                            group.leave()
                        }
                        let timeoutWork = DispatchWorkItem { box.cancel() }
                        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout,
                                                                        execute: timeoutWork)
                        process.waitUntilExit()
                        timeoutWork.cancel()
                        _ = group.wait(timeout: .now() + 2)
                        continuation.resume(returning: process.terminationStatus == 0
                            ? .success(stdout.value) : .failure(.collectorFailed))
                    } catch {
                        continuation.resume(returning: .failure(.collectorFailed))
                    }
                }
            }
        } onCancel: {
            box.cancel()
        }
    }
}
