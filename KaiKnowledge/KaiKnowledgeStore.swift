import Foundation
import SQLite3

public struct KaiKnowledgeDocument: Equatable, Sendable {
    public let source: String
    public let sourceID: String
    public let title: String
    public let text: String
    public let modified: Date?
    /// Changes whenever the content does. An equal fingerprint skips the rewrite.
    public let fingerprint: String

    public init(source: String, sourceID: String, title: String, text: String, modified: Date? = nil, fingerprint: String) {
        self.source = source
        self.sourceID = sourceID
        self.title = title
        self.text = text
        self.modified = modified
        self.fingerprint = fingerprint
    }
}

public struct KaiKnowledgeHit: Equatable, Sendable {
    public let source: String
    public let sourceID: String
    public let title: String
    public let snippet: String
    public let modified: Date?
}

public enum KaiKnowledgeChange: Equatable, Sendable {
    case added, updated, unchanged
}

public enum KaiKnowledgeError: Error, Equatable {
    case sqlite(String)
}

/// Local search over everything Kai has read: notes, calendar, mail headers and Markdown files.
/// One SQLite file with an FTS5 index. Nothing leaves the Mac.
public final class KaiKnowledgeStore: @unchecked Sendable {
    public static let chunkSize = 1_200

    private var db: OpaquePointer?
    private let lock = NSLock()

