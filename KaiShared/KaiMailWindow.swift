import Foundation

/// How far back Night Shift reads Mail. Each choice starts at midnight, so "Yesterday" means
/// yesterday and today so far. A short window keeps Mail fast: Kai reads from the newest message back
/// and stops at the first one older than the window.
public enum KaiMailWindow: String, Codable, CaseIterable, Sendable {
    case today, yesterday, last3Days, lastWeek

    public static let `default`: KaiMailWindow = .yesterday
    /// The most messages read, however large the window.
    public static let maxMessages = 200

    public var title: String {
        switch self {
        case .today: return "Today"
        case .yesterday: return "Yesterday and today"
        case .last3Days: return "Last 3 days"
        case .lastWeek: return "Last 7 days"
        }
    }

    /// Calendar days before today at which the window starts.
    public var daysBack: Int {
        switch self {
        case .today: return 0
        case .yesterday: return 1
        case .last3Days: return 2
        case .lastWeek: return 6
        }
    }

    public func since(now: Date = Date(), calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: -daysBack, to: start) ?? start
    }

    public var detail: String {
        "Reads mail received since midnight \(daysBack == 0 ? "today" : daysBack == 1 ? "yesterday" : "\(daysBack) days ago"), newest first, up to \(Self.maxMessages) messages."
    }
}
