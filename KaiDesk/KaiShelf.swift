//
//  KaiShelf.swift
//  Kai Desk
//
//  A holding area for files, links and text. Files are kept by reference (their path), never copied.
//  Dragging an item out removes it, and the removal can be undone for a few seconds.
//  Pinned items stay.
//

import Foundation

public struct KaiShelfItem: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable { case file, link, text }

    public let id: UUID
    public var kind: Kind
    /// A file path, a URL string, or the text itself.
    public var value: String
    public var date: Date
    public var pinned: Bool

    public init(id: UUID = UUID(), kind: Kind, value: String, date: Date, pinned: Bool = false) {
        self.id = id
        self.kind = kind
        self.value = value
        self.date = date
        self.pinned = pinned
    }

    public var title: String {
        switch kind {
        case .file: return URL(fileURLWithPath: value).lastPathComponent
        case .link:
            return URL(string: value).flatMap { $0.host ?? $0.absoluteString } ?? value
        case .text:
            let flat = value.split(whereSeparator: \.isNewline).joined(separator: " ")
            return flat.count > 80 ? String(flat.prefix(80)) + "…" : flat
        }
    }

    public var detail: String? {
        switch kind {
        case .file: return URL(fileURLWithPath: value).deletingLastPathComponent().path
        case .link: return value
        case .text: return nil
        }
    }

    public var fileURL: URL? { kind == .file ? URL(fileURLWithPath: value) : nil }

    /// A dropped string is a link when it is one http(s) URL, otherwise text.
    public static func fromString(_ string: String, now: Date) -> KaiShelfItem? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if !trimmed.contains(where: \.isWhitespace),
           let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https", url.host != nil {
            return KaiShelfItem(kind: .link, value: trimmed, date: now)
        }
        return KaiShelfItem(kind: .text, value: string, date: now)
    }
}

public struct KaiShelf: Codable, Equatable, Sendable {
    public static let undoWindow: TimeInterval = 5
    public static let capacity = 100

    public private(set) var items: [KaiShelfItem]

    /// The last item taken out, kept only until `undoDeadline`. Not saved to disk.
    public private(set) var lastRemoved: (item: KaiShelfItem, index: Int)?
    public private(set) var undoDeadline: Date?

    private enum CodingKeys: String, CodingKey { case items }

    public init(items: [KaiShelfItem] = []) {
        self.items = items
    }

    public init(from decoder: Decoder) throws {
        items = try decoder.container(keyedBy: CodingKeys.self).decode([KaiShelfItem].self, forKey: .items)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(items, forKey: .items)
    }

    public static func == (lhs: KaiShelf, rhs: KaiShelf) -> Bool { lhs.items == rhs.items }

    /// Adds an item at the top. Dropping the same file or link again only moves it up.
    @discardableResult
    public mutating func add(_ item: KaiShelfItem) -> Bool {
        if item.kind != .text, let index = items.firstIndex(where: { $0.kind == item.kind && $0.value == item.value }) {
            var existing = items.remove(at: index)
            existing.date = item.date
            items.insert(existing, at: 0)
            return false
        }
        items.insert(item, at: 0)
        if items.count > Self.capacity, let drop = items.lastIndex(where: { !$0.pinned }) {
            items.remove(at: drop)
        }
        return true
    }

    public mutating func addFile(_ url: URL, now: Date = Date()) {
        add(KaiShelfItem(kind: .file, value: url.standardizedFileURL.path, date: now))
    }

    public mutating func addString(_ string: String, now: Date = Date()) {
        if let item = KaiShelfItem.fromString(string, now: now) { add(item) }
    }

    public mutating func togglePin(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].pinned.toggle()
    }

    /// Plain removal (the delete button). Not undoable.
    public mutating func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
    }

    /// Called when an item was dragged out. A pinned item stays. Others leave, and can be restored
    /// with `undo` until the window closes. Returns true when the item left.
    @discardableResult
    public mutating func takeOut(_ id: UUID, now: Date = Date()) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }), !items[index].pinned else { return false }
        lastRemoved = (items.remove(at: index), index)
        undoDeadline = now.addingTimeInterval(Self.undoWindow)
        return true
    }

    public func canUndo(now: Date = Date()) -> Bool {
        guard lastRemoved != nil, let deadline = undoDeadline else { return false }
        return now < deadline
    }

    /// Puts the last dragged-out item back where it was. Returns false when the window has closed.
    @discardableResult
    public mutating func undo(now: Date = Date()) -> Bool {
        guard canUndo(now: now), let removed = lastRemoved else { return false }
        items.insert(removed.item, at: min(removed.index, items.count))
        lastRemoved = nil
        undoDeadline = nil
        return true
    }

    /// Forgets an expired undo. The app calls this when the banner goes away.
    public mutating func expireUndo(now: Date = Date()) {
        if !canUndo(now: now) {
            lastRemoved = nil
            undoDeadline = nil
        }
    }

    public mutating func clear(includingPinned: Bool = false) {
        items = includingPinned ? [] : items.filter(\.pinned)
        lastRemoved = nil
        undoDeadline = nil
    }
}
