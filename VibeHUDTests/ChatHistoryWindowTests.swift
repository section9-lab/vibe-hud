import Foundation
import Testing
@testable import vibe_hud

@Suite("Chat history presentation window")
struct ChatHistoryWindowTests {
    @Test("A large session initially presents only its newest messages")
    func boundsInitialRendering() {
        let history = makeHistory(count: 2_000)
        let visible = ChatHistoryWindow.visibleItems(
            in: history,
            limit: ChatHistoryWindow.initialLimit
        )

        #expect(visible.count == 120)
        #expect(visible.first?.id == "item-1880")
        #expect(visible.last?.id == "item-1999")
    }

    @Test("Earlier history expands in bounded batches")
    func expandsInBatches() {
        #expect(ChatHistoryWindow.expandedLimit(current: 120, total: 2_000) == 240)
        #expect(ChatHistoryWindow.expandedLimit(current: 1_950, total: 2_000) == 2_000)
    }

    @Test("Small sessions remain complete")
    func preservesSmallSessions() {
        let history = makeHistory(count: 40)
        #expect(ChatHistoryWindow.visibleItems(in: history, limit: 120).map(\.id)
            == history.map(\.id))
    }

    private func makeHistory(count: Int) -> [ChatHistoryItem] {
        (0..<count).map { index in
            ChatHistoryItem(
                id: "item-\(index)",
                type: .assistant("Message \(index)"),
                timestamp: Date(timeIntervalSince1970: Double(index))
            )
        }
    }
}
