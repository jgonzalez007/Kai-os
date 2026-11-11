//
//  KaiToday.swift
//  Kai Local Data
//
//  What the Today card lists as it is, not as a model picked it: the day's events, reminders that are due or
//  overdue, and mail that is waiting. Reminders are read with the system's own permission, on this Mac only.
//

import EventKit
import Foundation

public struct KaiTodayReminder: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let due: Date?
    public let list: String
    /// 1 is the highest priority in Reminders, 0 means none.
    public let priority: Int
    public let isOverdue: Bool

    public init(id: String, title: String, due: Date?, list: String, priority: Int, isOverdue: Bool) {
        self.id = id
        self.title = title
        self.due = due
        self.list = list
        self.priority = priority
        self.isOverdue = isOverdue
    }
}

public enum KaiRemindersSource {
    public static var access: KaiCalendarAccess {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess: return .granted
        case .notDetermined: return .notRequested
        default: return .denied
        }
    }

    /// Shows the system permission prompt the first time it runs.
    public static func requestAccess() async throws -> Bool {
        try await EKEventStore().requestFullAccessToReminders()
    }

    /// Reminders not yet done that are due by the end of today, including overdue ones, most urgent first.
    public static func dueByEndOfToday(now: Date = Date(), calendar: Calendar = .current) async -> [KaiTodayReminder] {
        guard access == .granted else { return [] }
        let store = EKEventStore()
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: end, calendars: nil)
        let found: [KaiTodayReminder] = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                let items = (reminders ?? []).map { reminder -> KaiTodayReminder in
                    let due = reminder.dueDateComponents.flatMap { calendar.date(from: $0) }
                    return KaiTodayReminder(id: reminder.calendarItemIdentifier, title: reminder.title ?? "Untitled", due: due,
                                            list: reminder.calendar?.title ?? "", priority: reminder.priority,
                                            isOverdue: due.map { $0 < calendar.startOfDay(for: now) } ?? false)
                }
                continuation.resume(returning: items)
            }
        }
        return KaiToday.sorted(reminders: found)
    }
}

/// How the day's items are ordered and split. Plain functions, so they can be tested.
public enum KaiToday {
    /// Overdue first, then by due time, then by priority. Reminders with no time come after the timed ones of the same day.
    public static func sorted(reminders: [KaiTodayReminder]) -> [KaiTodayReminder] {
        func rank(_ r: KaiTodayReminder) -> Int { r.priority == 0 ? 10 : r.priority }
        return reminders.sorted {
            if $0.isOverdue != $1.isOverdue { return $0.isOverdue }
            if ($0.due ?? .distantFuture) != ($1.due ?? .distantFuture) { return ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
            if rank($0) != rank($1) { return rank($0) < rank($1) }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    public struct Schedule: Equatable, Sendable {
        public var allDay: [KaiCalendarItem] = []
        public var happeningNow: [KaiCalendarItem] = []
        public var upcoming: [KaiCalendarItem] = []
        public var finished: [KaiCalendarItem] = []
        public var tomorrow: [KaiCalendarItem] = []
        public init() {}
        public var isEmpty: Bool { allDay.isEmpty && happeningNow.isEmpty && upcoming.isEmpty && finished.isEmpty && tomorrow.isEmpty }
    }

    /// Splits events into what is on all day, happening now, still to come today, already over, and tomorrow's.
    /// Cancelled events are left out. Events you've marked free still show: they are on your calendar.
    public static func schedule(events: [KaiCalendarItem], now: Date = Date(), calendar: Calendar = .current) -> Schedule {
        var result = Schedule()
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        for event in events.sorted(by: { $0.start < $1.start }) where !event.isCancelled {
            if event.start >= startOfTomorrow { result.tomorrow.append(event); continue }
            if event.isAllDay { result.allDay.append(event); continue }
            if event.end <= now { result.finished.append(event) }
            else if event.start <= now { result.happeningNow.append(event) }
            else { result.upcoming.append(event) }
        }
        return result
    }

    /// Flagged mail first, then newest. Mail the person muted is left out by the caller.
    public static func ranked(mail: [KaiBriefingMail]) -> [KaiBriefingMail] {
        mail.sorted {
            if $0.isFlagged != $1.isFlagged { return $0.isFlagged }
            return $0.date > $1.date
        }
    }

    /// "9:30 AM – 10:00 AM", or "All day".
    public static func timeRange(_ event: KaiCalendarItem) -> String {
        if event.isAllDay { return "All day" }
        let style = Date.FormatStyle.dateTime.hour().minute()
        return "\(event.start.formatted(style)) – \(event.end.formatted(style))"
    }
}
