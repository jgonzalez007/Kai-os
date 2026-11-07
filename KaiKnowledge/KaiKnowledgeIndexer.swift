import Foundation
import CryptoKit
import KaiLocalData

public struct KaiIndexReport: Equatable, Sendable {
    public var added = 0
    public var updated = 0
    public var unchanged = 0
    public var removed = 0

    public init() {}

    public var total: Int { added + updated + unchanged }

    mutating func record(_ change: KaiKnowledgeChange) {
        switch change {
        case .added: added += 1
        case .updated: updated += 1
        case .unchanged: unchanged += 1
        }
    }

    public mutating func merge(_ other: KaiIndexReport) {
        added += other.added; updated += other.updated; unchanged += other.unchanged; removed += other.removed
    }
}

/// Turns each source into documents and keeps the store in step with it.
/// Mail is indexed by subject and sender only, never by body.
public enum KaiKnowledgeIndexer {
    public static let folderSource = "files"
    public static let notesSource = "notes"
    public static let calendarSource = "calendar"
    public static let mailSource = "mail"

    static let fileExtensions: Set<String> = ["md", "markdown", "txt"]
    static let maxFileBytes = 1_000_000

    /// ~/Kai OS - Knowledge Base
    public static func defaultFolder() -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Kai OS - Knowledge Base", isDirectory: true)
    }

    // MARK: Documents

    public static func hash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    public static func document(for note: KaiNoteItem) -> KaiKnowledgeDocument {
        let title = note.title.isEmpty ? "Untitled note" : note.title
        return KaiKnowledgeDocument(source: notesSource, sourceID: note.id, title: title, text: note.body,
                                    modified: note.modified, fingerprint: hash(title + "\n" + note.body))
    }

    public static func document(for event: KaiCalendarItem) -> KaiKnowledgeDocument {
        var lines = ["\(event.title)", "When: \(event.start.formatted(date: .complete, time: event.isAllDay ? .omitted : .shortened))"]
        if !event.isAllDay { lines.append("Until: \(event.end.formatted(date: .omitted, time: .shortened))") }
        if !event.location.isEmpty { lines.append("Where: \(event.location)") }
        if !event.calendarName.isEmpty { lines.append("Calendar: \(event.calendarName)") }
        let text = lines.joined(separator: "\n\n")
        return KaiKnowledgeDocument(source: calendarSource, sourceID: event.id, title: event.title, text: text,
                                    modified: event.start, fingerprint: hash(text))
    }

    public static func document(for message: KaiMailItem) -> KaiKnowledgeDocument {
        let subject = message.subject.isEmpty ? "(no subject)" : message.subject
        let text = "Email from \(message.sender)\n\nSubject: \(subject)\n\nDate: \(message.date.formatted(date: .abbreviated, time: .shortened))"
        return KaiKnowledgeDocument(source: mailSource, sourceID: message.id, title: subject, text: text,
                                    modified: message.date, fingerprint: hash(text))
    }

    // MARK: Indexing

    /// Markdown and text files under `folder`. Unchanged files (same size and date) are not read again.
    @discardableResult
    public static func indexFolder(_ folder: URL, into store: KaiKnowledgeStore) throws -> KaiIndexReport {
        var report = KaiIndexReport()
        var seen = Set<String>()
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys,
                                                          options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return report }
        let root = folder.resolvingSymlinksInPath().path
        for case let url as URL in walker {
            guard fileExtensions.contains(url.pathExtension.lowercased()),
                  let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
                  let size = values.fileSize, size <= maxFileBytes else { continue }
            let resolved = url.resolvingSymlinksInPath().path
            guard resolved.hasPrefix(root + "/") else { continue }
            let relative = String(resolved.dropFirst(root.count + 1))
            seen.insert(relative)
            let modified = values.contentModificationDate
            let fingerprint = "\(Int(modified?.timeIntervalSince1970 ?? 0))-\(size)"
            if try store.isCurrent(source: folderSource, sourceID: relative, fingerprint: fingerprint) {
                report.unchanged += 1
                continue
            }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let title = markdownTitle(text) ?? url.deletingPathExtension().lastPathComponent
            report.record(try store.upsert(KaiKnowledgeDocument(source: folderSource, sourceID: relative, title: title,
                                                                text: text, modified: modified, fingerprint: fingerprint)))
        }
        report.removed = try store.removeMissing(source: folderSource, keeping: seen)
        return report
    }

    /// The first "# Heading" line, if there is one.
    static func markdownTitle(_ text: String) -> String? {
        for line in text.split(separator: "\n", maxSplits: 40, omittingEmptySubsequences: true).prefix(40) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# ") { return String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces) }
        }
        return nil
    }

    @discardableResult
    public static func index(_ documents: [KaiKnowledgeDocument], source: String, into store: KaiKnowledgeStore, removeMissing: Bool) throws -> KaiIndexReport {
        var report = KaiIndexReport()
        for document in documents { report.record(try store.upsert(document)) }
        if removeMissing { report.removed = try store.removeMissing(source: source, keeping: Set(documents.map(\.sourceID))) }
        return report
    }

    public static func indexNotes(into store: KaiKnowledgeStore, limit: Int = 200) async throws -> KaiIndexReport {
        let notes = try await KaiNotesSource.recentNotes(limit: limit, bodyLimit: 4000)
        // Only the most recent notes are read, so older ones are kept rather than removed.
        return try index(notes.map(document(for:)), source: notesSource, into: store, removeMissing: false)
    }

    public static func indexCalendar(into store: KaiKnowledgeStore, now: Date = Date()) throws -> KaiIndexReport {
        let start = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
        let end = Calendar.current.date(byAdding: .day, value: 90, to: now) ?? now
        let events = KaiCalendarSource.events(from: start, to: end)
        return try index(events.map(document(for:)), source: calendarSource, into: store, removeMissing: true)
    }

    public static func indexMail(into store: KaiKnowledgeStore, limit: Int = 200) async throws -> KaiIndexReport {
        let messages = try await KaiMailSource.recentMessages(limit: limit)
        return try index(messages.map(document(for:)), source: mailSource, into: store, removeMissing: false)
    }
}
