import Foundation
import CryptoKit
import KaiLocalData
import KaiShared

public struct KaiIndexReport: Equatable, Sendable {
    public var added = 0
    public var updated = 0
    public var unchanged = 0
    public var removed = 0
    /// Files that were left out: too big, no text in them, or named like a secret.
    public var skipped = 0

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
        added += other.added; updated += other.updated; unchanged += other.unchanged; removed += other.removed; skipped += other.skipped
    }
}

/// Turns each source into documents and keeps the store in step with it.
/// Mail is indexed by subject and sender only, never by body.
public enum KaiKnowledgeIndexer {
    public static let folderSource = "files"
    /// Folders the person added from anywhere on the Mac. Each file's ID is "<folder id>/<path inside it>".
    public static let extraFoldersSource = "folder"
    public static let notesSource = "notes"
    public static let calendarSource = "calendar"
    public static let mailSource = "mail"

    static var fileExtensions: Set<String> { KaiFileReader.supportedExtensions }
    /// How much of one file is kept. A long report is searched whole, but a profile reads only the start.
    static let maxFileCharacters = 120_000

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
        let people = event.attendees.filter { !$0.isMe }.map(\.name).prefix(12)
        if !people.isEmpty { lines.append("With: \(people.joined(separator: ", "))") }
        if event.isRecurring { lines.append("Repeats") }
        if !event.notes.isEmpty { lines.append("Notes: \(String(event.notes.prefix(600)))") }
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

    /// Files under `folder` that Kai can read: text, Markdown, Word, PDF, web pages and pictures with text. Unchanged files
    /// (same size and date) are not read again. Hidden files, build folders and files named like secrets are left out.
    @discardableResult
    public static func indexFolder(_ folder: URL, into store: KaiKnowledgeStore) throws -> KaiIndexReport {
        var seen = Set<String>()
        var report = KaiIndexReport()
        _ = try scan(folder, source: folderSource, idPrefix: "", extraSkips: [], store: store, seen: &seen, report: &report)
        report.removed = try store.removeMissing(source: folderSource, keeping: seen)
        return report
    }

    /// The folders the person added. A folder that is switched off or removed from the list is forgotten; a folder that
    /// is just not there right now (an unplugged drive) keeps what was read, until it comes back.
    public static func indexFolders(_ folders: [KaiKnowledgeFolder], into store: KaiKnowledgeStore) throws -> (report: KaiIndexReport, results: [String: KaiFolderResult]) {
        var seen = Set<String>()
        var report = KaiIndexReport()
        var results: [String: KaiFolderResult] = [:]
        var someMissing = false
        for folder in folders where folder.enabled {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                results[folder.id] = KaiFolderResult(available: false)
                someMissing = true
                continue
            }
            var folderReport = KaiIndexReport()
            let indexed = try scan(folder.url, source: extraFoldersSource, idPrefix: folder.id + "/", extraSkips: folder.skipNames,
                                 store: store, seen: &seen, report: &folderReport)
            report.merge(folderReport)
            results[folder.id] = KaiFolderResult(indexed: indexed, skipped: folderReport.skipped)
        }
        if !someMissing { report.removed = try store.removeMissing(source: extraFoldersSource, keeping: seen) }
        return (report, results)
    }

    private static func scan(_ folder: URL, source: String, idPrefix: String, extraSkips: [String], store: KaiKnowledgeStore,
                             seen: inout Set<String>, report: inout KaiIndexReport) throws -> Int {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys,
                                                          options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return 0 }
        let root = folder.resolvingSymlinksInPath().path
        var indexed = 0
        var visited = 0
        for case let url as URL in walker {
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            if values.isDirectory == true {
                if KaiKnowledgeFolders.skips(directory: url.lastPathComponent, extra: extraSkips) { walker.skipDescendants() }
                continue
            }
            let ext = url.pathExtension.lowercased()
            guard values.isRegularFile == true, KaiFileReader.supports(ext) else { continue }
            visited += 1
            if visited > KaiKnowledgeFolders.maxFilesPerFolder { report.skipped += 1; continue }
            guard let size = values.fileSize else { continue }
            if KaiKnowledgeFolders.looksSecret(fileName: url.lastPathComponent) || size > KaiFileReader.maxBytes(for: ext) {
                report.skipped += 1
                continue
            }
            // A link that leads outside the folder is never followed.
            let resolved = url.resolvingSymlinksInPath().path
            guard resolved.hasPrefix(root + "/") else { continue }
            let relative = String(resolved.dropFirst(root.count + 1))
            let id = idPrefix + relative
            let modified = values.contentModificationDate
            let fingerprint = "\(Int(modified?.timeIntervalSince1970 ?? 0))-\(size)"
            if try store.isCurrent(source: source, sourceID: id, fingerprint: fingerprint) {
                seen.insert(id)
                report.unchanged += 1
                indexed += 1
                continue
            }
            guard let text = KaiFileReader.read(url, maxCharacters: maxFileCharacters) else { report.skipped += 1; continue }
            seen.insert(id)
            let title = (ext == "md" || ext == "markdown" ? markdownTitle(text) : nil) ?? url.deletingPathExtension().lastPathComponent
            report.record(try store.upsert(KaiKnowledgeDocument(source: source, sourceID: id, title: title,
                                                                text: text, modified: modified, fingerprint: fingerprint)))
            indexed += 1
        }
        return indexed
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

    /// Mail received since `since`. Reading stops at the first older message, so a short window is quick.
    public static func indexMail(into store: KaiKnowledgeStore, since: Date, limit: Int = KaiMailWindow.maxMessages) async throws -> KaiIndexReport {
        let messages = try await KaiMailSource.messages(since: since, limit: limit)
        return try index(messages.map(document(for:)), source: mailSource, into: store, removeMissing: false)
    }

    public static func indexMail(into store: KaiKnowledgeStore, limit: Int = 200) async throws -> KaiIndexReport {
        let messages = try await KaiMailSource.recentMessages(limit: limit)
        return try index(messages.map(document(for:)), source: mailSource, into: store, removeMissing: false)
    }
}
