import AppKit
import Mixpanel
import SwiftUI
import XCTest
@testable import vibe_hud

@MainActor
final class ChatLayoutTests: XCTestCase {
    func testChatRemainsResponsiveWhenOpeningAndUpdatingHistory() async throws {
        Mixpanel.initialize(token: "layout-test", optOutTrackingByDefault: true)
        let id = UUID().uuidString
        let manager = ChatHistoryManager.shared
        let monitor = ClaudeSessionMonitor()
        let model = NotchViewModel(
            deviceNotchRect: CGRect(x: 0, y: 0, width: 200, height: 32),
            screenRect: CGRect(x: 0, y: 0, width: 1512, height: 982),
            windowHeight: 750, hasPhysicalNotch: true
        )
        await SessionStore.shared.process(.hookReceived(HookEvent(
            sessionId: id, cwd: "/tmp/chat-layout", event: "SessionStart", status: "processing",
            source: "claude", pid: nil, tty: nil, transcriptPath: nil,
            terminalBundleId: nil, terminalPid: nil, tmuxPane: nil, tmuxSocket: nil,
            tool: nil, toolInput: nil, toolUseId: nil, notificationType: nil, message: nil
        )))
        let text = """
        ## Task progress

        The task reads source files, runs checks, and reports results while the conversation remains open.
        会话包含较长的中英文回复、代码块和工具记录，窗口缩小再展开后仍应正常响应。

        ```sh
        swift test --parallel --filter ConversationTests
        ```

        1. Read the source files and inspect the current behavior.
        2. Run the regression checks and report their results.

        > Keep the history readable while new messages arrive.
        """
        let messages = (0..<24).map { index in
            let content: [MessageBlock]
            switch index % 4 {
            case 0: content = [.text("Run the checks")]
            case 1: content = [.thinking("")]
            case 2: content = [.toolUse(ToolUseBlock(id: "tool-\(index)", name: "Read", input: ["file_path": "/tmp/example.swift"]))]
            default: content = [.text(String(repeating: text + "\n\n", count: 6))]
            }
            return ChatMessage(
                id: "message-\(index)", role: index.isMultiple(of: 4) ? .user : .assistant,
                timestamp: Date(timeIntervalSince1970: Double(index)), content: content
            )
        }
        await SessionStore.shared.process(.historyLoaded(
            sessionId: id, messages: messages, completedTools: [], toolResults: [:], structuredResults: [:],
            conversationInfo: ConversationInfo(
                summary: nil, lastMessage: text, lastMessageRole: "assistant",
                lastToolName: nil, firstUserMessage: "Run the checks", lastUserMessageDate: nil
            )
        ))
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(manager.history(for: id).count, 18)
        let storedSession = await SessionStore.shared.session(for: id)
        let session = try XCTUnwrap(storedSession)
        let view = ChatView(sessionId: id, initialSession: session, sessionMonitor: monitor, viewModel: model)
        let host = NSHostingView(rootView: view
            .frame(width: 456)
            .frame(maxWidth: 480, maxHeight: 580, alignment: .top)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top))
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 480, height: 540),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.contentView = host
        window.orderBack(nil)
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))

        for height in [32.0, 540.0, 1.0, 320.0, 540.0] {
            window.setContentSize(NSSize(width: 480, height: height))
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(50))
        }
        for scroll in scrollViews(in: host) where scroll.hasVerticalScroller || (scroll.documentView?.frame.height ?? 0) > 540 {
            if let document = scroll.documentView {
                scroll.contentView.scroll(to: NSPoint(x: 0, y: document.bounds.maxY))
                scroll.reflectScrolledClipView(scroll.contentView)
                host.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(100))
            }
        }
        await SessionStore.shared.process(.historyLoaded(
            sessionId: id,
            messages: [ChatMessage(id: "new-message", role: .assistant, timestamp: Date(), content: [.text("Done")])],
            completedTools: [], toolResults: [:], structuredResults: [:],
            conversationInfo: session.conversationInfo
        ))
        try await Task.sleep(for: .milliseconds(400))
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(manager.history(for: id).count, 19)
        await SessionStore.shared.process(.sessionEnded(sessionId: id))
    }

    private func scrollViews(in view: NSView) -> [NSScrollView] {
        (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap { scrollViews(in: $0) }
    }
}