    public init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) != SQLITE_OK {
            throw KaiKnowledgeError.sqlite(message())
        }
        // Mail subjects and notes are private: only this user can read the file.
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        try execute("PRAGMA journal_mode=WAL")
        try execute("""
            CREATE TABLE IF NOT EXISTS documents(
                id INTEGER PRIMARY KEY,
                source TEXT NOT NULL,
                source_id TEXT NOT NULL,
                title TEXT NOT NULL,
                modified REAL,
                fingerprint TEXT NOT NULL,
                UNIQUE(source, source_id))
            """)
        try execute("CREATE VIRTUAL TABLE IF NOT EXISTS chunks USING fts5(text, title, doc_id UNINDEXED, tokenize='porter unicode61')")
    }

    deinit { sqlite3_close(db) }

    /// ~/Library/Application Support/Kai OS/knowledge.sqlite
    public static func defaultURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kai OS", isDirectory: true)
            .appendingPathComponent("knowledge.sqlite")
    }

    // MARK: Writing

    @discardableResult
    public func upsert(_ document: KaiKnowledgeDocument) throws -> KaiKnowledgeChange {
        lock.lock(); defer { lock.unlock() }
        let existing = try rows("SELECT id, fingerprint FROM documents WHERE source = ? AND source_id = ?",
                                [document.source, document.sourceID]) { ($0.int(0), $0.text(1)) }.first
        if let existing, existing.1 == document.fingerprint { return .unchanged }

        try execute("BEGIN")
        do {
            if let existing {
                try run("DELETE FROM chunks WHERE doc_id = ?", [existing.0])
                try run("UPDATE documents SET title = ?, modified = ?, fingerprint = ? WHERE id = ?",
                        [document.title, document.modified?.timeIntervalSince1970 as Any, document.fingerprint, existing.0])
            } else {
                try run("INSERT INTO documents(source, source_id, title, modified, fingerprint) VALUES(?,?,?,?,?)",
                        [document.source, document.sourceID, document.title, document.modified?.timeIntervalSince1970 as Any, document.fingerprint])
            }
            let id = existing?.0 ?? Int(sqlite3_last_insert_rowid(db))
            for chunk in KaiChunker.chunks(document.text, maxCharacters: Self.chunkSize) {
                try run("INSERT INTO chunks(text, title, doc_id) VALUES(?,?,?)", [chunk, document.title, id])
            }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
        return existing == nil ? .added : .updated
    }

    /// True when the stored copy has this fingerprint, so the caller can skip reading it again.
    public func isCurrent(source: String, sourceID: String, fingerprint: String) throws -> Bool {
        lock.lock(); defer { lock.unlock() }
        return try rows("SELECT 1 FROM documents WHERE source = ? AND source_id = ? AND fingerprint = ?",
                        [source, sourceID, fingerprint]) { _ in true }.first ?? false
    }

    /// Removes documents of `source` whose id is not in `keeping`, such as a deleted file.
    @discardableResult
    public func removeMissing(source: String, keeping ids: Set<String>) throws -> Int {
        lock.lock(); defer { lock.unlock() }
        let stored = try rows("SELECT id, source_id FROM documents WHERE source = ?", [source]) { ($0.int(0), $0.text(1)) }
        let gone = stored.filter { !ids.contains($0.1) }
        for (id, _) in gone {
            try run("DELETE FROM chunks WHERE doc_id = ?", [id])
            try run("DELETE FROM documents WHERE id = ?", [id])
        }
        return gone.count
    }

    public func clear() throws {
        lock.lock(); defer { lock.unlock() }
        try execute("DELETE FROM chunks")
        try execute("DELETE FROM documents")
    }

    // MARK: Reading

    public func count(source: String? = nil) throws -> Int {
        lock.lock(); defer { lock.unlock() }
        if let source {
            return try rows("SELECT COUNT(*) FROM documents WHERE source = ?", [source]) { $0.int(0) }.first ?? 0
        }
        return try rows("SELECT COUNT(*) FROM documents", []) { $0.int(0) }.first ?? 0
    }

    public func counts() throws -> [String: Int] {
        lock.lock(); defer { lock.unlock() }
        let pairs = try rows("SELECT source, COUNT(*) FROM documents GROUP BY source", []) { ($0.text(0), $0.int(1)) }
        return Dictionary(uniqueKeysWithValues: pairs)
    }

    /// Documents for browsing and the graph, newest first, each with its text joined from the stored chunks.
    public func documents(limit: Int = 300, maxText: Int = 4_000) throws -> [KaiKnowledgeDocument] {
        lock.lock(); defer { lock.unlock() }
        let heads = try rows("SELECT id, source, source_id, title, modified, fingerprint FROM documents ORDER BY COALESCE(modified, 0) DESC, id DESC LIMIT ?",
                             [max(limit, 1)]) { row in
            (id: row.int(0), source: row.text(1), sourceID: row.text(2), title: row.text(3),
             modified: row.isNull(4) ? nil : Date(timeIntervalSince1970: row.double(4)), fingerprint: row.text(5))
        }
        return try heads.map { head in
            let parts = try rows("SELECT text FROM chunks WHERE doc_id = ? ORDER BY rowid", [head.id]) { $0.text(0) }
            return KaiKnowledgeDocument(source: head.source, sourceID: head.sourceID, title: head.title,
                                        text: String(parts.joined(separator: "\n").prefix(maxText)), modified: head.modified, fingerprint: head.fingerprint)
        }
    }

    /// Best chunk per document, most relevant first. Every word must match; if nothing does,
    /// any word may.
    public func search(_ query: String, limit: Int = 8) throws -> [KaiKnowledgeHit] {
        let words = KaiSearchQuery.words(query)
        guard !words.isEmpty else { return [] }
        var hits = try matches(KaiSearchQuery.match(words, all: true), limit: limit)
        if hits.isEmpty, words.count > 1 { hits = try matches(KaiSearchQuery.match(words, all: false), limit: limit) }
        return hits
    }

    private func matches(_ match: String, limit: Int) throws -> [KaiKnowledgeHit] {
        lock.lock(); defer { lock.unlock() }
        let found = try rows("""
            SELECT d.source, d.source_id, d.title, d.modified, snippet(chunks, 0, '', '', '…', 28)
            FROM chunks JOIN documents d ON d.id = chunks.doc_id
            WHERE chunks MATCH ? ORDER BY bm25(chunks) LIMIT ?
            """, [match, max(limit, 1) * 4]) { row in
            KaiKnowledgeHit(source: row.text(0), sourceID: row.text(1), title: row.text(2),
                            snippet: row.text(4).replacingOccurrences(of: "\n", with: " "),
                            modified: row.isNull(3) ? nil : Date(timeIntervalSince1970: row.double(3)))
        }
        var seen = Set<String>()
        return found.filter { seen.insert($0.source + "\u{1F}" + $0.sourceID).inserted }.prefix(limit).map { $0 }
    }

    // MARK: SQLite plumbing

    private func message() -> String { db.map { String(cString: sqlite3_errmsg($0)) } ?? "no database" }

    private func execute(_ sql: String) throws {
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK { throw KaiKnowledgeError.sqlite(message()) }
    }

    private func run(_ sql: String, _ values: [Any]) throws {
        _ = try rows(sql, values) { _ in () }
    }

    private func rows<T>(_ sql: String, _ values: [Any], _ map: (Row) -> T) throws -> [T] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw KaiKnowledgeError.sqlite(message()) }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, value) in values.enumerated() {
            let position = Int32(index + 1)
            switch value {
            case let text as String: sqlite3_bind_text(statement, position, text, -1, transient)
            case let number as Int: sqlite3_bind_int64(statement, position, Int64(number))
            case let number as Double: sqlite3_bind_double(statement, position, number)
            default: sqlite3_bind_null(statement, position)
            }
        }
        var result: [T] = []
        while true {
            let code = sqlite3_step(statement)
            if code == SQLITE_ROW { result.append(map(Row(statement: statement))) }
            else if code == SQLITE_DONE { break }
            else { throw KaiKnowledgeError.sqlite(message()) }
        }
        return result
    }

    private struct Row {
        let statement: OpaquePointer?
        func text(_ column: Int32) -> String { sqlite3_column_text(statement, column).map { String(cString: $0) } ?? "" }
        func int(_ column: Int32) -> Int { Int(sqlite3_column_int64(statement, column)) }
        func double(_ column: Int32) -> Double { sqlite3_column_double(statement, column) }
        func isNull(_ column: Int32) -> Bool { sqlite3_column_type(statement, column) == SQLITE_NULL }
    }
}

