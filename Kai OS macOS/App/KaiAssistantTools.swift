//
//  KaiAssistantTools.swift
//  Kai OS macOS
//
//  Tools the local model can call. Reading tools never connect a source on their own:
//  connecting stays a deliberate click, so a model can't trigger a permission prompt.
//  Propose tools only show a card. No tool can approve one, so a model that's been misled
//  by a file or a message still can't change anything without the user.
//

import Foundation
import KaiShared
import KaiActions
import KaiLocalAI
import KaiLocalData

extension AppState {
    private static let toolOutputLimit = 6000

    static let assistantTools: [KaiOllamaTool] = [
        KaiOllamaTool(
            name: "search_files",
            description: "Search the names and contents of files in the user's home folder with Spotlight.",
            parameters: [.init(name: "query", type: "string", description: "Words to search for", required: true)]
        ),
        KaiOllamaTool(
            name: "list_calendar_events",
            description: "List the user's calendar events, starting from today.",
            parameters: [.init(name: "days_ahead", type: "integer", description: "How many days ahead to include. Defaults to 7, maximum 60.", required: false)]
        ),
        KaiOllamaTool(
            name: "list_recent_mail",
            description: "List recent messages in the user's inbox: sender, subject, date, read and flagged status. Bodies are not available.",
            parameters: [.init(name: "query", type: "string", description: "Optional words to filter by sender or subject", required: false)]
        ),
        KaiOllamaTool(
            name: "search_notes",
            description: "List the user's recent notes with their text.",
            parameters: [.init(name: "query", type: "string", description: "Optional words to filter by title or text", required: false)]
        ),
        KaiOllamaTool(
            name: "search_knowledge",
            description: "Search everything Kai has indexed on this Mac: the user's Markdown notes folder, Apple Notes, calendar events and email subjects. Use it to recall what the user has written or planned.",
            parameters: [.init(name: "query", type: "string", description: "A few words to search for", required: true)]
        ),
        KaiOllamaTool(
            name: "search_slack",
            description: "Search the user's Slack messages with the Slack API. Read-only.",
            parameters: [.init(name: "query", type: "string", description: "A few words to search for", required: true)]
        ),
        KaiOllamaTool(
            name: "read_slack_screen",
            description: "Read the text the Slack app is showing right now on this Mac, such as the open channel or conversation. Read-only. Use it when the user says what's on my Slack or refers to the conversation they have open.",
            parameters: []
        ),
        KaiOllamaTool(
            name: "propose_calendar_event",
            description: "Propose a new calendar event. The user sees a card and decides; nothing is added unless they approve.",
            parameters: [
                .init(name: "title", type: "string", description: "Event title", required: true),
                .init(name: "start", type: "string", description: "Local start time, formatted like 2026-11-07T09:00:00", required: true),
                .init(name: "minutes", type: "integer", description: "Length in minutes. Defaults to 60.", required: false),
                .init(name: "location", type: "string", description: "Optional location", required: false),
            ]
        ),
        KaiOllamaTool(
            name: "propose_email_draft",
            description: "Propose opening a new draft in Apple Mail. The user sees a card and decides. Mail is never sent; the user reviews and sends the draft themselves.",
            parameters: [
                .init(name: "to", type: "string", description: "Recipient email addresses, separated by commas", required: true),
                .init(name: "subject", type: "string", description: "Subject line", required: true),
                .init(name: "body", type: "string", description: "Message text", required: false),
            ]
        ),
        KaiOllamaTool(
            name: "propose_notification",
            description: "Propose a Mac notification at a future time. The user sees a card and decides; nothing is scheduled unless they approve.",
            parameters: [
                .init(name: "title", type: "string", description: "Notification title", required: true),
                .init(name: "body", type: "string", description: "Optional text", required: false),
                .init(name: "at", type: "string", description: "Local time, formatted like 2026-11-07T09:00:00", required: true),
            ]
        ),
    ]

    static func toolStatus(for name: String) -> String {
        switch name {
        case "search_files": return "Searching files…"
        case "list_calendar_events": return "Checking your calendar…"
        case "list_recent_mail": return "Checking your mail…"
        case "search_notes": return "Reading your notes…"
        case "search_knowledge": return "Searching your knowledge base…"
        case "search_slack": return "Searching Slack…"
        case "read_slack_screen": return "Reading your Slack window…"
        case "propose_calendar_event", "propose_email_draft", "propose_notification": return "Preparing a proposal…"
        default: return "Working…"
        }
    }

