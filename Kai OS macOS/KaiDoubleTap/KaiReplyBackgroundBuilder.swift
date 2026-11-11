//
//  KaiReplyBackgroundBuilder.swift
//  Kai OS macOS
//
//  Gathers what a reply can use besides the message: the user's profile, their own files that match the topic, when
//  they are busy (only when the message is about time), and what was said before with this person. Everything is read
//  on this Mac and goes only to the local model. Each part is optional: a part that can't be read is left out and the
//  reply is still written.
//

import Foundation
import KaiActions
import KaiKnowledge
import KaiLocalData
import KaiSlack

@MainActor
enum KaiReplyBackgroundBuilder {
    /// The text the topic is taken from, and the subject if it is a mail.
    private static func topic(of context: KaiReplyContext) -> (query: String, mail: KaiEmailDraftSource?, chat: String?)? {
        switch context {
        case .mail(_, let source): return (source.subject + " " + String(source.body.prefix(400)), source, nil)
        case .chat(_, let text): return (String(text.suffix(500)), nil, text)
        case .screen, .chatScreen: return nil
        }
    }

    static func build(for context: KaiReplyContext, appState: AppState) async -> KaiReplyBackground {
        guard let topic = topic(of: context) else { return KaiReplyBackground() }
        var background = KaiReplyBackground()

        if let profile = appState.profile?.markdown.trimmingCharacters(in: .whitespacesAndNewlines), !profile.isEmpty { background.profile = profile }

        async let notes = relatedNotes(query: topic.query, appState: appState, skipping: topic.mail?.subject)
        async let history = earlierMessages(context: context, topic: topic, appState: appState)
        if appState.calendarConnected, KaiReplyBackground.mentionsTiming(topic.query) { background.busy = busyTimes() }
        background.notes = await notes
        background.history = await history
        return background
    }

    private static func relatedNotes(query: String, appState: AppState, skipping subject: String?) async -> [KaiReplyBackground.Note] {
        let hits = await appState.searchKnowledge(query, limit: 6)
        var seen = Set<String>()
        return hits
            .filter { hit in
                // The message itself, or the same conversation read from Slack, says nothing new.
                if let subject, !subject.isEmpty, hit.title.localizedCaseInsensitiveContains(subject) { return false }
                return hit.snippet.count > 40 && seen.insert(hit.title).inserted
            }
            .prefix(4)
            .map { KaiReplyBackground.Note(title: $0.title, excerpt: $0.snippet.replacingOccurrences(of: "\n", with: " ")) }
    }

    /// Times in the next 7 days that have something on them. Only the times are given, never the event titles.
    private static func busyTimes() -> [String] {
        let now = Date()
        let end = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
        let day = Date.FormatStyle.dateTime.weekday(.wide).month(.abbreviated).day()
        let time = Date.FormatStyle.dateTime.hour().minute()
        return KaiCalendarSource.events(from: now, to: end)
            .filter { !$0.isAllDay && !$0.isCancelled && !$0.showsAsFree }
            .prefix(16)
            .map { "\($0.start.formatted(day)), \($0.start.formatted(time)) – \($0.end.formatted(time))" }
    }

    private static func earlierMessages(context: KaiReplyContext, topic: (query: String, mail: KaiEmailDraftSource?, chat: String?), appState: AppState) async -> [String] {
        if case .mail(let reference, let source) = context {
            guard appState.mailConnected else { return [] }
            return await KaiMailHistory.around(sender: source.sender, subject: source.subject, excludingID: reference.id).map(\.line)
        }
        guard let conversation = topic.chat, let client = appState.slackClient,
              let titleLine = conversation.split(separator: "\n").first(where: { $0.hasPrefix("Window: ") }),
              let name = KaiReplyBackground.slackCounterpart(windowTitle: String(titleLine.dropFirst("Window: ".count))) else { return [] }
        async let theirs = try? client.search("from:\"\(name)\"", count: 6)
        async let mine = try? client.search("to:\"\(name)\" from:me", count: 6)
        let found = (await theirs ?? []).map { (hit: $0, mine: false) } + (await mine ?? []).map { (hit: $0, mine: true) }
        return found.sorted { $0.hit.ts > $1.hit.ts }.prefix(8).map { item in
            let text = item.hit.text.replacingOccurrences(of: "\n", with: " ")
            return "\(item.mine ? "The user wrote" : "\(name) wrote") in Slack: \(String(text.prefix(300)))"
        }
    }
}
