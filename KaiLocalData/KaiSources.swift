//
//  KaiSources.swift
//  Kai OS
//
//  Read-only access to the user's calendar, mail, notes and files on this Mac.
//  Nothing here modifies data or leaves the machine. Changes go through KaiActions.
//

import EventKit
import Foundation

public enum KaiSourceError: LocalizedError, Equatable, Sendable {
    case notAuthorized(String)
    case timedOut(String)
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .notAuthorized(let app):
            return "Kai OS isn't allowed to read \(app). Turn it on in System Settings → Privacy & Security, then try again."
        case .timedOut(let app):
            return "\(app) took too long to respond."
        case .failed(let message):
            return message
        }
    }

    public static func fromAppleScriptFailure(app: String, message: String) -> KaiSourceError {
        if message.contains("-1743") || message.localizedCaseInsensitiveContains("not authorized") {
            return .notAuthorized(app)
        }
        return .failed("\(app) reported an error: \(message)")
    }
}

// MARK: - Process runner

public enum KaiProcessRunner {
    public struct Output: Sendable {
        public let standardOutput: String
        public let standardError: String
        public let exitCode: Int32
    }

    /// Returns nil when the timeout is reached; the process is terminated in that case.
    public static func run(_ path: String, arguments: [String], timeout: TimeInterval) async throws -> Output? {
        let process = Process()
        let out = Pipe()
        let err = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }
                let lock = NSLock()
                var didTimeOut = false
                let watchdog = DispatchWorkItem {
                    lock.withLock { didTimeOut = true }
                    process.terminate()
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
                // Stderr is drained on its own queue, so a full pipe can't deadlock the process.
                var errorData = Data()
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global().async {
                    errorData = err.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                let outputData = out.fileHandleForReading.readDataToEndOfFile()
                group.wait()
                process.waitUntilExit()
                watchdog.cancel()
                if lock.withLock({ didTimeOut }) {
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(returning: Output(
                        standardOutput: String(decoding: outputData, as: UTF8.self),
                        standardError: String(decoding: errorData, as: UTF8.self),
                        exitCode: process.terminationStatus
                    ))
                }
            }
        }
    }
}

// MARK: - AppleScript records

/// Scripts emit fields split by the ASCII unit separator and records by the record separator,
/// because subjects and note bodies can contain any printable character.
enum KaiAppleScriptRecords {
    static let prelude = """
    set US to (ASCII character 31)
    set RS to (ASCII character 30)

    """ + handlers

    /// Kept apart from `prelude` for scripts with their own run handler, where the
    /// top-level statements above aren't allowed.
    static let handlers = """
    on isoDate(d)
        return (d as «class isot») as string
    end isoDate
    on cleaned(t)
        set AppleScript's text item delimiters to {(ASCII character 30), (ASCII character 31)}
        set parts to text items of (t as string)
        set AppleScript's text item delimiters to " "
        set joined to parts as string
        set AppleScript's text item delimiters to ""
        return joined
    end cleaned

    """

    static func parse(_ output: String) -> [[String]] {
        output
            .split(separator: "\u{1E}", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .newlines) }
            .filter { !$0.isEmpty }
            .map { $0.split(separator: "\u{1F}", omittingEmptySubsequences: false).map(String.init) }
    }

    static func date(fromISO text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.date(from: text)
    }

    static func run(script: String, app: String, arguments: [String] = [], timeout: TimeInterval = 45) async throws -> [[String]] {
        guard let output = try await KaiProcessRunner.run("/usr/bin/osascript", arguments: ["-e", script] + arguments, timeout: timeout) else {
            throw KaiSourceError.timedOut(app)
        }
        guard output.exitCode == 0 else {
            throw KaiSourceError.fromAppleScriptFailure(app: app, message: output.standardError.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return parse(output.standardOutput)
    }
}

// MARK: - Calendar

public struct KaiCalendarItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let start: Date
    public let end: Date
    public let isAllDay: Bool
    public let location: String
    public let calendarName: String
}

public enum KaiCalendarAccess: Sendable {
    case granted, notRequested, denied
}

public enum KaiCalendarSource {
    public static var access: KaiCalendarAccess {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return .granted
        case .notDetermined: return .notRequested
        default: return .denied
        }
    }

    /// Shows the system permission prompt the first time it runs.
    public static func requestAccess() async throws -> Bool {
        try await EKEventStore().requestFullAccessToEvents()
    }

    public static func events(from start: Date, to end: Date) -> [KaiCalendarItem] {
        // A fresh store sees the permission state and events as they are now.
        let store = EKEventStore()
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .map { event in
                KaiCalendarItem(
                    id: event.eventIdentifier ?? UUID().uuidString,
                    title: event.title ?? "Untitled",
                    start: event.startDate,
                    end: event.endDate,
                    isAllDay: event.isAllDay,
                    location: event.location ?? "",
                    calendarName: event.calendar?.title ?? ""
                )
            }
    }
}

// MARK: - Mail

