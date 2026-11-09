//
//  KaiAgentDirectTools.swift
//  Kai OS macOS
//
//  The things Sidekick can do without looking at the screen: make a note, add an event, open a draft, open a link,
//  read the calendar, find files. Each is one step instead of ten clicks. Anything that makes something has already
//  been approved by the time it gets here (the rules are in KaiAgentPolicy), and nothing here sends or deletes.
//

import AppKit
import Foundation
import KaiActions
import KaiAgent
import KaiLocalData
import KaiWeb

struct KaiAgentDirectTools: KaiAgentToolRunner {
    func run(name: String, arguments a: [String: String]) async throws -> String {
        switch name {
        case "open_url":
            guard let url = KaiWebURL.validate(a["url"] ?? "") else { throw KaiAgentActionProblem("That isn't a public web address.") }
            guard await MainActor.run(body: { NSWorkspace.shared.open(url) }) else { throw KaiAgentActionProblem("macOS couldn't open the link.") }
            return "Opened \(url.host ?? "the link") in the browser."
        case "create_note":
            return try await createNote(title: a["title"] ?? "", body: a["body"] ?? "")
        case "add_calendar_event":
            let action = try KaiActionParser.calendarEvent(title: a["title"], start: a["start"], minutes: a["minutes"].flatMap(Int.init), location: a["location"])
            return try await KaiSystemActionExecutor().perform(action)
        case "compose_mail_draft":
            let action = try KaiActionParser.mailDraft(to: a["to"], subject: a["subject"], body: a["body"])
            return try await KaiSystemActionExecutor().perform(action)
        case "read_calendar":
            return try readCalendar(days: Int(a["days"] ?? "") ?? 3)
        case "search_files":
            return try await searchFiles(a["query"] ?? "")
        default:
            throw KaiAgentActionProblem("There is no tool called \(name).")
        }
    }

    // MARK: Notes

    /// Values go in as script arguments, never as script text, so a title or body can't become code.
    static let noteScript = """
    on run argv
        tell application "Notes"
            set n to make new note with properties {body:(item 1 of argv)}
            return name of n
        end tell
    end run
    """

    private func createNote(title: String, body: String) async throws -> String {
        guard let output = try await KaiProcessRunner.run("/usr/bin/osascript", arguments: ["-e", Self.noteScript, KaiAgentTools.noteHTML(title: title, body: body)], timeout: 45) else {
            throw KaiAgentActionProblem("Notes didn't answer in time.")
        }
        guard output.exitCode == 0 else {
            let why = output.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            throw KaiAgentActionProblem(why.isEmpty ? "Notes couldn't make the note." : "Notes said: \(why)")
        }
        return "Made the note “\(title)” in Notes."
    }

    // MARK: Reading

    private func readCalendar(days: Int) throws -> String {
        guard KaiCalendarSource.access == .granted else { throw KaiAgentActionProblem("Kai OS isn't allowed to read Calendar. It can be turned on on the Permissions page.") }
        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: min(max(days, 1), 14), to: start) ?? start
        let events = KaiCalendarSource.events(from: start, to: end).prefix(40)
        guard !events.isEmpty else { return "Nothing is scheduled in that time." }
        return events.map { event in
            let when = event.isAllDay ? event.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) + ", all day"
                : event.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()) + "–" + event.end.formatted(date: .omitted, time: .shortened)
            return "- \(when): \(event.title)" + (event.location.isEmpty ? "" : " (\(event.location))")
        }.joined(separator: "\n")
    }

    private func searchFiles(_ query: String) async throws -> String {
        let found = try await KaiSpotlightSource.search(query, limit: 10)
        guard !found.isEmpty else { return "No files matched." }
        return found.map { "- \($0.name): \($0.path)" }.joined(separator: "\n")
    }
}
