import Foundation

// Whole-mailbox access to Apple Mail through AppleScript. Everything the model supplies, such as
// a sender or a mailbox name, goes in as a script argument and never as script text, so it can't
// become code.
//
// Mail's own `whose` filter is never used. On a mailbox with tens of thousands of messages it can run
// for minutes, ignores the caller giving up, and leaves Mail unresponsive. Instead each script
// fetches a few properties of the newest N messages in one request apiece (seconds, whatever the
// mailbox size) and matches them itself. So a search covers the newest N messages and says so.

public struct KaiMailboxSummary: Equatable, Sendable {
    public let account: String
    public let name: String
    public let unread: Int
    public let total: Int
}

public struct KaiMailFilter: Codable, Equatable, Sendable {
    public static let maxTextLength = 200

    public var account: String
    public var mailbox: String
    public var senderContains: String
    public var subjectContains: String
    public var unreadOnly: Bool

    public init(account: String, mailbox: String, senderContains: String = "", subjectContains: String = "", unreadOnly: Bool = false) {
        self.account = account
        self.mailbox = mailbox
        self.senderContains = senderContains
        self.subjectContains = subjectContains
        self.unreadOnly = unreadOnly
    }

    public var hasText: Bool { !senderContains.isEmpty || !subjectContains.isEmpty }

    /// A change always needs a sender or a subject to narrow it, so "every message" can't be moved.
    public func validated(forChange: Bool) throws -> KaiMailFilter {
        func clean(_ text: String) -> String {
            text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
        }
        let result = KaiMailFilter(account: clean(account), mailbox: clean(mailbox), senderContains: clean(senderContains),
                                   subjectContains: clean(subjectContains), unreadOnly: unreadOnly)
        guard !result.account.isEmpty, !result.mailbox.isEmpty else { throw KaiSourceError.invalid("Say which account and mailbox.") }
        for text in [result.account, result.mailbox, result.senderContains, result.subjectContains] where text.count > Self.maxTextLength {
            throw KaiSourceError.invalid("Keep each search text under \(Self.maxTextLength) characters.")
        }
        if forChange, !result.hasText {
            throw KaiSourceError.invalid("Narrow it down with a sender or a subject. Kai won't change a whole mailbox at once.")
        }
        return result
    }
}

public struct KaiMailHit: Equatable, Sendable {
    public let id: String
    public let account: String
    public let mailbox: String
    public let sender: String
    public let subject: String
    public let date: Date
    public let isRead: Bool
}

public struct KaiMailMessageText: Equatable, Sendable {
    public let sender: String
    public let subject: String
    public let date: Date
    public let text: String
    public let truncated: Bool
}

public enum KaiMailOperation: Codable, Equatable, Sendable {
    case move(to: String)
    case markRead
}

public enum KaiMailAdmin {
    /// The most messages one approved action may touch.
    public static let maxChange = 500
    /// How many matches are checked one by one when filtering by unread.
    /// How many of the newest messages a search looks at.
    public static let scanLimit = 500
    /// How many of the newest messages a change looks at. Messages further back are not touched.
    public static let changeScanLimit = 2_000
    static let maxBodyCharacters = 20_000

    // MARK: Scripts

    static let mailboxesScript = KaiAppleScriptRecords.prelude + """
    set out to ""
    tell application "Mail"
        repeat with acct in accounts
            set acctName to name of acct
            repeat with mb in (mailboxes of acct)
                try
                    set out to out & my cleaned(acctName) & US & my cleaned(name of mb) & US & (unread count of mb as string) & US & (count of messages of mb as string) & RS
                end try
            end repeat
        end repeat
    end tell
    return out
    """

    /// Arguments: account, mailbox, sender text, subject text, unread only, limit, how many of the newest messages to examine.
    static let searchScript = KaiAppleScriptRecords.handlers + "on run argv\n" + """
    set US to (ASCII character 31)
    set RS to (ASCII character 30)
    set acctName to item 1 of argv
    set mbName to item 2 of argv
    set senderText to item 3 of argv
    set subjectText to item 4 of argv
    set unreadOnly to (item 5 of argv is "true")
    set maxCount to (item 6 of argv) as integer
    set scanMax to (item 7 of argv) as integer
    tell application "Mail"
        set mb to mailbox mbName of account acctName
        set n to count of messages of mb
        if n > scanMax then set n to scanMax
        if n < 1 then return ""
        set theIDs to id of (messages 1 thru n of mb)
        set theSenders to sender of (messages 1 thru n of mb)
        set theSubjects to subject of (messages 1 thru n of mb)
        set theDates to date received of (messages 1 thru n of mb)
        set theReads to read status of (messages 1 thru n of mb)
    end tell
    set out to ""
    set shown to 0
    repeat with i from 1 to n
        if shown >= maxCount then exit repeat
        if (senderText is "" or (item i of theSenders) contains senderText) and (subjectText is "" or (item i of theSubjects) contains subjectText) and ((not unreadOnly) or ((item i of theReads) is false)) then
            set out to out & ((item i of theIDs) as string) & US & my cleaned(item i of theSenders) & US & my cleaned(item i of theSubjects) & US & my isoDate(item i of theDates) & US & ((item i of theReads) as string) & RS
            set shown to shown + 1
        end if
    end repeat
    return out
    end run
    """

