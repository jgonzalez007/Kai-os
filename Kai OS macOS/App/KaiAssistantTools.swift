//
//  KaiAssistantTools.swift
//  Kai OS macOS
//
//  Read-only tools the local model can call. A tool never connects a source on its own:
//  connecting stays a deliberate click, so a model can't trigger a permission prompt.
//

import Foundation
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
    ]

    static func toolStatus(for name: String) -> String {
        switch name {
        case "search_files": return "Searching files…"
        case "list_calendar_events": return "Checking your calendar…"
        case "list_recent_mail": return "Checking your mail…"
        case "search_notes": return "Reading your notes…"
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
            case "search_notes":
                output = try await notesTool(query: call.arguments["query"]?.stringValue)
            default:
                output = "Unknown tool: \(call.name)"
            }
            return String(output.prefix(Self.toolOutputLimit))
        } catch {
            return "The tool failed: \(error.localizedDescription)"
        }
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
