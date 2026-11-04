import Foundation
import Testing
@testable import vibe_hud

@Suite("JSONL interrupt watching")
struct JSONLInterruptWatcherTests {
    @Test("Only JSONL transcripts are eligible; OpenCode is never watched")
    func watchEligibility() {
        #expect(JSONLInterruptWatcher.shouldWatch(source: nil, transcriptPath: nil))
        #expect(JSONLInterruptWatcher.shouldWatch(source: "claude", transcriptPath: "/tmp/session.jsonl"))
        #expect(JSONLInterruptWatcher.shouldWatch(source: "pi", transcriptPath: "/tmp/session.jsonl"))
        #expect(!JSONLInterruptWatcher.shouldWatch(source: "opencode", transcriptPath: "/tmp/session.jsonl"))
        #expect(!JSONLInterruptWatcher.shouldWatch(source: nil, transcriptPath: "/Users/test/.local/share/opencode/opencode.db"))
        #expect(!JSONLInterruptWatcher.shouldWatch(source: "claude", transcriptPath: "/tmp/opencode.db"))
    }

    @Test("Scans split lines and split UTF-8 without replaying malformed lines")
    func incrementalLines() {
        var scanner = JSONLInterruptScanner()
        let data = Data("{\"type\":\"user\",\"text\":\"你好 [Request interrupted by user]\"}\n".utf8)
        let split = data.firstIndex(of: 0xe4) ?? 0
        let first = scanner.consume(data.prefix(split + 1))
        let second = scanner.consume(data.dropFirst(split + 1))
        let invalid = scanner.consume(Data([0xff, 0x0a]))
        let next = scanner.consume(Data("{\"interrupted\":true}\n".utf8))
        #expect(!first)
        #expect(second)
        #expect(!invalid)
        #expect(next)
    }

    @Test("Oversized lines are discarded without blocking later interrupts")
    func oversizedLine() {
        var scanner = JSONLInterruptScanner(maximumLineBytes: 64)
        let oversized = scanner.consume(Data(repeating: 65, count: 128))
        let next = scanner.consume(Data("\n{\"interrupted\":true}\n".utf8))
        #expect(!oversized)
        #expect(next)
    }
}
