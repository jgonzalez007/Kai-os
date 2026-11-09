//
//  KaiMailDisplay.swift
//  Kai Local Data
//
//  Small helpers for showing mail: who a message is from, whether it was sent by a machine, and
//  whether it looks like it needs the person. They read only a sender and a subject.
//

import Foundation

public enum KaiMailDisplay {
    /// "Ana Torres <ana@example.com>" becomes ("Ana Torres", "ana@example.com"). A bare address has no name.
    public static func parseSender(_ raw: String) -> (name: String, address: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let open = text.lastIndex(of: "<"), let close = text.lastIndex(of: ">"), open < close {
            let address = String(text[text.index(after: open)..<close]).trimmingCharacters(in: .whitespaces)
            let name = text[..<open].trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
            return (name.isEmpty ? address : name, address)
        }
        return text.contains("@") && !text.contains(" ") ? (text, text) : (text, "")
    }

    /// Up to two capital letters for the round avatar.
    public static func initials(_ name: String) -> String {
        let words = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).filter { !$0.isEmpty }
        guard let first = words.first else { return "?" }
        if words.count == 1 { return String(first.prefix(1)).uppercased() }
        return (String(first.prefix(1)) + String(words[words.count - 1].prefix(1))).uppercased()
    }

    /// Newsletters, receipts and notifications, by the way the address is written.
    public static func isAutomated(sender: String) -> Bool {
        let address = parseSender(sender).address.lowercased()
        let local = address.split(separator: "@").first.map(String.init) ?? address
        let markers = ["noreply", "no-reply", "no_reply", "donotreply", "do-not-reply", "notification", "notifications", "newsletter",
                       "mailer", "bounce", "updates", "digest", "alerts", "marketing", "news", "info", "support", "billing", "receipts"]
        return markers.contains { local == $0 || local.hasPrefix($0 + "+") || local.hasPrefix($0 + "-") || local.hasPrefix($0 + ".") }
    }

    /// Words that usually mean someone is waiting on an answer.
    static let askWords = ["?", "please", "can you", "could you", "need", "urgent", "asap", "deadline", "due", "review", "approve",
                           "sign", "confirm", "reminder", "action required", "follow up", "follow-up", "by friday", "by monday", "eod", "today"]

    /// A guess, from the sender and subject only: unread, from a person (not a machine), and asking for something,
    /// or flagged. It is shown as "Looks like it needs you", never as a fact.
    public static func looksLikeItNeedsYou(sender: String, subject: String, isRead: Bool, isFlagged: Bool) -> Bool {
        if isFlagged { return true }
        guard !isRead, !isAutomated(sender: sender) else { return false }
        let lower = subject.lowercased()
        return askWords.contains { lower.contains($0) }
    }

    /// A stable number for a name, so the same sender always gets the same avatar color.
    public static func colorIndex(_ name: String, count: Int) -> Int {
        guard count > 0 else { return 0 }
        var hash: UInt64 = 1469598103934665603
        for byte in name.lowercased().utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        return Int(hash % UInt64(count))
    }
}
