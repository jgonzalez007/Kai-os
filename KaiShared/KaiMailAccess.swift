import Foundation

/// How much of the mailbox Kai may use. The person chooses, and the choice is checked again at
/// every use, so a model can't raise it.
public enum KaiMailAccess: String, CaseIterable, Codable, Sendable {
    /// The 50 newest inbox messages (sender and subject), unread mail for the briefing, and reply drafts.
    case standard
    /// Also: list every mailbox with its counts, search any mailbox, and read a message's text.
    case read
    /// Also: propose moving messages or marking them read. Each proposal is a card the person approves.
    case manage

    public static let defaultsKey = "kai.mail.access"

    public static var current: KaiMailAccess {
        get { UserDefaults.standard.string(forKey: defaultsKey).flatMap(KaiMailAccess.init(rawValue:)) ?? .standard }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }

    public var allowsWholeMailbox: Bool { self != .standard }
    public var allowsChanges: Bool { self == .manage }

    public var title: String {
        switch self {
        case .standard: return "Recent messages only"
        case .read: return "Read the whole mailbox"
        case .manage: return "Read and organize"
        }
    }

    public var explanation: String {
        switch self {
        case .standard:
            return "Kai sees the newest 50 inbox messages (sender and subject) and unread mail for the morning briefing, and can open a reply draft."
        case .read:
            return "Kai can list every mailbox, search any of them by sender or subject, and read the text of a message you ask about. It never changes anything."
        case .manage:
            return "Everything in \"Read the whole mailbox\", and Kai can propose moving messages to another mailbox or marking them read. Each proposal shows how many messages and examples, and nothing happens until you press Approve. Kai never sends mail, never deletes permanently, and never touches more than 500 messages in one approval."
        }
    }
}
