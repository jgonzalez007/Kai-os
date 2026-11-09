//
//  KaiMailCleanup.swift
//  Kai Local Data
//
//  Cleaning up an inbox full of mail that doesn't matter. Recent messages are grouped by sender, and for a group
//  the person can mark the messages read, move them to a folder, make a Mail rule for the sender's future mail, or
//  mute the sender in Kai. A change only ever touches the exact messages that were shown: they are named by id,
//  each is checked right before it is changed, and nothing is sent or deleted for good.
//

import Foundation

public struct KaiMailCleanupInput: Equatable, Sendable {
    public let id: String
    /// Where it was in the inbox list, so it can be found again quickly.
    public let position: Int
    public let sender: String
    public let subject: String
    public let date: Date
    public let isRead: Bool
    public let isFlagged: Bool

    public init(id: String, position: Int, sender: String, subject: String, date: Date, isRead: Bool, isFlagged: Bool) {
        self.id = id; self.position = position; self.sender = sender; self.subject = subject
        self.date = date; self.isRead = isRead; self.isFlagged = isFlagged
    }
}

public struct KaiMailGroup: Identifiable, Equatable, Sendable {
    public let id: String
    /// What a Mail rule or the mute list matches on: a sender's address, or the domain for automated mail.
    public let key: String
    public let name: String
    public let isAutomated: Bool
    public let isMuted: Bool
    public let messages: [KaiMailCleanupInput]

    public var unread: Int { messages.filter { !$0.isRead }.count }
    /// Flagged messages are left alone: the person marked them as important.
    public var changeable: [KaiMailCleanupInput] { messages.filter { !$0.isFlagged } }
}

public enum KaiMailMuteStore {
    public static let defaultsKey = "kai.mail.muted"

    public static func muted(_ defaults: UserDefaults = .standard) -> Set<String> {
        Set(defaults.stringArray(forKey: defaultsKey) ?? [])
    }

    public static func mute(_ key: String, _ defaults: UserDefaults = .standard) {
        defaults.set(Array(muted(defaults).union([key.lowercased()])).sorted(), forKey: defaultsKey)
    }

    public static func unmute(_ key: String, _ defaults: UserDefaults = .standard) {
        defaults.set(Array(muted(defaults).subtracting([key.lowercased()])).sorted(), forKey: defaultsKey)
    }

    /// True when this sender's address, or its domain, is on the list.
    public static func isMuted(sender: String, in set: Set<String>) -> Bool {
        let address = KaiMailDisplay.parseSender(sender).address.lowercased()
        return !set.isEmpty && (set.contains(address) || set.contains(KaiMailCleanup.domainKey(of: address)))
    }
}

public enum KaiMailCleanup {
    public static let maxChange = 60

    /// "no-reply@email.marketplace.aws" becomes "marketplace.aws". Two-part country endings like co.uk keep three labels.
    public static func domainKey(of address: String) -> String {
        let host = address.split(separator: "@").last.map(String.init)?.lowercased() ?? address.lowercased()
        let labels = host.split(separator: ".").map(String.init)
        guard labels.count > 2 else { return host }
        let secondLevel: Set<String> = ["co", "com", "org", "net", "gov", "ac"]
        if let last = labels.last, last.count == 2, secondLevel.contains(labels[labels.count - 2]) { return labels.suffix(3).joined(separator: ".") }
        return labels.suffix(2).joined(separator: ".")
    }

    /// Groups of two or more messages from one sender, plus every automated sender and every muted one, biggest first.
    public static func groups(from inputs: [KaiMailCleanupInput], muted: Set<String> = []) -> [KaiMailGroup] {
        var buckets: [String: [KaiMailCleanupInput]] = [:]
        var order: [String] = []
        for input in inputs {
            let parts = KaiMailDisplay.parseSender(input.sender)
            let automated = KaiMailDisplay.isAutomated(sender: input.sender)
            let address = parts.address.isEmpty ? parts.name.lowercased() : parts.address.lowercased()
            let key = automated && !parts.address.isEmpty ? domainKey(of: address) : address
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(input)
        }
        let groups: [KaiMailGroup] = order.compactMap { key in
            let messages = buckets[key]!.sorted { $0.date > $1.date }
            let automated = messages.contains { KaiMailDisplay.isAutomated(sender: $0.sender) }
            let isMuted = muted.contains(key)
            guard messages.count >= 2 || automated || isMuted else { return nil }
            let names = messages.map { KaiMailDisplay.parseSender($0.sender).name }
            let common = Dictionary(grouping: names, by: { $0 }).max { $0.value.count < $1.value.count }?.key ?? key
            return KaiMailGroup(id: key, key: key, name: common, isAutomated: automated, isMuted: isMuted, messages: messages)
        }
        return groups.sorted { a, b in
            if a.isMuted != b.isMuted { return !a.isMuted }
            if a.isAutomated != b.isAutomated { return a.isAutomated }
            return (a.messages.count, a.key) > (b.messages.count, b.key)
        }
    }

