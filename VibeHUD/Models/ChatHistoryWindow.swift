import Foundation

/// Bounds the number of chat rows SwiftUI must construct when a large session
/// is opened. Older history remains available in explicit, predictable batches.
enum ChatHistoryWindow {
    static let initialLimit = 120
    static let batchSize = 120

    nonisolated static func visibleItems(
        in history: [ChatHistoryItem],
        limit: Int
    ) -> ArraySlice<ChatHistoryItem> {
        history.suffix(max(0, limit))
    }

    nonisolated static func expandedLimit(current: Int, total: Int) -> Int {
        min(total, current + batchSize)
    }
}
