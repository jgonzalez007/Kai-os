//
//  KaiMailSavedViews.swift
//  Kai Local Data
//
//  Mail views the person builds themselves ("Unread from Dana", "Flagged, older than a week"). A view is only a
//  filter over the inbox Kai already shows: it never changes mail, so making or removing one needs no approval.
//  The list is kept in Kai's own settings, in the person's words, and never leaves this Mac.
//

import Foundation

public struct KaiMailSavedView: Codable, Equatable, Identifiable, Sendable {
    public static let maxNameLength = 40
    public static let maxTextLength = 80
    public static let maxViews = 12

    public var id: String
    public var name: String
    public var senderContains: String
    public var subjectContains: String
    public var unreadOnly: Bool
    public var flaggedOnly: Bool
    /// Only messages received at least this many days ago (0 = no limit).
    public var olderThanDays: Int
    /// Only messages received within this many days (0 = no limit).
    public var withinDays: Int

    public init(id: String = UUID().uuidString, name: String, senderContains: String = "", subjectContains: String = "",
                unreadOnly: Bool = false, flaggedOnly: Bool = false, olderThanDays: Int = 0, withinDays: Int = 0) {
        self.id = id
        self.name = name
        self.senderContains = senderContains
        self.subjectContains = subjectContains
        self.unreadOnly = unreadOnly
        self.flaggedOnly = flaggedOnly
        self.olderThanDays = olderThanDays
        self.withinDays = withinDays
    }

    /// A view with no condition would be the whole inbox, which is already "All".
    public var hasCondition: Bool {
        !senderContains.isEmpty || !subjectContains.isEmpty || unreadOnly || flaggedOnly || olderThanDays > 0 || withinDays > 0
    }

    /// The same view with clean text and sane numbers, or nil when it can't be kept.
    public func cleaned() -> KaiMailSavedView? {
        func clean(_ text: String, _ limit: Int) -> String {
            String(text.components(separatedBy: .newlines).joined(separator: " ").trimmingCharacters(in: .whitespaces).prefix(limit))
        }
        var copy = self
        copy.name = clean(name, Self.maxNameLength)
        copy.senderContains = clean(senderContains, Self.maxTextLength)
        copy.subjectContains = clean(subjectContains, Self.maxTextLength)
        copy.olderThanDays = min(max(olderThanDays, 0), 3_650)
        copy.withinDays = min(max(withinDays, 0), 3_650)
        guard !copy.name.isEmpty, copy.hasCondition else { return nil }
        if copy.olderThanDays > 0, copy.withinDays > 0, copy.withinDays <= copy.olderThanDays { return nil }
        return copy
    }

    public func matches(sender: String, subject: String, isRead: Bool, isFlagged: Bool, date: Date, now: Date = Date()) -> Bool {
        if unreadOnly && isRead { return false }
        if flaggedOnly && !isFlagged { return false }
        if !senderContains.isEmpty && !sender.localizedCaseInsensitiveContains(senderContains) { return false }
        if !subjectContains.isEmpty && !subject.localizedCaseInsensitiveContains(subjectContains) { return false }
        let age = now.timeIntervalSince(date)
        if olderThanDays > 0 && age < Double(olderThanDays) * 86_400 { return false }
        if withinDays > 0 && age > Double(withinDays) * 86_400 { return false }
        return true
    }

    /// The conditions in words, for the sidebar and for the assistant to read back.
    public var summary: String {
        var parts: [String] = []
        if unreadOnly { parts.append("unread") }
        if flaggedOnly { parts.append("flagged") }
        if !senderContains.isEmpty { parts.append("from “\(senderContains)”") }
        if !subjectContains.isEmpty { parts.append("subject has “\(subjectContains)”") }
        if olderThanDays > 0 { parts.append("older than \(olderThanDays) day\(olderThanDays == 1 ? "" : "s")") }
        if withinDays > 0 { parts.append("in the last \(withinDays) day\(withinDays == 1 ? "" : "s")") }
        return parts.joined(separator: ", ")
    }
}

public struct KaiMailSavedViewStore: Sendable {
    public static let key = "kai.mail.savedViews"
    private let defaults: UncheckedDefaults

    /// UserDefaults isn't Sendable, but it is documented as thread safe.
    private struct UncheckedDefaults: @unchecked Sendable { let value: UserDefaults }

    public init(defaults: UserDefaults = .standard) { self.defaults = UncheckedDefaults(value: defaults) }

    public static var standard: KaiMailSavedViewStore { KaiMailSavedViewStore() }

    public func load() -> [KaiMailSavedView] {
        guard let data = defaults.value.data(forKey: Self.key), let list = try? JSONDecoder().decode([KaiMailSavedView].self, from: data) else { return [] }
        return list.compactMap { $0.cleaned() }.prefix(KaiMailSavedView.maxViews).map { $0 }
    }

    private func save(_ views: [KaiMailSavedView]) {
        if let data = try? JSONEncoder().encode(views) { defaults.value.set(data, forKey: Self.key) }
    }

    public enum Problem: Error, Equatable, LocalizedError {
        case unusable, tooMany
        public var errorDescription: String? {
            switch self {
            case .unusable: return "A view needs a name and at least one condition (a sender, a subject, unread, flagged or an age), and its age limits have to make sense together."
            case .tooMany: return "There are already \(KaiMailSavedView.maxViews) views. Remove one first."
            }
        }
    }

    /// Adds a view, or replaces the one with the same name (without regard to capitals).
    @discardableResult
    public func add(_ view: KaiMailSavedView) throws -> [KaiMailSavedView] {
        guard let clean = view.cleaned() else { throw Problem.unusable }
        var list = load()
        if let index = list.firstIndex(where: { $0.name.caseInsensitiveCompare(clean.name) == .orderedSame }) {
            var replacement = clean
            replacement.id = list[index].id
            list[index] = replacement
        } else {
            guard list.count < KaiMailSavedView.maxViews else { throw Problem.tooMany }
            list.append(clean)
        }
        save(list)
        return list
    }

    /// Removes by id or by name. Returns what is left.
    @discardableResult
    public func remove(idOrName: String) -> [KaiMailSavedView] {
        let list = load().filter { $0.id != idOrName && $0.name.caseInsensitiveCompare(idOrName) != .orderedSame }
        save(list)
        return list
    }
}
