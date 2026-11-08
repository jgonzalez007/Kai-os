//
//  KaiActions.swift
//  Kai OS
//
//  Actions that change something on the user's Mac. The model can only propose one; it runs
//  when the user approves its card, and at most once. The set is closed on purpose: there is
//  no shell action, and mail stops at a visible draft because no send command exists here.
//

import EventKit
import AppKit
import Foundation
import KaiWeb
import KaiLocalData
import KaiShared
import UserNotifications

public enum KaiActionError: LocalizedError, Equatable, Sendable {
    case invalid(String)
    case notAllowed(String)
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .invalid(let message), .notAllowed(let message), .failed(let message):
            return message
        }
    }
}

/// What the person approves when Kai proposes to organize mail: exactly which messages, and what happens to them.
public struct KaiMailPlan: Codable, Equatable, Sendable {
    public let operation: KaiMailOperation
    public let filter: KaiMailFilter
    /// How many messages matched when it was proposed. Carrying it out refuses if more match later.
    public let count: Int
    public let examples: [String]

    public init(operation: KaiMailOperation, filter: KaiMailFilter, count: Int, examples: [String]) {
        self.operation = operation
        self.filter = filter
        self.count = count
        self.examples = examples
    }

    public var matching: String {
        var parts: [String] = []
        if !filter.senderContains.isEmpty { parts.append("from “\(filter.senderContains)”") }
        if !filter.subjectContains.isEmpty { parts.append("subject has “\(filter.subjectContains)”") }
        if filter.unreadOnly { parts.append("unread only") }
        return parts.joined(separator: ", ")
    }

    public var change: String {
        let noun = count == 1 ? "message" : "messages"
        switch operation {
        case .move(let to): return "Move \(count) \(noun) to “\(to)”"
        case .markRead: return "Mark \(count) \(noun) as read"
        }
    }
}

public enum KaiProposedAction: Codable, Equatable, Sendable {
    case calendarEvent(title: String, start: Date, minutes: Int, location: String)
    case mailDraft(to: [String], subject: String, body: String)
    case mailReply(reference: KaiMailMessageReference, recipient: String, subject: String, body: String)
    /// Text written at the cursor in another app. Only ever created by the user's own double
    /// tap, never proposed by the model, and carried out by the app's text inserter.
    case insertText(app: String, text: String)
    case notification(title: String, body: String, at: Date)
    /// Moves messages or marks them read. Never sends and never deletes for good.
    case mailOrganize(KaiMailPlan)
    /// Opens a web address in the person's browser. Nothing is signed in or sent by Kai.
    case openLink(url: URL, reason: String)

    public var kindName: String {
        switch self {
        case .calendarEvent: return "calendar_event"
        case .mailDraft: return "mail_draft"
        case .mailReply: return "mail_reply"
        case .insertText: return "insert_text"
        case .notification: return "notification"
        case .mailOrganize: return "mail_organize"
        case .openLink: return "open_link"
        }
    }

    public var heading: String {
        switch self {
        case .calendarEvent: return "Add to Calendar"
        case .mailDraft: return "Open a Mail Draft"
        case .mailReply: return "Open a Reply in Mail"
        case .insertText: return "Write at the Cursor"
        case .notification: return "Schedule a Notification"
        case .mailOrganize: return "Organize Mail"
        case .openLink: return "Open a Link"
        }
    }

    public var iconName: String {
        switch self {
        case .calendarEvent: return "calendar.badge.plus"
        case .mailDraft: return "square.and.pencil"
        case .mailReply: return "arrowshape.turn.up.left"
        case .insertText: return "text.cursor"
        case .notification: return "bell.badge"
        case .mailOrganize: return "tray.full"
        case .openLink: return "safari"
        }
    }