    /// A name for a Mail rule that says it came from Kai, so the person can find and remove it in Mail.
    public static func ruleName(for key: String) -> String { "Kai: mark mail from \(key) as read" }

    public static func moveRuleName(for key: String, folder: String) -> String { "Kai: move mail from \(key) to \(folder)" }
}

/// What the person approves when cleaning up: exactly which messages, and what happens to them.
public struct KaiMailCleanupPlan: Codable, Equatable, Sendable {
    public enum Operation: Codable, Equatable, Sendable {
        case markRead
        case move(to: String)
        /// A rule in Apple Mail that marks future mail from the sender as read.
        case rule
        /// A rule in Apple Mail that moves future mail from the sender to a folder of the same account.
        case moveRule(to: String)
    }

    public struct Item: Codable, Equatable, Sendable {
        public let id: String
        public let position: Int
        public let subject: String
        public init(id: String, position: Int, subject: String) { self.id = id; self.position = position; self.subject = subject }
    }

    public let operation: Operation
    public let senderKey: String
    public let senderName: String
    public let items: [Item]

    public init(operation: Operation, senderKey: String, senderName: String, items: [Item]) {
        self.operation = operation; self.senderKey = senderKey; self.senderName = senderName
        self.items = Array(items.prefix(KaiMailCleanup.maxChange))
    }

    public var change: String {
        let noun = items.count == 1 ? "message" : "messages"
        switch operation {
        case .markRead: return "Mark \(items.count) \(noun) from \(senderName) as read"
        case .move(let folder): return "Move \(items.count) \(noun) from \(senderName) to “\(folder)”"
        case .rule: return "Make a rule in Mail: mail from \(senderKey) is marked as read when it arrives"
        case .moveRule(let folder): return "Make a rule in Mail: mail from \(senderKey) always goes to “\(folder)”"
        }
    }
}

public enum KaiMailCleanupRunner {
    /// Values arrive as arguments, never as script text. Each message is found by its id, checked right before it is
    /// changed, and left alone if it is no longer among the newest 80 of the inbox.
    static let changeScript = KaiAppleScriptRecords.handlers + """
    on run argv
        set op to item 1 of argv
        set dest to item 2 of argv
        set changed to 0
        tell application "Mail"
            repeat with k from 3 to (count of argv)
                set pair to item k of argv
                set AppleScript's text item delimiters to ":"
                set targetID to (text item 1 of pair) as integer
                set hint to (text item 2 of pair) as integer
                set AppleScript's text item delimiters to ""
                set c to missing value
                try
                    set x to message hint of inbox
                    if (id of x) is targetID then set c to x
                end try
                if c is missing value then
                    repeat with i from 1 to 80
                        try
                            set x to message i of inbox
                            if (id of x) is targetID then
                                set c to x
                                exit repeat
                            end if
                        end try
                    end repeat
                end if
                if c is not missing value then
                    if op is "read" then
                        set read status of c to true
                        set changed to changed + 1
                    else
                        try
                            set acct to account of (mailbox of c)
                            move c to mailbox dest of acct
                            set changed to changed + 1
                        end try
                    end if
                end if
            end repeat
        end tell
        return changed as string
    end run
    """

    /// Arguments: rule name, the text the sender must contain. Does nothing if a rule of that name exists.
    static let ruleScript = """
    on run argv
        set ruleName to item 1 of argv
        set expr to item 2 of argv
        tell application "Mail"
            if (count of (rules whose name is ruleName)) > 0 then return "exists"
            set r to make new rule at end of rules with properties {name:ruleName, enabled:true, all conditions must be met:true, mark read:true}
            tell r
                make new rule condition at end of rule conditions with properties {rule type:from header, qualifier:does contain value, expression:expr}
            end tell
        end tell
        return "made"
    end run
    """