    /// Arguments: account, mailbox, message id, how many of the newest messages to look through.
    static let messageScript = KaiAppleScriptRecords.handlers + "on run argv\n" + """
    set US to (ASCII character 31)
    set target to (item 3 of argv) as integer
    set scanMax to (item 4 of argv) as integer
    tell application "Mail"
        set mb to mailbox (item 2 of argv) of account (item 1 of argv)
        set n to count of messages of mb
        if n > scanMax then set n to scanMax
        if n < 1 then error "That mailbox is empty."
        set theIDs to id of (messages 1 thru n of mb)
        set idx to 0
        repeat with i from 1 to n
            if (item i of theIDs) is target then
                set idx to i
                exit repeat
            end if
        end repeat
        if idx is 0 then error "That message isn't among the newest " & n & " in this mailbox."
        set m to message idx of mb
        set body to content of m
        return my cleaned(sender of m) & US & my cleaned(subject of m) & US & my isoDate(date received of m) & US & body
    end tell
    end run
    """

    /// Arguments: account, mailbox, sender text, subject text, unread only, cap, destination (empty to mark read),
    /// how many of the newest messages to examine. `move` is true to move, false to mark read.
    /// Each message's ID is checked right before it is changed, so mail arriving meanwhile can't make it pick the wrong one.
    static func changeScript(move: Bool) -> String {
        let action = move ? "move m to dest" : "set read status of m to true"
        return "on run argv\n" + """
        set acctName to item 1 of argv
        set mbName to item 2 of argv
        set senderText to item 3 of argv
        set subjectText to item 4 of argv
        set unreadOnly to (item 5 of argv is "true")
        set cap to (item 6 of argv) as integer
        set destName to item 7 of argv
        set scanMax to (item 8 of argv) as integer
        set changed to 0
        tell application "Mail"
            set mb to mailbox mbName of account acctName
            \(move ? "set dest to mailbox destName of account acctName" : "")
            set n to count of messages of mb
            if n > scanMax then set n to scanMax
            if n < 1 then return "0"
            set theIDs to id of (messages 1 thru n of mb)
            set theSenders to sender of (messages 1 thru n of mb)
            set theSubjects to subject of (messages 1 thru n of mb)
            set theReads to read status of (messages 1 thru n of mb)
        end tell
        set picks to {}
        repeat with i from 1 to n
            if (senderText is "" or (item i of theSenders) contains senderText) and (subjectText is "" or (item i of theSubjects) contains subjectText) and ((not unreadOnly) or ((item i of theReads) is false)) then
                set end of picks to i
                if (count of picks) > cap then error "More than " & cap & " messages match, so nothing was changed."
            end if
        end repeat
        tell application "Mail"
            repeat with k from (count of picks) to 1 by -1
                set idx to item k of picks
                set m to message idx of mb
                if (id of m) is (item idx of theIDs) then
                    \(action)
                    set changed to changed + 1
                end if
            end repeat
        end tell
        return changed as string
        end run
        """
    }

    // MARK: Size guard

    /// Beyond this many messages, Apple Mail's scripting takes minutes to read even a few hundred of them and
    /// stays busy afterwards, which freezes Mail. Kai won't try on a mailbox this big.
    public static let maxScriptableMailbox = 5_000

    public static func requireScriptable(account: String, mailbox: String, messageCount: Int) throws {
        guard messageCount <= maxScriptableMailbox else {
            throw KaiSourceError.invalid("“\(mailbox)” in \(account) has \(messageCount.formatted()) messages. Apple Mail's scripting is too slow for a mailbox that large and would freeze Mail, so Kai won't search or change it. Smaller mailboxes work.")
        }
    }

    static let countScript = "on run argv\n" + """
    tell application "Mail" to return (count of messages of mailbox (item 2 of argv) of account (item 1 of argv)) as string
    end run
    """