    /// Every field the action will use, so the user approves exactly what will happen.
    public var details: [(label: String, value: String)] {
        switch self {
        case .calendarEvent(let title, let start, let minutes, let location):
            var rows = [
                ("Title", title),
                ("Starts", start.formatted(date: .complete, time: .shortened)),
                ("Duration", "\(minutes) min"),
            ]
            if !location.isEmpty { rows.append(("Location", location)) }
            return rows
        case .mailDraft(let to, let subject, let body):
            return [("To", to.joined(separator: ", ")), ("Subject", subject), ("Body", body)]
        case .mailReply(_, let recipient, let subject, let body):
            return [("To", recipient), ("Subject", subject), ("Body", body)]
        case .insertText(let app, let text):
            return [("App", app), ("Text", text)]
        case .notification(let title, let body, let date):
            var rows = [("Title", title), ("When", date.formatted(date: .complete, time: .shortened))]
            if !body.isEmpty { rows.append(("Text", body)) }
            return rows
        case .mailOrganize(let plan):
            var rows = [("Mailbox", "\(plan.filter.account) › \(plan.filter.mailbox)"), ("Messages", plan.matching), ("Change", plan.change)]
            if !plan.examples.isEmpty { rows.append(("Examples", plan.examples.joined(separator: "\n"))) }
            rows.append(("Note", "Nothing is sent or deleted for good."))
            return rows
        case .openLink(let url, let reason):
            var rows = [("Link", url.absoluteString)]
            if !reason.isEmpty { rows.append(("Why", reason)) }
            rows.append(("Note", "Opens in your browser. Kai signs in to nothing and sends nothing."))
            return rows
        }
    }
}

// MARK: - Parsing

public enum KaiActionParser {
    private static let maxTextLength = 20_000
    private static let maxRecipients = 10
    private static let maxMinutes = 24 * 60

