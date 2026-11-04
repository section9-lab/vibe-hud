//
//  JSONLInterruptWatcher.swift
//  VibeHUD
//
//  Watches JSONL files for interrupt patterns in real-time
//  Uses file system events to detect interrupts faster than hook polling
//

import Foundation
import os.log

/// Logger for interrupt watcher
private let logger = Logger(subsystem: "com.vibehud", category: "Interrupt")

protocol JSONLInterruptWatcherDelegate: AnyObject {
    func didDetectInterrupt(sessionId: String)
}

/// Watches a session's JSONL file for interrupt patterns in real-time
/// Uses DispatchSource for immediate detection when new lines are written
class JSONLInterruptWatcher {
    private var fileHandle: FileHandle?
    private var source: DispatchSourceFileSystemObject?
    private var lastOffset: UInt64 = 0
    private var scanner = JSONLInterruptScanner()
    private let sessionId: String
    private let filePath: String
    private let queue = DispatchQueue(label: "com.vibehud.interruptwatcher", qos: .userInteractive)

    weak var delegate: JSONLInterruptWatcherDelegate?

    nonisolated static func shouldWatch(source: String?, transcriptPath: String?) -> Bool {
        guard SessionSource(rawSource: source, transcriptPath: transcriptPath) != .opencode else { return false }
        guard let transcriptPath, !transcriptPath.isEmpty else { return true }
        return URL(fileURLWithPath: transcriptPath).pathExtension.lowercased() == "jsonl"
    }

    init(sessionId: String, cwd: String) {
        self.sessionId = sessionId
        let projectDir = cwd.replacingOccurrences(of: "/", with: "-")
                            .replacingOccurrences(of: ".", with: "-")
        self.filePath = ClaudePaths.projectsDir.path + "/" + projectDir + "/" + sessionId + ".jsonl"
    }

    init(sessionId: String, filePath: String) {
        self.sessionId = sessionId
        self.filePath = filePath
    }

    /// Start watching the JSONL file for interrupts
    func start() {
        queue.async { [weak self] in
            self?.startWatching()
        }
    }

    private func startWatching() {
        stopInternal()

        guard FileManager.default.fileExists(atPath: filePath),
              let handle = FileHandle(forReadingAtPath: filePath) else {
            logger.warning("Failed to open file: \(self.filePath, privacy: .public)")
            return
        }

        fileHandle = handle
        scanner = JSONLInterruptScanner()

        do {
            lastOffset = try handle.seekToEnd()
        } catch {
            logger.error("Failed to seek to end: \(error.localizedDescription, privacy: .public)")
            try? handle.close()
            fileHandle = nil
            return
        }

        let fd = handle.fileDescriptor
        let newSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend],
            queue: queue
        )

        newSource.setEventHandler { [weak self] in
            self?.checkForInterrupt()
        }

        newSource.setCancelHandler {
            try? handle.close()
        }

        source = newSource
        newSource.resume()

        logger.debug("Started watching: \(self.sessionId.prefix(8), privacy: .public)...")
    }

    private func checkForInterrupt() {
        guard let handle = fileHandle else { return }

        let currentSize: UInt64
        do {
            currentSize = try handle.seekToEnd()
        } catch {
            return
        }

        if currentSize < lastOffset {
            lastOffset = 0
            scanner = JSONLInterruptScanner()
        }
        guard currentSize > lastOffset else { return }

        do {
            try handle.seek(toOffset: lastOffset)
            // Read only the size observed at the start of this event, in bounded chunks.
            while lastOffset < currentSize {
                let count = Int(min(currentSize - lastOffset, 64 * 1024))
                guard let data = try handle.read(upToCount: count), !data.isEmpty else { break }
                lastOffset += UInt64(data.count)
                if scanner.consume(data) {
                    logger.info("Detected interrupt in session: \(self.sessionId.prefix(8), privacy: .public)")
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        self.delegate?.didDetectInterrupt(sessionId: self.sessionId)
                    }
                }
            }
        } catch {
            logger.error("Failed to read transcript: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Stop watching
    func stop() {
        queue.async { [weak self] in
            self?.stopInternal()
        }
    }

    private func stopInternal() {
        if source != nil {
            logger.debug("Stopped watching: \(self.sessionId.prefix(8), privacy: .public)...")
        }
        source?.cancel()
        source = nil
        fileHandle = nil
        // The cancel handler owns and closes the corresponding handle.
    }

    deinit {
        source?.cancel()
    }
}

/// Buffers complete JSONL lines only. Invalid or excessively large lines are skipped,
/// so malformed input cannot cause unbounded memory use or repeated reads.
struct JSONLInterruptScanner {
    private let maximumLineBytes: Int
    private var pending = Data()
    private var discardingLine = false

    init(maximumLineBytes: Int = 1_048_576) {
        self.maximumLineBytes = maximumLineBytes
    }

    mutating func consume(_ data: Data) -> Bool {
        var found = false
        var start = data.startIndex
        while start < data.endIndex {
            let newline = data[start...].firstIndex(of: 0x0a)
            let end = newline ?? data.endIndex
            if !discardingLine {
                let segment = data[start..<end]
                if segment.count > maximumLineBytes - pending.count {
                    pending.removeAll(keepingCapacity: false)
                    discardingLine = true
                } else {
                    pending.append(contentsOf: segment)
                }
            }
            guard let newline else { break }
            if !discardingLine, let line = String(data: pending, encoding: .utf8), Self.isInterruptLine(line) {
                found = true
            }
            pending.removeAll(keepingCapacity: true)
            discardingLine = false
            start = data.index(after: newline)
        }
        return found
    }

    private static func isInterruptLine(_ line: String) -> Bool {
        if line.contains("\"type\":\"user\"") &&
            (line.contains("[Request interrupted by user]") ||
             line.contains("[Request interrupted by user for tool use]")) {
            return true
        }
        if line.contains("\"tool_result\"") && line.contains("\"is_error\":true") {
            return ["Interrupted by user", "interrupted by user", "user doesn't want to proceed",
                    "[Request interrupted by user"].contains { line.contains($0) }
        }
        return line.contains("\"interrupted\":true")
    }
}

// MARK: - Interrupt Watcher Manager

/// Manages interrupt watchers for all active sessions
@MainActor
class InterruptWatcherManager {
    static let shared = InterruptWatcherManager()

    private var watchers: [String: JSONLInterruptWatcher] = [:]
    weak var delegate: JSONLInterruptWatcherDelegate?

    private init() {}

    func startWatching(sessionId: String, cwd: String) {
        guard watchers[sessionId] == nil else { return }

        let watcher = JSONLInterruptWatcher(sessionId: sessionId, cwd: cwd)
        watcher.delegate = delegate
        watcher.start()
        watchers[sessionId] = watcher
    }

    func startWatching(sessionId: String, filePath: String) {
        guard watchers[sessionId] == nil else { return }

        let watcher = JSONLInterruptWatcher(sessionId: sessionId, filePath: filePath)
        watcher.delegate = delegate
        watcher.start()
        watchers[sessionId] = watcher
    }

    /// Stop watching a specific session
    func stopWatching(sessionId: String) {
        watchers[sessionId]?.stop()
        watchers.removeValue(forKey: sessionId)
    }

    /// Stop all watchers
    func stopAll() {
        for (_, watcher) in watchers {
            watcher.stop()
        }
        watchers.removeAll()
    }

    /// Check if we're watching a session
    func isWatching(sessionId: String) -> Bool {
        watchers[sessionId] != nil
    }
}
