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
        // One vector per chunk, for searching by meaning. Made by a local embedding model, and optional.
        try execute("CREATE TABLE IF NOT EXISTS embeddings(chunk_id INTEGER PRIMARY KEY, doc_id INTEGER NOT NULL, model TEXT NOT NULL, vector BLOB NOT NULL)")
        try execute("CREATE INDEX IF NOT EXISTS embeddings_doc ON embeddings(doc_id)")
        // What the local model made of each document (see KaiTriage): a summary, or the verdict that it is junk or private.
        try execute("CREATE TABLE IF NOT EXISTS summaries(doc_id INTEGER PRIMARY KEY, fingerprint TEXT NOT NULL, verdict TEXT NOT NULL, title TEXT NOT NULL, summary TEXT NOT NULL, model TEXT NOT NULL, created REAL NOT NULL)")
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
                try run("DELETE FROM embeddings WHERE doc_id = ?", [existing.0])
                try run("DELETE FROM summaries WHERE doc_id = ?", [existing.0])
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
            try run("DELETE FROM embeddings WHERE doc_id = ?", [id])
            try run("DELETE FROM summaries WHERE doc_id = ?", [id])
            try run("DELETE FROM documents WHERE id = ?", [id])
        }
        return gone.count
    }

    public func clear() throws {
        lock.lock(); defer { lock.unlock() }
        try execute("DELETE FROM chunks")
        try execute("DELETE FROM embeddings")
        try execute("DELETE FROM summaries")
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
    public func documents(limit: Int = 300, maxText: Int = 4_000, source: String? = nil) throws -> [KaiKnowledgeDocument] {
        lock.lock(); defer { lock.unlock() }
        let heads = try rows("SELECT id, source, source_id, title, modified, fingerprint FROM documents " + (source == nil ? "" : "WHERE source = ? ") + "ORDER BY COALESCE(modified, 0) DESC, id DESC LIMIT ?",
                             (source.map { [$0] } ?? []) + [max(limit, 1)]) { row in
            (id: row.int(0), source: row.text(1), sourceID: row.text(2), title: row.text(3),
             modified: row.isNull(4) ? nil : Date(timeIntervalSince1970: row.double(4)), fingerprint: row.text(5))
        }
        return try heads.map { head in
            let parts = try rows("SELECT text FROM chunks WHERE doc_id = ? ORDER BY rowid", [head.id]) { $0.text(0) }
            return KaiKnowledgeDocument(source: head.source, sourceID: head.sourceID, title: head.title,
                                        text: String(parts.joined(separator: "\n").prefix(maxText)), modified: head.modified, fingerprint: head.fingerprint)
        }
    }

    /// Some of every source, newest first within each, dealt out one source after another. Newest-first over everything
    /// would be all Slack on a busy workspace, and the graph and the portrait would never see mail, calendar or notes.
    public func balancedDocuments(perSource: Int = 60, maxText: Int = 4_000) throws -> [KaiKnowledgeDocument] {
        let names = try counts().keys.sorted()
        let lists = try names.map { try documents(limit: perSource, maxText: maxText, source: $0) }
        var out: [KaiKnowledgeDocument] = []
        for index in 0..<(lists.map(\.count).max() ?? 0) {
            for list in lists where index < list.count { out.append(list[index]) }
        }
        return out
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

    // MARK: Search by meaning

    /// A vector's length is made 1, so the dot product of two is their cosine similarity.
    public static func normalized(_ vector: [Float]) -> [Float] {
        let length = vector.reduce(0) { $0 + $1 * $1 }.squareRoot()
        return length > 0 ? vector.map { $0 / length } : vector
    }

    static func data(_ vector: [Float]) -> Data { vector.withUnsafeBufferPointer { Data(buffer: $0) } }
    static func vector(_ data: Data) -> [Float] { data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) } }

    /// Chunks that have no vector yet from `model`.
    public func chunksNeedingEmbedding(model: String, limit: Int) throws -> [(id: Int, text: String)] {
        lock.lock(); defer { lock.unlock() }
        return try rows("""
            SELECT chunks.rowid, chunks.text FROM chunks
            LEFT JOIN embeddings e ON e.chunk_id = chunks.rowid AND e.model = ?
            WHERE e.chunk_id IS NULL LIMIT ?
            """, [model, max(limit, 1)]) { (id: $0.int(0), text: $0.text(1)) }
    }

    public func saveEmbeddings(_ items: [(id: Int, vector: [Float])], model: String) throws {
        lock.lock(); defer { lock.unlock() }
        try execute("BEGIN")
        do {
            for item in items {
                guard let doc = try rows("SELECT doc_id FROM chunks WHERE rowid = ?", [item.id], { $0.int(0) }).first else { continue }
                try run("DELETE FROM embeddings WHERE chunk_id = ?", [item.id])
                try insertEmbedding(chunk: item.id, doc: doc, model: model, vector: Self.normalized(item.vector))
            }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func insertEmbedding(chunk: Int, doc: Int, model: String, vector: [Float]) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT INTO embeddings(chunk_id, doc_id, model, vector) VALUES(?,?,?,?)", -1, &statement, nil) == SQLITE_OK else { throw KaiKnowledgeError.sqlite(message()) }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_int64(statement, 1, Int64(chunk)); sqlite3_bind_int64(statement, 2, Int64(doc))
        sqlite3_bind_text(statement, 3, model, -1, transient)
        let blob = Self.data(vector)
        _ = blob.withUnsafeBytes { sqlite3_bind_blob(statement, 4, $0.baseAddress, Int32(blob.count), transient) }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw KaiKnowledgeError.sqlite(message()) }
    }

    /// How many chunks have a vector from `model`, out of all of them.
    public func embeddingProgress(model: String) throws -> (embedded: Int, total: Int) {
        lock.lock(); defer { lock.unlock() }
        let total = try rows("SELECT COUNT(*) FROM chunks", []) { $0.int(0) }.first ?? 0
        let done = try rows("SELECT COUNT(*) FROM embeddings WHERE model = ?", [model]) { $0.int(0) }.first ?? 0
        return (done, total)
    }

    /// Below this similarity a chunk is not about the question, however it ranks.
    public static let minimumSimilarity: Float = 0.5

    /// Documents whose best chunk is closest in meaning to `queryVector`, best first.
    public func meaningMatches(queryVector: [Float], model: String, limit: Int) throws -> [KaiKnowledgeHit] {
        let query = Self.normalized(queryVector)
        lock.lock(); defer { lock.unlock() }
        let all = try rows("SELECT chunk_id, doc_id, vector FROM embeddings WHERE model = ?", [model]) { row -> (Int, Int, Data) in
            let bytes = sqlite3_column_blob(row.statement, 2), count = Int(sqlite3_column_bytes(row.statement, 2))
            return (row.int(0), row.int(1), bytes.map { Data(bytes: $0, count: count) } ?? Data())
        }
        var best: [Int: (score: Float, chunk: Int)] = [:]
        for (chunk, doc, blob) in all {
            let vector = Self.vector(blob)
            guard vector.count == query.count else { continue }
            var dot: Float = 0
            for index in 0..<vector.count { dot += vector[index] * query[index] }
            if dot >= Self.minimumSimilarity, dot > (best[doc]?.score ?? -1) { best[doc] = (dot, chunk) }
        }
        var hits: [KaiKnowledgeHit] = []
        for (doc, found) in best.sorted(by: { $0.value.score > $1.value.score }).prefix(max(limit, 1)) {
            guard let head = try rows("SELECT source, source_id, title, modified FROM documents WHERE id = ?", [doc], { row in
                (row.text(0), row.text(1), row.text(2), row.isNull(3) ? nil : Date(timeIntervalSince1970: row.double(3)))
            }).first, let text = try rows("SELECT text FROM chunks WHERE rowid = ?", [found.chunk], { $0.text(0) }).first else { continue }
            hits.append(KaiKnowledgeHit(source: head.0, sourceID: head.1, title: head.2,
                                        snippet: String(text.replacingOccurrences(of: "\n", with: " ").prefix(260)), modified: head.3))
        }
        return hits
    }

    /// Words and meaning together: a document found by either is kept, and one found by both comes first
    /// (reciprocal rank fusion). Without a query vector this is the plain word search.
    public func search(_ query: String, queryVector: [Float]?, model: String?, limit: Int = 8) throws -> [KaiKnowledgeHit] {
        let byWords = try search(query, limit: limit * 2)
        guard let queryVector, let model else { return Array(byWords.prefix(limit)) }
        let byMeaning = try meaningMatches(queryVector: queryVector, model: model, limit: limit * 2)
        func key(_ hit: KaiKnowledgeHit) -> String { hit.source + "\u{1F}" + hit.sourceID }
        var score: [String: Double] = [:], hitFor: [String: KaiKnowledgeHit] = [:]
        for (rank, hit) in byWords.enumerated() { score[key(hit), default: 0] += 1 / Double(60 + rank); hitFor[key(hit)] = hit }
        for (rank, hit) in byMeaning.enumerated() { score[key(hit), default: 0] += 1 / Double(60 + rank); if hitFor[key(hit)] == nil { hitFor[key(hit)] = hit } }
        return score.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(limit).compactMap { hitFor[$0.key] }
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


// MARK: - Summaries

extension KaiKnowledgeStore {
    /// Documents that have no summary yet, or whose content changed since it was made. Newest first. Reference material
    /// is left out: it is searched, never used to describe the person.
    public func documentsNeedingSummary(limit: Int, maxText: Int = KaiTriage.maxInputCharacters) throws -> [KaiKnowledgeDocument] {
        lock.lock(); defer { lock.unlock() }
        let heads = try rows("""
            SELECT d.id, d.source, d.source_id, d.title, d.modified, d.fingerprint FROM documents d
            LEFT JOIN summaries s ON s.doc_id = d.id
            WHERE d.source != ? AND (s.doc_id IS NULL OR s.fingerprint != d.fingerprint)
            ORDER BY COALESCE(d.modified, 0) DESC, d.id DESC LIMIT ?
            """, [KaiKnowledgeIndexer.referenceSource, max(limit, 1)]) { row in
            (id: row.int(0), source: row.text(1), sourceID: row.text(2), title: row.text(3),
             modified: row.isNull(4) ? nil : Date(timeIntervalSince1970: row.double(4)), fingerprint: row.text(5))
        }
        return try heads.map { head in
            let parts = try rows("SELECT text FROM chunks WHERE doc_id = ? ORDER BY rowid", [head.id]) { $0.text(0) }
            return KaiKnowledgeDocument(source: head.source, sourceID: head.sourceID, title: head.title,
                                        text: String(parts.joined(separator: "\n").prefix(maxText)), modified: head.modified, fingerprint: head.fingerprint)
        }
    }

    /// Keeps the verdict for a document. Only a survivor keeps any text. The document must still have this fingerprint.
    public func saveSummary(for document: KaiKnowledgeDocument, outcome: KaiTriageOutcome, model: String) throws {
        lock.lock(); defer { lock.unlock() }
        guard let id = try rows("SELECT id FROM documents WHERE source = ? AND source_id = ? AND fingerprint = ?",
                                [document.source, document.sourceID, document.fingerprint], { $0.int(0) }).first else { return }
        let keep = outcome.verdict == .survivor
        try run("INSERT OR REPLACE INTO summaries(doc_id, fingerprint, verdict, title, summary, model, created) VALUES(?,?,?,?,?,?,?)",
                [id, document.fingerprint, outcome.verdict.rawValue, keep ? outcome.title : "", keep ? outcome.summary : "", model, Date().timeIntervalSince1970])
    }

    /// The summaries that survived, newest first, some of every source in turn so one chatty source can't crowd out the rest.
    public func survivorSummaries(perSource: Int = 80) throws -> [KaiSummaryRecord] {
        lock.lock(); defer { lock.unlock() }
        let names = try rows("SELECT DISTINCT d.source FROM documents d JOIN summaries s ON s.doc_id = d.id WHERE s.verdict = 'survivor'", []) { $0.text(0) }.sorted()
        let lists = try names.map { name in
            try rows("""
                SELECT d.source, d.source_id, d.title, s.title, s.summary, d.modified, d.fingerprint FROM documents d
                JOIN summaries s ON s.doc_id = d.id AND s.fingerprint = d.fingerprint
                WHERE s.verdict = 'survivor' AND d.source = ?
                ORDER BY COALESCE(d.modified, 0) DESC, d.id DESC LIMIT ?
                """, [name, max(perSource, 1)]) { row in
                KaiSummaryRecord(source: row.text(0), sourceID: row.text(1), documentTitle: row.text(2), title: row.text(3), summary: row.text(4),
                                 modified: row.isNull(5) ? nil : Date(timeIntervalSince1970: row.double(5)), fingerprint: row.text(6))
            }
        }
        var out: [KaiSummaryRecord] = []
        for index in 0..<(lists.map(\.count).max() ?? 0) {
            for list in lists where index < list.count { out.append(list[index]) }
        }
        return out
    }

    public func summaryCounts() throws -> KaiSummaryCounts {
        lock.lock(); defer { lock.unlock() }
        var counts = KaiSummaryCounts()
        for (verdict, number) in try rows("SELECT s.verdict, COUNT(*) FROM summaries s JOIN documents d ON d.id = s.doc_id AND d.fingerprint = s.fingerprint GROUP BY s.verdict", [], { ($0.text(0), $0.int(1)) }) {
            switch verdict {
            case "survivor": counts.survivors = number
            case "junk": counts.junk = number
            case "sensitive": counts.sensitive = number
            default: break
            }
        }
        counts.pending = try rows("""
            SELECT COUNT(*) FROM documents d LEFT JOIN summaries s ON s.doc_id = d.id
            WHERE d.source != ? AND (s.doc_id IS NULL OR s.fingerprint != d.fingerprint)
            """, [KaiKnowledgeIndexer.referenceSource]) { $0.int(0) }.first ?? 0
        return counts
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
