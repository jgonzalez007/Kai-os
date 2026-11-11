//
//  KaiMailHistory.swift
//  Kai Local Data
//
//  What was said before in a mail thread or with a person, so a reply can pick up where it left off and sound like
//  the user did with them. Read only, from Mail on this Mac: the person's earlier messages in the inbox and the ones
//  the user sent with the same subject.
//

import Foundation

public struct KaiMailHistoryEntry: Equatable, Sendable {
    public let fromMe: Bool
    public let who: String
    public let subject: String
    public let date: Date?
    public let text: String

    public init(fromMe: Bool, who: String, subject: String, date: Date?, text: String) {
        self.fromMe = fromMe
        self.who = who
        self.subject = subject
        self.date = date
        self.text = text
    }

    /// One line for the prompt: who, when, what they said. Line breaks are flattened and the quoted older text is cut.
    public var line: String {
        let when = date.map { $0.formatted(.dateTime.month(.abbreviated).day()) } ?? ""
        let body = KaiMailHistory.firstPart(of: text)
        return "\(fromMe ? "The user wrote" : "\(who) wrote")\(when.isEmpty ? "" : " on \(when)") (\(subject)): \(body)"
    }
}

public enum KaiMailHistory {
    static let maxBody = 600

    /// The address inside "Name <name@host>", or the text itself when there are no angle brackets.
    public static func address(from sender: String) -> String {
        if let open = sender.lastIndex(of: "<"), let close = sender.lastIndex(of: ">"), open < close {
            return String(sender[sender.index(after: open)..<close]).trimmingCharacters(in: .whitespaces).lowercased()
        }
        return sender.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// "Re: Fwd: Budget" → "Budget".
    public static func baseSubject(_ subject: String) -> String {
        var text = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        while let range = text.range(of: #"^(re|fwd?|aw|sv)\s*:\s*"#, options: [.regularExpression, .caseInsensitive]) {
            text.removeSubrange(range)
        }
        return text
    }

    /// The new part of a message: line breaks flattened, and cut where the quoted older mail starts.
    public static func firstPart(of text: String) -> String {
        var lines: [String] = []
        for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix(">") { continue }
            if line.range(of: #"^(on .+ wrote:|-{2,}\s*original message|from:\s.+|sent from my)"#, options: [.regularExpression, .caseInsensitive]) != nil { break }
            lines.append(line)
        }
        let flat = lines.joined(separator: " ")
        return flat.count > maxBody ? String(flat.prefix(maxBody)) + "…" : flat
    }

    /// Earlier messages from this address, and the user's own sent messages that share the subject. Newest first.
    /// A slow or very large mailbox gives up quietly: a reply is never held back by it.
    public static func around(sender: String, subject: String, excludingID: String, perKind: Int = 4) async -> [KaiMailHistoryEntry] {
        let addr = address(from: sender)
        guard addr.contains("@") else { return [] }
        let records = (try? await KaiAppleScriptRecords.run(script: script, app: "Mail",
                                                              arguments: [addr, baseSubject(subject), excludingID, String(perKind)], timeout: 25)) ?? []
        return entries(from: records)
    }

    static func entries(from records: [[String]]) -> [KaiMailHistoryEntry] {
        records.compactMap { fields -> KaiMailHistoryEntry? in
            guard fields.count == 5 else { return nil }
            return KaiMailHistoryEntry(fromMe: fields[0] == "me", who: displayName(fields[1]), subject: fields[2],
                                       date: KaiAppleScriptRecords.date(fromISO: fields[3]), text: fields[4])
        }
        .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    static func displayName(_ sender: String) -> String {
        if let open = sender.firstIndex(of: "<") {
            let name = sender[..<open].trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\"")))
            if !name.isEmpty { return name }
        }
        return address(from: sender)
    }

    /// Arguments: the sender's address, the subject without Re:, the id of the message being answered, how many of each.
    static let script = KaiAppleScriptRecords.handlers + """
    on run argv
        set US to (ASCII character 31)
        set RS to (ASCII character 30)
        set addr to item 1 of argv
        set subj to item 2 of argv
        set excludeID to item 3 of argv
        set maxCount to (item 4 of argv) as integer
        set out to ""
        tell application "Mail"
            try
                set theirs to (messages of inbox whose sender contains addr)
                set found to 0
                repeat with i from 1 to (count of theirs)
                    if found >= maxCount then exit repeat
                    set m to item i of theirs
                    if (id of m as string) is not excludeID then
                        set c to content of m
                        if (length of c) > 1500 then set c to text 1 thru 1500 of c
                        set out to out & "them" & US & my cleaned(sender of m) & US & my cleaned(subject of m) & US & my isoDate(date received of m) & US & my cleaned(c) & RS
                        set found to found + 1
                    end if
                end repeat
            end try
            if subj is not "" then
                try
                    set mine to (messages of sent mailbox whose subject contains subj)
                    set found to 0
                    repeat with i from 1 to (count of mine)
                        if found >= maxCount then exit repeat
                        set m to item i of mine
                        set c to content of m
                        if (length of c) > 1500 then set c to text 1 thru 1500 of c
                        set out to out & "me" & US & my cleaned(sender of m) & US & my cleaned(subject of m) & US & my isoDate(date sent of m) & US & my cleaned(c) & RS
                        set found to found + 1
                    end repeat
                end try
            end if
        end tell
        return out
    end run
    """
}