    func runTool(_ call: KaiOllamaToolCall) async -> String {
        toolRunCount += 1
        do {
            let output: String
            switch call.name {
            case "search_files":
                output = try await searchFilesTool(call.arguments["query"]?.stringValue ?? "")
            case "list_calendar_events":
                output = calendarTool(daysAhead: call.arguments["days_ahead"]?.intValue ?? 7)
            case "list_recent_mail":
                output = try await mailTool(query: call.arguments["query"]?.stringValue)
            case "search_slack":
                output = await searchSlackTool(query: call.arguments["query"]?.stringValue)
            case "read_slack_screen":
                output = await readSlackScreenTool()
            case "search_knowledge":
                output = knowledgeTool(query: call.arguments["query"]?.stringValue)
            case "search_notes":
                output = try await notesTool(query: call.arguments["query"]?.stringValue)
            case "propose_calendar_event":
                output = try propose(KaiActionParser.calendarEvent(
                    title: call.arguments["title"]?.stringValue,
                    start: call.arguments["start"]?.stringValue,
                    minutes: call.arguments["minutes"]?.intValue,
                    location: call.arguments["location"]?.stringValue
                ))
            case "propose_email_draft":
                output = try propose(KaiActionParser.mailDraft(
                    to: call.arguments["to"]?.stringValue,
                    subject: call.arguments["subject"]?.stringValue,
                    body: call.arguments["body"]?.stringValue
                ))
            case "propose_notification":
                output = try propose(KaiActionParser.notification(
                    title: call.arguments["title"]?.stringValue,
                    body: call.arguments["body"]?.stringValue,
                    at: call.arguments["at"]?.stringValue
                ))
            default:
                output = "Unknown tool: \(call.name)"
            }
            return String(output.prefix(Self.toolOutputLimit))
        } catch {
            return "The tool failed: \(error.localizedDescription)"
        }
    }

    private func propose(_ action: KaiProposedAction) throws -> String {
        try presentActionCard(KaiActionCard(action: action))
        return "The user now sees a card for this and can approve or decline it. Nothing has happened yet, so don't say it's done."
    }

    private func searchFilesTool(_ query: String) async throws -> String {
        let files = try await KaiSpotlightSource.search(query)
        guard !files.isEmpty else { return "No files matched." }
        return files.map { file in
            let modified = file.modified.map { " (modified \($0.formatted(date: .abbreviated, time: .omitted)))" } ?? ""
            return "\(file.path)\(modified)"
        }.joined(separator: "\n")
    }

    private func calendarTool(daysAhead: Int) -> String {
        guard calendarConnected else { return Self.notConnected("Calendar") }
        let start = Calendar.current.startOfDay(for: Date())
        let days = min(max(daysAhead, 1), 60)
        let end = Calendar.current.date(byAdding: .day, value: days, to: start) ?? start
        let events = KaiCalendarSource.events(from: start, to: end)
        guard !events.isEmpty else { return "No events in the next \(days) days." }
        return events.map { event in
            let when = event.isAllDay
                ? event.start.formatted(date: .abbreviated, time: .omitted) + " (all day)"
                : event.start.formatted(date: .abbreviated, time: .shortened) + " – " + event.end.formatted(date: .omitted, time: .shortened)
            let place = event.location.isEmpty ? "" : " at \(event.location)"
            return "\(when): \(event.title)\(place) [\(event.calendarName)]"
        }.joined(separator: "\n")
    }

    private func mailTool(query: String?) async throws -> String {
        guard mailConnected else { return Self.notConnected("Mail") }
        var messages = try await KaiMailSource.recentMessages(limit: 50)
        if let query, !query.isEmpty {
            messages = messages.filter {
                $0.subject.localizedCaseInsensitiveContains(query) || $0.sender.localizedCaseInsensitiveContains(query)
            }
        }
        guard !messages.isEmpty else { return "No matching messages." }
        return messages.map { message in
            let flags = (message.isRead ? "" : " [unread]") + (message.isFlagged ? " [flagged]" : "")
            return "\(message.date.formatted(date: .abbreviated, time: .shortened)) from \(message.sender): \(message.subject)\(flags)"
        }.joined(separator: "\n")
    }

    private func notesTool(query: String?) async throws -> String {
        guard notesConnected else { return Self.notConnected("Notes") }
        var notes = try await KaiNotesSource.recentNotes(limit: 50)
        if let query, !query.isEmpty {
            notes = notes.filter {
                $0.title.localizedCaseInsensitiveContains(query) || $0.body.localizedCaseInsensitiveContains(query)
            }
        }
        guard !notes.isEmpty else { return "No matching notes." }
        return notes.map { "\($0.title) (\($0.modified.formatted(date: .abbreviated, time: .omitted))):\n\($0.body)" }
            .joined(separator: "\n\n")
    }

    private static func notConnected(_ source: String) -> String {
        "\(source) is not connected. Tell the user to click Connect \(source) in the \(source) section of the Kai OS sidebar."
    }
}
