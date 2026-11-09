import Foundation
import Testing
@testable import vibe_hud

@Suite("Session list visibility")
struct SessionDisplayTests {
    @Test("A prewarmed session without messages stays hidden")
    func emptySessionIsHidden() {
        #expect(!makeSession(phase: .waitingForInput).isDisplayable)
        #expect(!makeSession(phase: .idle).isDisplayable)
    }

    @Test("An active session is always visible")
    func activeSessionIsVisible() {
        #expect(makeSession(phase: .processing).isDisplayable)
        #expect(makeSession(phase: .compacting).isDisplayable)
        #expect(makeSession(phase: .failed("Request failed")).isDisplayable)
        #expect(makeSession(phase: .waitingForApproval(.init(
            toolUseId: "tool-1",
            toolName: "Bash",
            toolInput: nil,
            receivedAt: Date(timeIntervalSince1970: 0)
        ))).isDisplayable)
    }

    @Test("A session with conversation content is visible once it settles")
    func contentMakesSessionVisible() {
        let chatItems = [
            ChatHistoryItem(
                id: "message-1",
                type: .user("Hello"),
                timestamp: Date(timeIntervalSince1970: 0)
            )
        ]
        #expect(makeSession(phase: .waitingForInput, chatItems: chatItems).isDisplayable)
        #expect(makeSession(
            phase: .waitingForInput,
            conversationInfo: ConversationInfo(
                summary: nil,
                lastMessage: "Done",
                lastMessageRole: "assistant",
                lastToolName: nil,
                firstUserMessage: "Hello",
                lastUserMessageDate: nil
            )
        ).isDisplayable)
    }

    private func makeSession(
        phase: SessionPhase,
        chatItems: [ChatHistoryItem] = [],
        conversationInfo: ConversationInfo = ConversationInfo(
            summary: nil,
            lastMessage: nil,
            lastMessageRole: nil,
            lastToolName: nil,
            firstUserMessage: nil,
            lastUserMessageDate: nil
        )
    ) -> SessionState {
        SessionState(
            sessionId: "pi-test",
            cwd: "/tmp/project",
            source: .pi,
            phase: phase,
            chatItems: chatItems,
            conversationInfo: conversationInfo
        )
    }
}