// MARK: - Queries

enum KaiSearchQuery {
    /// Letters and digits only, so a query can never be read as FTS syntax.
    static func words(_ query: String) -> [String] {
        query.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .prefix(12)
            .map { $0 }
    }

    static func match(_ words: [String], all: Bool) -> String {
        words.map { "\"\($0)\"*" }.joined(separator: all ? " AND " : " OR ")
    }
}

// MARK: - Chunking

public enum KaiChunker {
    /// Paragraphs are packed up to `maxCharacters`. A paragraph longer than that is cut at spaces.
    public static func chunks(_ text: String, maxCharacters: Int) -> [String] {
        let paragraphs = text.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var result: [String] = []
        var current = ""
        func flush() {
            if !current.isEmpty { result.append(current); current = "" }
        }
        for paragraph in paragraphs {
            for piece in split(paragraph, maxCharacters: maxCharacters) {
                if current.isEmpty { current = piece }
                else if current.count + piece.count + 2 <= maxCharacters { current += "\n\n" + piece }
                else { flush(); current = piece }
            }
        }
        flush()
        return result
    }

    private static func split(_ paragraph: String, maxCharacters: Int) -> [String] {
        guard paragraph.count > maxCharacters else { return [paragraph] }
        var pieces: [String] = []
        var line = ""
        for word in paragraph.split(separator: " ", omittingEmptySubsequences: true) {
            if word.count > maxCharacters {
                if !line.isEmpty { pieces.append(line); line = "" }
                var rest = Substring(word)
                while rest.count > maxCharacters { pieces.append(String(rest.prefix(maxCharacters))); rest = rest.dropFirst(maxCharacters) }
                line = String(rest)
            } else if line.isEmpty { line = String(word) }
            else if line.count + word.count + 1 <= maxCharacters { line += " " + word }
            else { pieces.append(line); line = String(word) }
        }
        if !line.isEmpty { pieces.append(line) }
        return pieces
    }
}
