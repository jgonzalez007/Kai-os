//
//  KaiMailCache.swift
//  Kai Local Data
//
//  The last list of inbox messages Kai read (sender, subject, date, read or not), kept in a private file so the
//  Mail page opens at once while Apple Mail, which can take a minute on a big inbox, answers. Bodies are never
//  kept. The file is deleted when Mail is disconnected.
//

import Foundation

public struct KaiMailListCache: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    public static var standard: KaiMailListCache {
        KaiMailListCache(url: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kai OS", isDirectory: true).appendingPathComponent("mail-list.json"))
    }

    private struct Stored: Codable {
        struct Row: Codable {
            let id: String, sender: String, subject: String, date: Date, isRead: Bool, isFlagged: Bool, account: String, mailbox: String
        }
        let savedAt: Date
        let rows: [Row]
    }

    public func save(_ items: [KaiMailItem], at now: Date = Date()) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let stored = Stored(savedAt: now, rows: items.map { .init(id: $0.id, sender: $0.sender, subject: $0.subject, date: $0.date, isRead: $0.isRead, isFlagged: $0.isFlagged, account: $0.account, mailbox: $0.mailbox) })
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(stored).write(to: url, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public func load() -> (items: [KaiMailItem], savedAt: Date)? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let stored = try? decoder.decode(Stored.self, from: data), !stored.rows.isEmpty else { return nil }
        return (stored.rows.map { KaiMailItem(id: $0.id, sender: $0.sender, subject: $0.subject, date: $0.date, isRead: $0.isRead, isFlagged: $0.isFlagged, account: $0.account, mailbox: $0.mailbox) }, stored.savedAt)
    }

    public func delete() { try? FileManager.default.removeItem(at: url) }
}