    public static func date(from text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX")
        local.timeZone = .current
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm"] {
            local.dateFormat = format
            if let date = local.date(from: trimmed) { return date }
        }
        return ISO8601DateFormatter().date(from: trimmed)
    }

    public static func calendarEvent(title: String?, start: String?, minutes: Int?, location: String?, now: Date = Date()) throws -> KaiProposedAction {
        let duration = minutes ?? 60
        guard (1...maxMinutes).contains(duration) else {
            throw KaiActionError.invalid("Duration must be between 1 and \(maxMinutes) minutes.")
        }
        return .calendarEvent(
            title: try required(title, "A title"),
            start: try futureDate(start, now: now),
            minutes: duration,
            location: clean(location)
        )
    }

    public static func mailDraft(to: String?, subject: String?, body: String?) throws -> KaiProposedAction {
        let recipients = (to ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard !recipients.isEmpty, recipients.count <= maxRecipients else {
            throw KaiActionError.invalid("Give between 1 and \(maxRecipients) recipient addresses.")
        }
        guard recipients.allSatisfy(isEmailAddress) else {
            throw KaiActionError.invalid("Each recipient must be a plain email address.")
        }
        return .mailDraft(to: recipients, subject: try required(subject, "A subject"), body: clean(body))
    }

    public static func notification(title: String?, body: String?, at: String?, now: Date = Date()) throws -> KaiProposedAction {
        .notification(title: try required(title, "A title"), body: clean(body), at: try futureDate(at, now: now))
    }

    /// A proposal to open a public web address in the browser. Never an address on this Mac or a private network.
    public static func openLink(url: String?, reason: String?) throws -> KaiProposedAction {
        guard let url, let checked = KaiWebURL.validate(url) else {
            throw KaiActionError.invalid("Give a full public web address starting with https://.")
        }
        return .openLink(url: checked, reason: String(clean(reason).prefix(200)))
    }

    /// A proposal to move messages or mark them read. `count` and `examples` come from looking in Mail first.
    public static func mailOrganize(operation: KaiMailOperation, filter: KaiMailFilter, count: Int, examples: [String]) throws -> KaiProposedAction {
        let checked: KaiMailFilter
        do { checked = try filter.validated(forChange: true) } catch { throw KaiActionError.invalid(error.localizedDescription) }
        if case .move(let to) = operation {
            let target = to.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !target.isEmpty else { throw KaiActionError.invalid("Say which mailbox to move them to.") }
            guard target.caseInsensitiveCompare(checked.mailbox) != .orderedSame else { throw KaiActionError.invalid("They are already in that mailbox.") }
        }
        guard count > 0 else { throw KaiActionError.invalid("No messages match, so there is nothing to change.") }
        guard count <= KaiMailAdmin.maxChange else {
            throw KaiActionError.invalid("More than \(KaiMailAdmin.maxChange) messages match. Narrow it down with a more specific sender or subject.")
        }
        return .mailOrganize(KaiMailPlan(operation: operation, filter: checked, count: count, examples: Array(examples.prefix(5))))
    }

    private static func required(_ text: String?, _ name: String) throws -> String {
        let value = clean(text)
        guard !value.isEmpty else { throw KaiActionError.invalid("\(name) is required.") }
        return value
    }

    private static func clean(_ text: String?) -> String {
        String((text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxTextLength))
    }

    private static func futureDate(_ text: String?, now: Date) throws -> Date {
        guard let date = date(from: text ?? "") else {
            throw KaiActionError.invalid("Dates must look like 2026-11-07T09:00:00, in local time.")
        }
        guard date > now else { throw KaiActionError.invalid("That time has already passed.") }
        return date
    }

    private static func isEmailAddress(_ text: String) -> Bool {
        text.range(of: #"^[A-Za-z0-9._%+'-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$"#, options: .regularExpression) != nil
    }
}

// MARK: - Approval

public struct KaiActionCard: Identifiable, Codable, Equatable, Sendable {
    public enum State: Codable, Equatable, Sendable {
        case pending, running, declined
        case succeeded(String)
        case failed(String)
    }

    public let id: String
    public let action: KaiProposedAction
    public private(set) var state = State.pending

    public init(id: String = UUID().uuidString, action: KaiProposedAction) {
        self.id = id
        self.action = action
    }

    /// Returns true only for the transition that should run the action.
    public mutating func approve() -> Bool {
        guard state == .pending else { return false }
        state = .running
        return true
    }

    public mutating func decline() -> Bool {
        guard state == .pending else { return false }
        state = .declined
        return true
    }

    public mutating func finish(_ outcome: State) {
        guard state == .running else { return }
        switch outcome {
        case .succeeded, .failed: state = outcome
        case .pending, .running, .declined: break
        }
    }
}

// MARK: - Audit log

/// An append-only record on this Mac, readable only by this user.
public struct KaiActionLog: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public static var standard: KaiActionLog {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return KaiActionLog(url: support.appendingPathComponent("Kai OS/action-log.jsonl"))
    }

    public func record(event: String, card: KaiActionCard, detail: String?) throws {
        struct Entry: Encodable {
            let time: String
            let event: String
            let id: String
            let kind: String
            let action: KaiProposedAction
            let detail: String?
        }
        let entry = Entry(
            time: ISO8601DateFormatter().string(from: Date()),
            event: event,
            id: card.id,
            kind: card.action.kindName,
            action: card.action,
            detail: detail
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var line = try encoder.encode(entry)
        line.append(0x0A)

        let manager = FileManager.default
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !manager.fileExists(atPath: url.path) {
            guard manager.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                throw KaiActionError.failed("The action log couldn't be created.")
            }
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
    }
}

// MARK: - Execution

public protocol KaiActionPerforming: Sendable {
    /// Returns a short description of what happened.
    func perform(_ action: KaiProposedAction) async throws -> String
}

enum KaiMailDraftScript {
    /// Values arrive as arguments, never as script text, so their contents can't become code.
    /// Recipients come in the first argument, one per line.
    static let source = """
    on run argv
        set recipientList to paragraphs of item 1 of argv
        tell application "Mail"
            set theDraft to make new outgoing message with properties {subject:item 2 of argv, content:item 3 of argv, visible:true}
            tell theDraft
                repeat with theAddress in recipientList
                    make new to recipient at end of to recipients with properties {address:(contents of theAddress)}
                end repeat
            end tell
            activate
        end tell
    end run
    """
}

public struct KaiSystemActionExecutor: KaiActionPerforming {
    /// Read when the action runs, so lowering the access after a proposal stops it.
    private let mailAccess: @Sendable () -> KaiMailAccess

    public init(mailAccess: @escaping @Sendable () -> KaiMailAccess = { KaiMailAccess.current }) {
        self.mailAccess = mailAccess
    }

    public func perform(_ action: KaiProposedAction) async throws -> String {
        switch action {
        case .calendarEvent(let title, let start, let minutes, let location):
            return try await addCalendarEvent(title: title, start: start, minutes: minutes, location: location)
        case .mailDraft(let to, let subject, let body):
            return try await openMailDraft(to: to, subject: subject, body: body)
        case .mailReply(let reference, _, _, let body):
            return try await openMailReply(reference: reference, body: body)
        case .insertText:
            throw KaiActionError.failed("Writing at the cursor is handled by the text inserter.")
        case .notification(let title, let body, let date):
            return try await scheduleNotification(title: title, body: body, date: date)
        case .openLink(let url, _):
            guard KaiWebURL.validate(url.absoluteString) != nil else { throw KaiActionError.notAllowed("That address is not a public web link.") }
            guard await MainActor.run(body: { NSWorkspace.shared.open(url) }) else { throw KaiActionError.failed("macOS could not open the link.") }
            return "Opened \(url.host ?? "the link") in your browser."
        case .mailOrganize(let plan):
            guard mailAccess().allowsChanges else {
                throw KaiActionError.notAllowed("Mail access is no longer set to “Read and organize”, so nothing was changed.")
            }
            do {
                let changed = try await KaiMailAdmin.perform(plan.operation, filter: plan.filter, approvedCount: plan.count)
                switch plan.operation {
                case .move(let to): return "Moved \(changed) message\(changed == 1 ? "" : "s") to “\(to)”."
                case .markRead: return "Marked \(changed) message\(changed == 1 ? "" : "s") as read."
                }
            } catch {
                throw KaiActionError.failed(error.localizedDescription)
            }
        }
    }

    private func addCalendarEvent(title: String, start: Date, minutes: Int, location: String) async throws -> String {
        if KaiCalendarSource.access != .granted {
            guard try await KaiCalendarSource.requestAccess() else {
                throw KaiActionError.notAllowed("Kai OS isn't allowed to use Calendar. Turn it on in System Settings → Privacy & Security.")
            }
        }
        let store = EKEventStore()
        guard let calendar = store.defaultCalendarForNewEvents else {
            throw KaiActionError.failed("Calendar has no default calendar for new events.")
        }
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = start.addingTimeInterval(TimeInterval(minutes * 60))
        event.calendar = calendar
        if !location.isEmpty { event.location = location }
        try store.save(event, span: .thisEvent, commit: true)
        return "Added to \(calendar.title)."
    }

    private func openMailDraft(to: [String], subject: String, body: String) async throws -> String {
        let arguments = ["-e", KaiMailDraftScript.source, to.joined(separator: "\n"), subject, body]
        guard let output = try await KaiProcessRunner.run("/usr/bin/osascript", arguments: arguments, timeout: 45) else {
            throw KaiSourceError.timedOut("Mail")
        }
        guard output.exitCode == 0 else {
            throw KaiSourceError.fromAppleScriptFailure(app: "Mail", message: output.standardError.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return "The draft is open in Mail. It hasn't been sent."
    }

    private func openMailReply(reference: KaiMailMessageReference, body: String) async throws -> String {
        let arguments = ["-e", KaiMailReplyScript.source, reference.id, reference.mailbox, reference.account, body]
        guard let output = try await KaiProcessRunner.run("/usr/bin/osascript", arguments: arguments, timeout: 45) else {
            throw KaiSourceError.timedOut("Mail")
        }
        guard output.exitCode == 0 else {
            throw KaiSourceError.fromAppleScriptFailure(app: "Mail", message: output.standardError.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return "The reply is open in Mail. Review it and send it yourself."
    }

    private func scheduleNotification(title: String, body: String, date: Date) async throws -> String {
        let center = UNUserNotificationCenter.current()
        guard try await center.requestAuthorization(options: [.alert, .sound]) else {
            throw KaiActionError.notAllowed("Kai OS isn't allowed to send notifications. Turn them on in System Settings → Notifications.")
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        try await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger))
        return "Scheduled for \(date.formatted(date: .abbreviated, time: .shortened))."
    }
}
