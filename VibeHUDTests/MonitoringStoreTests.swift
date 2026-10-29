import Foundation
import Testing
@testable import vibe_hud

@Suite("Monitoring data and delivery", .serialized)
@MainActor
struct MonitoringStoreTests {
    private let now = ISO8601DateFormatter().date(from: "2026-10-27T02:00:00Z")!

    @Test("Quota percentages clamp and a passed reset retains its last measured value")
    func quotaDecode() throws {
        let payload = Data("""
        {"updated_at":1793065800,"windows":{"five_hour":{"used_percentage":125,"resets_at":1793060000},"seven_day":{"used_percentage":35,"resets_at":1793100000}},"daily_performance":{"day":"2026-10-27","metric":"output_generation","status":"ok","tokens_per_second":42.5}}
        """.utf8)
        let quota = try MonitoringDecoder.quota(payload, now: now)
        #expect(quota.window(.fiveHour)?.remainingPercent == 0)
        #expect(quota.window(.fiveHour)?.isStale == true)
        #expect(quota.window(.fiveHour)?.resetsAt == nil)
        #expect(quota.window(.sevenDay)?.remainingPercent == 65)
        #expect(quota.tokensPerSecond == 42.5)
        #expect(quota.window(.sevenDay)?.isStale == false)
        #expect(try MonitoringDecoder.quota(payload, now: now, staleAfter: 300)
            .window(.sevenDay)?.isStale == true)
    }

    @Test("Zero speed and another Shanghai day are unavailable")
    func invalidSpeed() throws {
        let base = """
        {"updated_at":1793065800,"windows":{},"daily_performance":{"day":"DAY","metric":"output_generation","status":"ok","tokens_per_second":RATE}}
        """
        #expect(try MonitoringDecoder.quota(Data(base.replacingOccurrences(of: "DAY", with: "2026-10-27")
            .replacingOccurrences(of: "RATE", with: "0").utf8), now: now).tokensPerSecond == nil)
        #expect(try MonitoringDecoder.quota(Data(base.replacingOccurrences(of: "DAY", with: "2026-10-26")
            .replacingOccurrences(of: "RATE", with: "42").utf8), now: now).tokensPerSecond == nil)
    }

    @Test("A removed quota cache cannot leave a fresh ring frozen indefinitely")
    func removedCache() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "MonitoringStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let cache = root.appendingPathComponent("codex.json")
        try Data("""
        {"updated_at":1793065800,"windows":{"seven_day":{"used_percentage":88,"resets_at":1793599673}}}
        """.utf8).write(to: cache)
        let store = MonitoringStore(paths: MonitoringPaths(runtimeRoot: root, cacheRoot: root),
                                    defaults: defaults, legacyDefaults: nil)
        store.reloadFromDisk(now: now)
        #expect(store.codex.window(.sevenDay)?.remainingPercent == 12)
        try FileManager.default.removeItem(at: cache)
        store.reloadFromDisk(now: now)
        #expect(store.codex.windows.isEmpty)
    }

    @Test("Preview never reads or persists live monitoring state")
    func previewIsolation() {
        let preview = MonitoringStore.preview()
        preview.start()
        preview.tick(now: now)
        preview.dismissTiboAlert("1234567890")
        #expect(preview.isPreview)
        #expect(preview.tibo.alert == nil)
    }

    @Test("Tibo pending alert survives reconstruction until dismissal")
    func persistenceAndDedup() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cache = root.appendingPathComponent("cache")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "MonitoringStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let tiboJSON = """
        {"version":1,"status":"ok","last_success":1793065800,"alert":{"id":"1234567890123456789","kind":"planned","text":"Codex reset planned","url":"https://x.com/thsottiaux/status/1234567890123456789","at":1793065800}}
        """
        try Data(tiboJSON.utf8).write(to: cache.appendingPathComponent("tibo-reset.json"))
        let paths = MonitoringPaths(runtimeRoot: root, cacheRoot: cache)
        let first = MonitoringStore(paths: paths, defaults: defaults, legacyDefaults: nil)
        first.reloadFromDisk(now: now)
        #expect(!first.tibo.shouldPresent) // Existing cache establishes a silent baseline.
        #expect(defaults.string(forKey: "monitoring.tibo.pendingID") == nil)
        let nextAlert = tiboJSON.replacingOccurrences(of: "1234567890123456789", with: "1234567890123456790")
        try Data(nextAlert.utf8).write(to: cache.appendingPathComponent("tibo-reset.json"))
        first.reloadFromDisk(now: now)
        #expect(first.tibo.shouldPresent)
        #expect(defaults.string(forKey: "monitoring.tibo.pendingID") == "1234567890123456790")
        first.reloadFromDisk(now: now)
        #expect(first.tibo.shouldPresent)
        let second = MonitoringStore(paths: paths, defaults: defaults, legacyDefaults: nil)
        second.reloadFromDisk(now: now)
        #expect(second.tibo.shouldPresent)
        second.dismissTiboAlert("1234567890123456790")
        #expect(!second.tibo.shouldPresent)
        #expect(defaults.string(forKey: "monitoring.tibo.pendingID") == nil)
        let third = MonitoringStore(paths: paths, defaults: defaults, legacyDefaults: nil)
        third.reloadFromDisk(now: now)
        #expect(!third.tibo.shouldPresent)
        third.importLegacyState(tiboDismissedID: "1234567890123456789")
        #expect(!third.tibo.shouldPresent)
    }

    @Test("Legacy dismissal migrates without presenting an existing cache")
    func legacyDismissalMigration() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "MonitoringStoreTests.\(UUID().uuidString)"
        let legacySuite = "MonitoringStoreTests.legacy.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let legacyDefaults = UserDefaults(suiteName: legacySuite)!
        defer {
            defaults.removePersistentDomain(forName: suite)
            legacyDefaults.removePersistentDomain(forName: legacySuite)
        }
        legacyDefaults.set("1234567890123456789", forKey: "usageHUD.resetDismissed")
        let cache = root.appendingPathComponent("tibo-reset.json")
        try Data("""
        {"version":1,"status":"ok","last_success":1793065800,"alert":{"id":"1234567890123456789","kind":"planned","text":"Codex reset planned","url":"https://x.com/thsottiaux/status/1234567890123456789","at":1793065800}}
        """.utf8).write(to: cache)
        let store = MonitoringStore(paths: MonitoringPaths(runtimeRoot: root, cacheRoot: root),
                                    defaults: defaults, legacyDefaults: legacyDefaults)
        store.reloadFromDisk(now: now)
        #expect(!store.tibo.shouldPresent)
        #expect(defaults.string(forKey: "monitoring.tibo.dismissedID") == "1234567890123456789")
        #expect(defaults.string(forKey: "monitoring.tibo.pendingID") == nil)
    }

}
