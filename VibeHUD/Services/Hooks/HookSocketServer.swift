//
//  HookSocketServer.swift
//  VibeHUD
//
//  One-way Unix socket receiver for privacy-preserving lifecycle events.
//

import Darwin
import Foundation
import os.log

private let logger = Logger(subsystem: "com.vibehud", category: "Hooks")

struct HookEvent: Codable, Sendable {
    let sessionId: String
    let cwd: String
    let event: String
    let status: String
    let source: String?
    let pid: Int?
    let tty: String?
    let terminalBundleId: String?
    let terminalPid: Int?
    let tmuxPane: String?
    let tmuxSocket: String?
    let eventSequence: UInt64?
    let notificationType: String?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case cwd, event, status, source, pid, tty
        case terminalBundleId = "terminal_bundle_id"
        case terminalPid = "terminal_pid"
        case tmuxPane = "tmux_pane"
        case tmuxSocket = "tmux_socket"
        case eventSequence = "event_sequence"
        case notificationType = "notification_type"
    }

    nonisolated var phaseUpdate: SessionPhase? {
        switch event {
        case "SessionStart":
            return .idle
        case "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure",
             "SubagentStart", "SubagentStop", "PostCompact":
            return .processing
        case "PreCompact":
            return .compacting
        case "Stop", "StopFailure":
            return .waitingForInput
        case "Notification" where notificationType == "idle_prompt":
            return .waitingForInput
        default:
            return nil
        }
    }

    nonisolated var isEnded: Bool {
        event == "SessionEnd" || status == "ended"
    }
}

typealias HookEventHandler = @Sendable (HookEvent) -> Void

final class HookSocketServer {
    static let shared = HookSocketServer()
    static let socketPath = "/tmp/vibe-hud.sock"

    private var serverSocket: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var eventHandler: HookEventHandler?
    private let queue = DispatchQueue(label: "com.vibehud.socket", qos: .userInitiated)

    private init() {}

    func start(onEvent: @escaping HookEventHandler) {
        queue.async { [weak self] in
            self?.startServer(onEvent: onEvent)
        }
    }

    private func startServer(onEvent: @escaping HookEventHandler) {
        guard serverSocket < 0 else { return }
        eventHandler = onEvent
        unlink(Self.socketPath)

        serverSocket = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverSocket >= 0 else {
            logger.error("Failed to create socket: \(errno)")
            return
        }

        let flags = fcntl(serverSocket, F_GETFL)
        _ = fcntl(serverSocket, F_SETFL, flags | O_NONBLOCK)

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        _ = Self.socketPath.withCString { source in
            withUnsafeMutablePointer(to: &address.sun_path) { destination in
                strcpy(
                    UnsafeMutableRawPointer(destination).assumingMemoryBound(to: CChar.self),
                    source
                )
            }
        }

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(serverSocket, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            logger.error("Failed to bind socket: \(errno)")
            close(serverSocket)
            serverSocket = -1
            return
        }

        chmod(Self.socketPath, 0o600)
        guard listen(serverSocket, 16) == 0 else {
            logger.error("Failed to listen: \(errno)")
            close(serverSocket)
            serverSocket = -1
            return
        }

        acceptSource = DispatchSource.makeReadSource(fileDescriptor: serverSocket, queue: queue)
        acceptSource?.setEventHandler { [weak self] in self?.acceptConnection() }
        acceptSource?.setCancelHandler { [weak self] in
            guard let self, self.serverSocket >= 0 else { return }
            close(self.serverSocket)
            self.serverSocket = -1
        }
        acceptSource?.resume()
        logger.info("Listening on \(Self.socketPath, privacy: .public)")
    }

    func stop() {
        acceptSource?.cancel()
        acceptSource = nil
        unlink(Self.socketPath)
    }

    private func acceptConnection() {
        while true {
            let client = accept(serverSocket, nil, nil)
            guard client >= 0 else {
                if errno != EAGAIN && errno != EWOULDBLOCK {
                    logger.error("Accept failed: \(errno)")
                }
                return
            }
            handleClient(client)
        }
    }

    private func handleClient(_ client: Int32) {
        defer { close(client) }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        var descriptor = pollfd(fd: client, events: Int16(POLLIN), revents: 0)
        let deadline = Date().addingTimeInterval(0.5)

        while Date() < deadline {
            let result = poll(&descriptor, 1, 50)
            if result > 0, (descriptor.revents & Int16(POLLIN)) != 0 {
                let count = read(client, &buffer, buffer.count)
                if count > 0 {
                    data.append(contentsOf: buffer[0..<count])
                } else {
                    break
                }
            } else if !data.isEmpty {
                break
            }
        }

        guard !data.isEmpty else { return }
        do {
            let event = try JSONDecoder().decode(HookEvent.self, from: data)
            eventHandler?(event)
        } catch {
            logger.warning("Rejected invalid lifecycle event: \(error.localizedDescription, privacy: .public)")
        }
    }
}
