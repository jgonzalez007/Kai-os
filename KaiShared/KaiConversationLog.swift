//
//  KaiConversationLog.swift
//  Kai Shared
//
//  The one conversation Kai keeps between launches: what the person asked and what Kai answered, in chat and in
//  Sidekick. Text only (screenshots and approval cards are not kept), the newest few hundred messages, in a file only
//  this person can read. A file that can't be read is treated as an empty conversation and is never overwritten by a
//  newer program's format.
//

import Foundation

public struct KaiStoredMessage: Codable, Equatable, Sendable {
    public var id: String
    public var text: String
    public var isUser: Bool
    public var timestamp: Date
    /// "chat", "notice", "error" or "sidekick" (a line about a computer task).
    public var kind: String

    public init(id: String, text: String, isUser: Bool, timestamp: Date, kind: String) {
        self.id = id
        self.text = text
        self.isUser = isUser
        self.timestamp = timestamp
        self.kind = kind
    }
}

public struct KaiConversationLog: Sendable {
    public static let currentVersion = 1
    public static let maxMessages = 300
    public static let maxTextLength = 20_000

    private struct File: Codable {
        var version: Int
        var messages: [KaiStoredMessage]
    }

    public let url: URL

    public init(url: URL) { self.url = url }

    public static var standard: KaiConversationLog {
        KaiConversationLog(url: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kai OS", isDirectory: true).appendingPathComponent("conversation.json"))
    }

    public func load() -> [KaiStoredMessage] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let file = try? decoder.decode(File.self, from: data), file.version <= Self.currentVersion else { return [] }
        return Self.trimmed(file.messages)
    }

    /// Newest messages only, empty ones dropped, long ones cut.
    public static func trimmed(_ messages: [KaiStoredMessage]) -> [KaiStoredMessage] {
        messages.filter { !$0.text.isEmpty }.suffix(maxMessages).map { message in
            var copy = message
            if copy.text.count > maxTextLength { copy.text = String(copy.text.prefix(maxTextLength)) + "…" }
            return copy
        }
    }

    public func save(_ messages: [KaiStoredMessage]) throws {
        // Never replace a file written by a newer version of Kai with an older shape.
        if let data = try? Data(contentsOf: url), let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let version = existing["version"] as? Int, version > Self.currentVersion { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(File(version: Self.currentVersion, messages: Self.trimmed(messages))).write(to: url, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public func erase() { try? FileManager.default.removeItem(at: url) }
}
