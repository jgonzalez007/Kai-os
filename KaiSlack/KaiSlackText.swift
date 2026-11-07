import Foundation
import KaiKnowledge

/// Turns Slack's message markup into plain text, and a channel's day into a knowledge document.
public enum KaiSlackText {
    /// "<@U1> see <https://x.com|the doc> in <#C1|general> &amp; <!here>" becomes readable text.
    public static func plain(_ text: String, userNames: [String: String] = [:]) -> String {
        var result = text
        let pattern = try! NSRegularExpression(pattern: "<([^<>]+)>")
        let matches = pattern.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed()
        for match in matches {
            guard let whole = Range(match.range, in: result), let inner = Range(match.range(at: 1), in: result) else { continue }
            result.replaceSubrange(whole, with: replacement(String(result[inner]), userNames))
        }
        return result
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    private static func replacement(_ token: String, _ names: [String: String]) -> String {
        let parts = token.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        let head = parts[0]
        let label = parts.count > 1 ? parts[1] : nil
        if head.hasPrefix("@") {
            let id = String(head.dropFirst())
            return "@" + (label ?? names[id] ?? id)
        }
        if head.hasPrefix("#") { return "#" + (label ?? String(head.dropFirst())) }
        if head.hasPrefix("!") {
            let word = String(head.dropFirst())
            if word.hasPrefix("subteam^") { return label ?? "@group" }
            return "@" + (label ?? word)
        }
        if let label, !label.isEmpty { return "\(label) (\(head))" }
        return head.replacingOccurrences(of: "mailto:", with: "")
    }

    /// One document per channel per day, so a search lands on the day it was said.
    public static func documents(channel: KaiSlackChannel, title: String, messages: [KaiSlackMessage], userNames: [String: String],
                                 calendar: Calendar = .current) -> [KaiKnowledgeDocument] {
        let conversational = messages.filter { $0.subtype == nil || $0.subtype == "thread_broadcast" || $0.subtype == "me_message" }
        let byDay = Dictionary(grouping: conversational) { dayKey($0.date, calendar) }
        return byDay.keys.sorted().compactMap { day in
            let lines = (byDay[day] ?? []).sorted { $0.ts < $1.ts }.compactMap { message -> String? in
                let text = plain(message.text, userNames: userNames).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                let who = message.user.flatMap { userNames[$0] } ?? message.user ?? "someone"
                return "\(who): \(text)"
            }
            guard !lines.isEmpty, let first = byDay[day]?.first else { return nil }
            let body = lines.joined(separator: "\n\n")
            return KaiKnowledgeDocument(
                source: KaiSlackIndexer.source, sourceID: "\(channel.id):\(day)", title: "\(title) — \(day)",
                text: body, modified: first.date, fingerprint: KaiKnowledgeIndexer.hash(body))
        }
    }

    static func dayKey(_ date: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// The Slack window's visible text, cleaned for the assistant: no empty lines, no repeats of
    /// neighbouring lines, and no more than `limit` characters.
    public static func cleanScreen(_ lines: [String], limit: Int = 6_000) -> String {
        var out: [String] = []
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || out.last == line { continue }
            out.append(line)
        }
        var text = ""
        for line in out {
            if text.count + line.count + 1 > limit { text += "\n…"; break }
            text += (text.isEmpty ? "" : "\n") + line
        }
        return text
    }
}

public enum KaiSlackIndexer {
    public static let source = "slack"

    /// Reads recent messages from the person's channels into the knowledge base.
    /// Direct messages are left out unless the person turned them on.
    public static func index(client: KaiSlackClient, into store: KaiKnowledgeStore, includeDirectMessages: Bool,
                             days: Int = 14, maxChannels: Int = 30, now: Date = Date()) async throws -> KaiIndexReport {
        let since = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
        let channels = Array(try await client.channels(includeDirectMessages: includeDirectMessages).prefix(maxChannels))
        var names: [String: String] = [:]
        func name(_ id: String) async -> String {
            if let known = names[id] { return known }
            let resolved = (try? await client.displayName(userID: id)) ?? id
            names[id] = resolved
            return resolved
        }
        var report = KaiIndexReport()
        for channel in channels {
            let messages = try await client.history(channel: channel.id, since: since)
            guard !messages.isEmpty else { continue }
            for id in Set(messages.compactMap(\.user)) { _ = await name(id) }
            let title: String
            switch channel.kind {
            case .channel, .privateChannel: title = "#\(channel.name)"
            case .groupDM: title = "Group message \(channel.name)"
            case .directMessage: title = "Direct message with \(await name(channel.userID ?? ""))"
            }
            let docs = KaiSlackText.documents(channel: channel, title: title, messages: messages, userNames: names)
            report.merge(try KaiKnowledgeIndexer.index(docs, source: source, into: store, removeMissing: false))
        }
        return report
    }
}
