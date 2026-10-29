import Foundation

enum QuotaPeriod: String, CaseIterable, Sendable {
    case fiveHour = "five_hour"
    case sevenDay = "seven_day"
}

struct QuotaWindow: Equatable, Sendable {
    let usedPercent: Double
    let remainingPercent: Double
    let resetsAt: Date?
    let isStale: Bool
}

struct QuotaSnapshot: Equatable, Sendable {
    let updatedAt: Date?
    let windows: [QuotaPeriod: QuotaWindow]
    let tokensPerSecond: Double?
    let errorCode: String?

    static let empty = QuotaSnapshot(updatedAt: nil, windows: [:], tokensPerSecond: nil, errorCode: nil)

    func window(_ period: QuotaPeriod) -> QuotaWindow? { windows[period] }
}

struct TiboAlert: Equatable, Sendable {
    let id: String
    let kind: String
    let text: String
    let url: URL
    let postedAt: Date
}

struct TiboMonitorState: Equatable, Sendable {
    let alert: TiboAlert?
    let shouldPresent: Bool
    let lastSuccess: Date?
    let isStale: Bool
    let errorCode: String?

    static let empty = TiboMonitorState(alert: nil, shouldPresent: false, lastSuccess: nil,
                                        isStale: false, errorCode: nil)
}

enum MonitoringDecoder {
    static func json(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DecodeError.invalid
        }
        return object
    }

    static func quota(_ data: Data, now: Date = Date(), staleAfter: TimeInterval = 900) throws -> QuotaSnapshot {
        let object = try json(data)
        let updatedAt = epoch(object["updated_at"])
        let stale = updatedAt.map { now.timeIntervalSince($0) > staleAfter } ?? true
        let rawWindows = object["windows"] as? [String: Any] ?? [:]
        var windows: [QuotaPeriod: QuotaWindow] = [:]
        for period in QuotaPeriod.allCases {
            guard let raw = rawWindows[period.rawValue] as? [String: Any],
                  let used = number(raw["used_percentage"]), used.isFinite else { continue }
            let reset = timestamp(raw["resets_at"])
            let resetPassed = reset.map { $0 <= now } == true
            // A clock crossing the recorded reset time is not evidence that the
            // provider has granted a fresh quota. Keep the last measured value.
            let measuredUsed = min(100, max(0, used))
            windows[period] = QuotaWindow(usedPercent: measuredUsed,
                                          remainingPercent: 100 - measuredUsed,
                                          resetsAt: resetPassed ? nil : reset,
                                          isStale: stale || resetPassed)
        }
        var speed: Double?
        if let performance = object["daily_performance"] as? [String: Any],
           performance["metric"] as? String == "output_generation",
           ["ok", "stale"].contains(performance["status"] as? String ?? ""),
           performance["day"] as? String == shanghaiDay(now),
           let value = number(performance["tokens_per_second"]), value.isFinite, value > 0 {
            speed = value
        }
        return QuotaSnapshot(updatedAt: updatedAt, windows: windows, tokensPerSecond: speed,
                             errorCode: windows.isEmpty ? "quota_unavailable" : nil)
    }

    static func tibo(_ data: Data, now: Date = Date()) throws -> TiboMonitorState {
        let object = try json(data)
        guard object["version"] as? Int == 1 else { throw DecodeError.invalid }
        let lastSuccess = epoch(object["last_success"])
        let stale = lastSuccess.map { now.timeIntervalSince($0) > 1800 } ?? true
        let rawAlert = object["alert"] as? [String: Any]
        var alert: TiboAlert?
        if let rawAlert, let id = rawAlert["id"] as? String,
           id.range(of: "^[0-9]{10,25}$", options: .regularExpression) != nil,
           let rawURL = rawAlert["url"] as? String,
           let url = URL(string: rawURL), url.absoluteString == "https://x.com/thsottiaux/status/\(id)",
           let kind = rawAlert["kind"] as? String,
           ["planned", "reported", "mentioned", "banked"].contains(kind),
           let body = rawAlert["text"] as? String,
           let posted = epoch(rawAlert["at"]) {
            alert = TiboAlert(id: id, kind: kind, text: body, url: url, postedAt: posted)
        }
        let error = object["status"] as? String == "error"
            ? (object["error"] as? String ?? "source_unavailable") : nil
        return TiboMonitorState(alert: alert, shouldPresent: alert != nil,
                                lastSuccess: lastSuccess, isStale: stale, errorCode: error)
    }

    static func shanghaiDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func number(_ value: Any?) -> Double? {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
        return value.doubleValue
    }

    private static func epoch(_ value: Any?) -> Date? {
        guard let number = number(value), number.isFinite, number > 0 else { return nil }
        return Date(timeIntervalSince1970: number)
    }

    private static func timestamp(_ value: Any?) -> Date? {
        if let date = epoch(value) { return date }
        guard let string = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }

    enum DecodeError: Error { case invalid }
}