public struct KaiMailItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let sender: String
    public let subject: String
    public let date: Date
    public let isRead: Bool
    public let isFlagged: Bool
}

public enum KaiMailSource {
    /// Scripting Mail launches it if it's closed, so call this only after the user connects Mail.
    public static func recentMessages(limit: Int = 30) async throws -> [KaiMailItem] {
        items(from: try await KaiAppleScriptRecords.run(script: script(limit: limit), app: "Mail"))
    }

    static func script(limit: Int) -> String {
        KaiAppleScriptRecords.prelude + """
        set out to ""
        tell application "Mail"
            set total to count of messages of inbox
            set n to total
            if n > \(limit) then set n to \(limit)
            repeat with i from 1 to n
                set m to message i of inbox
                set out to out & (id of m as string) & US & my cleaned(sender of m) & US & my cleaned(subject of m) & US & my isoDate(date received of m) & US & (read status of m as string) & US & (flagged status of m as string) & RS
            end repeat
        end tell
        return out
        """
    }

    static func items(from records: [[String]]) -> [KaiMailItem] {
        records.compactMap { fields in
            guard fields.count == 6, let date = KaiAppleScriptRecords.date(fromISO: fields[3]) else { return nil }
            return KaiMailItem(
                id: fields[0],
                sender: fields[1],
                subject: fields[2],
                date: date,
                isRead: fields[4] == "true",
                isFlagged: fields[5] == "true"
            )
        }
    }
}

// MARK: - Notes

public struct KaiNoteItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let body: String
    public let modified: Date
}

public enum KaiNotesSource {
    /// Each body is cut to `bodyLimit` characters to keep large notes from stalling the script.
    public static func recentNotes(limit: Int = 30, bodyLimit: Int = 2000) async throws -> [KaiNoteItem] {
        items(from: try await KaiAppleScriptRecords.run(script: script(limit: limit, bodyLimit: bodyLimit), app: "Notes"))
    }

    static func script(limit: Int, bodyLimit: Int) -> String {
        KaiAppleScriptRecords.prelude + """
        set out to ""
        tell application "Notes"
            set total to count of notes
            set n to total
            if n > \(limit) then set n to \(limit)
            repeat with i from 1 to n
                set theNote to note i
                set bodyText to my cleaned(plaintext of theNote)
                if (length of bodyText) > \(bodyLimit) then set bodyText to text 1 thru \(bodyLimit) of bodyText
                set out to out & (id of theNote as string) & US & my cleaned(name of theNote) & US & bodyText & US & my isoDate(modification date of theNote) & RS
            end repeat
        end tell
        return out
        """
    }

    static func items(from records: [[String]]) -> [KaiNoteItem] {
        records.compactMap { fields in
            guard fields.count == 4, let date = KaiAppleScriptRecords.date(fromISO: fields[3]) else { return nil }
            return KaiNoteItem(id: fields[0], title: fields[1], body: fields[2], modified: date)
        }
    }
}

// MARK: - Spotlight

public struct KaiFileItem: Equatable, Sendable {
    public let name: String
    public let path: String
    public let modified: Date?
}

public enum KaiSpotlightSource {
    static func sanitizedQuery(_ query: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutFlags = String(trimmed.drop { $0 == "-" }).trimmingCharacters(in: .whitespaces)
        return withoutFlags.isEmpty ? nil : withoutFlags
    }

    static func isUserFacing(path: String, home: String) -> Bool {
        guard path.hasPrefix(home + "/") else { return false }
        let relative = path.dropFirst(home.count + 1)
        if relative.hasPrefix("Library/") { return false }
        return !relative.split(separator: "/").contains { $0.hasPrefix(".") }
    }

    /// Searches file names and contents in the home folder.
    public static func search(_ query: String, limit: Int = 20) async throws -> [KaiFileItem] {
        guard let clean = sanitizedQuery(query) else { return [] }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard let output = try await KaiProcessRunner.run(
            "/usr/bin/mdfind",
            arguments: ["-onlyin", home, clean],
            timeout: 15
        ) else {
            throw KaiSourceError.timedOut("Spotlight")
        }
        guard output.exitCode == 0 else {
            throw KaiSourceError.failed("Spotlight search failed: \(output.standardError)")
        }
        return output.standardOutput
            .split(separator: "\n")
            .map(String.init)
            .filter { isUserFacing(path: $0, home: home) }
            .prefix(limit)
            .map { path in
                let attributes = try? FileManager.default.attributesOfItem(atPath: path)
                return KaiFileItem(
                    name: (path as NSString).lastPathComponent,
                    path: path,
                    modified: attributes?[.modificationDate] as? Date
                )
            }
    }
}

// MARK: - Selected message

public struct KaiMailMessageReference: Codable, Equatable, Sendable {
    public let id: String
    public let mailbox: String
    public let account: String

    public init(id: String, mailbox: String, account: String) {
        self.id = id
        self.mailbox = mailbox
        self.account = account
    }
}

/// The parts of an email a reply is drafted from. All of it is untrusted text from someone else.
public struct KaiEmailDraftSource: Equatable, Sendable {
    public let sender: String
    public let subject: String
    public let body: String