    /// One quick request, made before anything heavier.
    static func ensureScriptable(account: String, mailbox: String) async throws {
        guard let output = try await KaiProcessRunner.run("/usr/bin/osascript", arguments: ["-e", countScript, account, mailbox], timeout: 20) else {
            throw KaiSourceError.timedOut("Mail")
        }
        guard output.exitCode == 0, let count = Int(output.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw KaiSourceError.fromAppleScriptFailure(app: "Mail", message: output.standardError.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        try requireScriptable(account: account, mailbox: mailbox, messageCount: count)
    }

    // MARK: Using them

    public static func mailboxes() async throws -> [KaiMailboxSummary] {
        let records = try await KaiAppleScriptRecords.run(script: mailboxesScript, app: "Mail", timeout: 120)
        return records.compactMap { fields in
            guard fields.count == 4, let unread = Int(fields[2]), let total = Int(fields[3]) else { return nil }
            return KaiMailboxSummary(account: fields[0], name: fields[1], unread: unread, total: total)
        }
    }

    public static func search(_ filter: KaiMailFilter, limit: Int = 20) async throws -> [KaiMailHit] {
        let filter = try filter.validated(forChange: false)
        try await ensureScriptable(account: filter.account, mailbox: filter.mailbox)
        let arguments = [filter.account, filter.mailbox, filter.senderContains, filter.subjectContains, String(filter.unreadOnly), String(min(max(limit, 1), 50)), String(scanLimit)]
        let records = try await KaiAppleScriptRecords.run(script: searchScript, app: "Mail", arguments: arguments, timeout: 90)
        return hits(from: records, account: filter.account, mailbox: filter.mailbox)
    }

    static func hits(from records: [[String]], account: String, mailbox: String) -> [KaiMailHit] {
        records.compactMap { fields in
            guard fields.count == 5, let date = KaiAppleScriptRecords.date(fromISO: fields[3]) else { return nil }
            return KaiMailHit(id: fields[0], account: account, mailbox: mailbox, sender: fields[1], subject: fields[2], date: date, isRead: fields[4] == "true")
        }
    }

    public static func message(id: String, account: String, mailbox: String) async throws -> KaiMailMessageText {
        guard Int(id) != nil else { throw KaiSourceError.invalid("That isn't a message ID.") }
        try await ensureScriptable(account: account, mailbox: mailbox)
        guard let output = try await KaiProcessRunner.run("/usr/bin/osascript", arguments: ["-e", messageScript, account, mailbox, id, String(changeScanLimit)], timeout: 60) else {
            throw KaiSourceError.timedOut("Mail")
        }
        guard output.exitCode == 0 else {
            throw KaiSourceError.fromAppleScriptFailure(app: "Mail", message: output.standardError.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return try messageText(from: output.standardOutput)
    }

    static func messageText(from output: String) throws -> KaiMailMessageText {
        let parts = output.split(separator: "\u{1F}", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 4, let date = KaiAppleScriptRecords.date(fromISO: parts[2]) else { throw KaiSourceError.invalid("Mail sent a message Kai couldn't read.") }
        let body = parts[3].trimmingCharacters(in: .whitespacesAndNewlines)
        return KaiMailMessageText(sender: parts[0], subject: parts[1], date: date,
                                  text: String(body.prefix(maxBodyCharacters)), truncated: body.count > maxBodyCharacters)
    }

    /// How many messages the filter matches (up to the limit for one action) and a few examples.
    public static func preview(_ filter: KaiMailFilter) async throws -> (count: Int, examples: [KaiMailHit]) {
        let filter = try filter.validated(forChange: true)
        try await ensureScriptable(account: filter.account, mailbox: filter.mailbox)
        let arguments = [filter.account, filter.mailbox, filter.senderContains, filter.subjectContains, String(filter.unreadOnly), String(maxChange + 1), String(changeScanLimit)]
        let records = try await KaiAppleScriptRecords.run(script: searchScript, app: "Mail", arguments: arguments, timeout: 120)
        // One more than the limit is read, so "too many" can be told apart from "exactly the limit".
        let found = hits(from: records, account: filter.account, mailbox: filter.mailbox)
        return (found.count, Array(found.prefix(5)))
    }

    /// Carries out an approved change. It counts again first and refuses if more messages match now
    /// than the person approved.
    public static func perform(_ operation: KaiMailOperation, filter: KaiMailFilter, approvedCount: Int) async throws -> Int {
        let filter = try filter.validated(forChange: true)
        guard (1...maxChange).contains(approvedCount) else { throw KaiSourceError.invalid("This change covers more than \(maxChange) messages.") }
        try await ensureScriptable(account: filter.account, mailbox: filter.mailbox)
        let move: Bool
        let destination: String
        switch operation {
        case .move(let to):
            let target = to.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !target.isEmpty, target.count <= KaiMailFilter.maxTextLength else { throw KaiSourceError.invalid("Say which mailbox to move them to.") }
            move = true; destination = target
        case .markRead:
            move = false; destination = ""
        }
        let arguments = [filter.account, filter.mailbox, filter.senderContains, filter.subjectContains, String(filter.unreadOnly), String(approvedCount), destination, String(changeScanLimit)]
        guard let output = try await KaiProcessRunner.run("/usr/bin/osascript", arguments: ["-e", changeScript(move: move)] + arguments, timeout: 300) else {
            throw KaiSourceError.timedOut("Mail")
        }
        guard output.exitCode == 0 else {
            throw KaiSourceError.fromAppleScriptFailure(app: "Mail", message: output.standardError.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return Int(output.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }
}
