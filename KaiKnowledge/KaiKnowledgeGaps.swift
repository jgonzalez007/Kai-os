//
//  KaiKnowledgeGaps.swift
//  Kai Knowledge
//
//  The questions Kai searched for and found nothing about. They show what the person could add (a file, a
//  folder, a note) so Kai can answer next time. A small private file; the person can clear it.
//

import Foundation

public struct KaiKnowledgeGap: Codable, Equatable, Identifiable, Sendable {
    public var id: String { query.lowercased() }
    public var query: String
    public var count: Int
    public var lastAsked: Date

    public init(query: String, count: Int = 1, lastAsked: Date = Date()) {
        self.query = query
        self.count = count
        self.lastAsked = lastAsked
    }
}

public struct KaiKnowledgeGapStore: Sendable {
    public static let maxGaps = 30
    public let url: URL

    public init(url: URL) { self.url = url }

    public static var standard: KaiKnowledgeGapStore {
        KaiKnowledgeGapStore(url: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kai OS", isDirectory: true).appendingPathComponent("knowledge-gaps.json"))
    }

    public func load() -> [KaiKnowledgeGap] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return ((try? decoder.decode([KaiKnowledgeGap].self, from: data)) ?? []).sorted { $0.lastAsked > $1.lastAsked }
    }

    public func save(_ gaps: [KaiKnowledgeGap]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(gaps).write(to: url, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    /// A search phrase as one short line: no control characters, at most 120 characters. Nil when nothing is left.
    public static func clean(_ query: String) -> String? {
        let scalars = query.unicodeScalars.map { CharacterSet.controlCharacters.contains($0) ? " " : Character($0) }
        let line = String(scalars).split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        return line.count < 3 ? nil : String(line.prefix(120))
    }

    /// Adds one miss: a repeat raises its count, and the list keeps the 30 most recent.
    public static func recording(_ query: String, in gaps: [KaiKnowledgeGap], now: Date = Date()) -> [KaiKnowledgeGap] {
        guard let line = clean(query) else { return gaps }
        var list = gaps
        if let index = list.firstIndex(where: { $0.id == line.lowercased() }) {
            list[index].count += 1
            list[index].lastAsked = now
        } else {
            list.append(KaiKnowledgeGap(query: line, lastAsked: now))
        }
        return Array(list.sorted { $0.lastAsked > $1.lastAsked }.prefix(maxGaps))
    }
}