    public init(sender: String, subject: String, body: String) {
        self.sender = sender
        self.subject = subject
        self.body = body
    }
}

public enum KaiMailSelection {
    /// Reads the message selected in Mail, or nil when nothing is selected.
    public static func selectedEmail() async throws -> (reference: KaiMailMessageReference, source: KaiEmailDraftSource)? {
        email(from: try await KaiAppleScriptRecords.run(script: script, app: "Mail"))
    }

    static let script = KaiAppleScriptRecords.prelude + """
    tell application "Mail"
        set theSelection to selection
        if (count of theSelection) is 0 then return ""
        set m to item 1 of theSelection
        set boxName to ""
        set accountName to ""
        try
            set boxName to name of (mailbox of m)
        end try
        try
            set accountName to name of (account of (mailbox of m))
        end try
        return (id of m as string) & US & my cleaned(boxName) & US & my cleaned(accountName) & US & my cleaned(sender of m) & US & my cleaned(subject of m) & US & my isoDate(date received of m) & US & my cleaned(content of m) & RS
    end tell
    """

    /// Reads one known message, wherever the user's selection is.
    public static func email(at reference: KaiMailMessageReference) async throws -> (reference: KaiMailMessageReference, source: KaiEmailDraftSource)? {
        email(from: try await KaiAppleScriptRecords.run(
            script: referencedScript,
            app: "Mail",
            arguments: [reference.id, reference.mailbox, reference.account]
        ))
    }

    /// Values arrive as arguments, never as script text.
    static let referencedScript = KaiAppleScriptRecords.handlers + """
    on run argv
        set US to (ASCII character 31)
        set RS to (ASCII character 30)
        set targetID to item 1 of argv
        set boxName to item 2 of argv
        set accountName to item 3 of argv
        tell application "Mail"
            if accountName is "" then
                set m to first message of mailbox boxName whose id is (targetID as integer)
            else
                set m to first message of mailbox boxName of account accountName whose id is (targetID as integer)
            end if
            return (id of m as string) & US & my cleaned(boxName) & US & my cleaned(accountName) & US & my cleaned(sender of m) & US & my cleaned(subject of m) & US & my isoDate(date received of m) & US & my cleaned(content of m) & RS
        end tell
    end run
    """

    static func email(from records: [[String]]) -> (reference: KaiMailMessageReference, source: KaiEmailDraftSource)? {
        guard let fields = records.first, fields.count == 7 else { return nil }
        return (
            KaiMailMessageReference(id: fields[0], mailbox: fields[1], account: fields[2]),
            KaiEmailDraftSource(sender: fields[3], subject: fields[4], body: fields[6])
        )
    }
}

// MARK: - Unread mail for the morning briefing

public struct KaiBriefingMail: Codable, Equatable, Sendable {
    public let reference: KaiMailMessageReference
    public let sender: String
    public let subject: String
    public let date: Date
    public let isFlagged: Bool

    public init(reference: KaiMailMessageReference, sender: String, subject: String, date: Date, isFlagged: Bool) {
        self.reference = reference
        self.sender = sender
        self.subject = subject
        self.date = date
        self.isFlagged = isFlagged
    }
}

public enum KaiMailBriefing {
    /// How far back to look in the inbox, which keeps the script quick on large mailboxes.
    private static let scanLimit = 150

    public static func unreadMessages(limit: Int = 30) async throws -> [KaiBriefingMail] {
        items(from: try await KaiAppleScriptRecords.run(script: script(limit: limit), app: "Mail"))
    }

    static func script(limit: Int) -> String {
        KaiAppleScriptRecords.prelude + """
        set out to ""
        set found to 0
        tell application "Mail"
            set total to count of messages of inbox
            set n to total
            if n > \(scanLimit) then set n to \(scanLimit)
            repeat with i from 1 to n
                set m to message i of inbox
                if not (read status of m) then
                    set boxName to ""
                    set accountName to ""
                    try
                        set boxName to name of (mailbox of m)
                    end try
                    try
                        set accountName to name of (account of (mailbox of m))
                    end try
                    set out to out & (id of m as string) & US & my cleaned(boxName) & US & my cleaned(accountName) & US & my cleaned(sender of m) & US & my cleaned(subject of m) & US & my isoDate(date received of m) & US & (flagged status of m as string) & RS
                    set found to found + 1
                    if found is \(limit) then exit repeat
                end if
            end repeat
        end tell
        return out
        """
    }

    static func items(from records: [[String]]) -> [KaiBriefingMail] {
        records.compactMap { fields in
            guard fields.count == 7, let date = KaiAppleScriptRecords.date(fromISO: fields[5]) else { return nil }
            return KaiBriefingMail(
                reference: KaiMailMessageReference(id: fields[0], mailbox: fields[1], account: fields[2]),
                sender: fields[3],
                subject: fields[4],
                date: date,
                isFlagged: fields[6] == "true"
            )
        }
    }
}