    /// Arguments: rule name, the text the sender must contain, the folder, and where a message of that sender is in the
    /// inbox (the rule's folder is the one with that name in the same account). Does nothing if a rule of that name exists.
    static let moveRuleScript = """
    on run argv
        set ruleName to item 1 of argv
        set expr to item 2 of argv
        set folderName to item 3 of argv
        set hint to (item 4 of argv) as integer
        tell application "Mail"
            if (count of (rules whose name is ruleName)) > 0 then return "exists"
            set c to message hint of inbox
            set acct to account of (mailbox of c)
            set dest to mailbox folderName of acct
            set r to make new rule at end of rules with properties {name:ruleName, enabled:true, all conditions must be met:true, move message:dest}
            tell r
                make new rule condition at end of rule conditions with properties {rule type:from header, qualifier:does contain value, expression:expr}
            end tell
        end tell
        return "made"
    end run
    """

    /// Argument: where the first message was in the inbox. Names the folders of that message's account.
    static let foldersScript = KaiAppleScriptRecords.handlers + """
    on run argv
        set RS to (ASCII character 30)
        tell application "Mail"
            set c to message ((item 1 of argv) as integer) of inbox
            set acct to account of (mailbox of c)
            set out to ""
            repeat with b in (mailboxes of acct)
                set out to out & my cleaned(name of b) & RS
            end repeat
            return out
        end tell
    end run
    """

    /// Folders where moving mail would hide it or lose it, so they are never offered.
    static let notOffered: Set<String> = ["inbox", "deleted items", "deleted messages", "trash", "junk", "junk email", "spam", "drafts", "sent", "sent items",
                                          "sent messages", "outbox", "conversation history", "sync issues", "all mail"]

    public static func folders(forMessageAt position: Int) async throws -> [String] {
        let output = try await KaiProcessRunner.run("/usr/bin/osascript", arguments: ["-e", foldersScript, String(max(position, 1))], timeout: 60)
        guard let output, output.exitCode == 0 else { throw KaiSourceError.timedOut("Mail") }
        return output.standardOutput.split(separator: "\u{1E}").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !notOffered.contains($0.lowercased()) }.sorted()
    }

    /// Carries out an approved plan and says what happened.
    public static func perform(_ plan: KaiMailCleanupPlan) async throws -> String {
        switch plan.operation {
        case .rule:
            let result = try await run([ruleScript, KaiMailCleanup.ruleName(for: plan.senderKey), plan.senderKey], timeout: 45)
            return result == "exists" ? "Mail already has a rule for \(plan.senderKey)." : "Made a rule in Mail. You can see or remove it in Mail → Settings → Rules."
        case .moveRule(let folder):
            guard let sample = plan.items.first else { throw KaiSourceError.invalid("Kai needs one message from this sender to find its account.") }
            let result = try await run([moveRuleScript, KaiMailCleanup.moveRuleName(for: plan.senderKey, folder: folder), plan.senderKey, folder, String(sample.position)], timeout: 60)
            return result == "exists" ? "Mail already has this rule." : "Made a rule in Mail: mail from \(plan.senderKey) now goes to “\(folder)”. You can see or remove it in Mail → Settings → Rules."
        case .markRead, .move:
            guard !plan.items.isEmpty else { return "There was nothing to change." }
            // Highest position first, so changing one message doesn't move the ones still to come.
            let pairs = plan.items.sorted { $0.position > $1.position }.map { "\($0.id):\($0.position)" }
            var destination = ""
            var op = "read"
            if case .move(let folder) = plan.operation { op = "move"; destination = folder }
            let result = try await run([changeScript, op, destination] + pairs, timeout: 240)
            let changed = Int(result) ?? 0
            let what = op == "read" ? "marked read" : "moved to “\(destination)”"
            if changed == plan.items.count { return "\(changed) \(changed == 1 ? "message" : "messages") \(what)." }
            return "\(changed) of \(plan.items.count) messages \(what). The rest are no longer among the newest 80 in the inbox."
        }
    }

    private static func run(_ arguments: [String], timeout: TimeInterval) async throws -> String {
        guard let output = try await KaiProcessRunner.run("/usr/bin/osascript", arguments: ["-e"] + arguments, timeout: timeout) else {
            throw KaiSourceError.timedOut("Mail")
        }
        guard output.exitCode == 0 else {
            throw KaiSourceError.fromAppleScriptFailure(app: "Mail", message: output.standardError.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return output.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
