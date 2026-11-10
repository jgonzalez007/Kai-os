//
//  KaiCalendarPlanner.swift
//  Kai Local Data
//
//  Two questions about a calendar, answered from the events already read: which events overlap, and when is
//  there a free stretch of a given length. Nothing here changes the calendar. Adding an event is a separate
//  step the person approves.
//

import Foundation

public enum KaiCalendarPlanner {
    /// Events that count as taking time: a cancelled one, one marked "free", and an all-day one do not.
    static func occupies(_ event: KaiCalendarItem) -> Bool {
        !event.isCancelled && !event.showsAsFree && !event.isAllDay && event.end > event.start
    }

    /// For each event, the other events it overlaps. An event that ends exactly when another starts does not overlap it.
    public static func conflicts(in events: [KaiCalendarItem]) -> [String: [KaiCalendarItem]] {
        let busy = events.filter(occupies).sorted { ($0.start, $0.id) < ($1.start, $1.id) }
        var result: [String: [KaiCalendarItem]] = [:]
        for (index, a) in busy.enumerated() {
            for b in busy[(index + 1)...] {
                if b.start >= a.end { break }
                guard a.id != b.id else { continue }
                result[a.id, default: []].append(b)
                result[b.id, default: []].append(a)
            }
        }
        return result
    }

    public struct Window: Equatable, Sendable {
        public var startHour: Int
        public var endHour: Int
        public var skipWeekends: Bool
        public init(startHour: Int = 9, endHour: Int = 17, skipWeekends: Bool = true) {
            self.startHour = min(max(startHour, 0), 23)
            self.endHour = min(max(endHour, self.startHour + 1), 24)
            self.skipWeekends = skipWeekends
        }
    }

    /// Free stretches of at least `minutes`, inside the working window, from `now` forward over `days` days. Each one
    /// starts on the hour or half hour, with `buffer` minutes kept clear around other events. Earliest first, at most `limit`.
    public static func freeSlots(events: [KaiCalendarItem], from now: Date, days: Int, minutes: Int, window: Window = Window(),
                                 buffer: Int = 0, limit: Int = 6, calendar: Calendar = .current) -> [DateInterval] {
        let length = TimeInterval(max(minutes, 5) * 60), pad = TimeInterval(max(buffer, 0) * 60)
        let busy = events.filter(occupies).map { DateInterval(start: $0.start.addingTimeInterval(-pad), end: $0.end.addingTimeInterval(pad)) }
            .sorted { $0.start < $1.start }
        var slots: [DateInterval] = []
        let today = calendar.startOfDay(for: now)
        for offset in 0..<max(days, 1) {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            if window.skipWeekends, calendar.isDateInWeekend(day) { continue }
            guard let open = calendar.date(bySettingHour: window.startHour, minute: 0, second: 0, of: day),
                  let close = window.endHour >= 24 ? calendar.date(byAdding: .day, value: 1, to: day) : calendar.date(bySettingHour: window.endHour, minute: 0, second: 0, of: day) else { continue }
            var cursor = max(open, roundedUp(now, calendar: calendar))
            while cursor.addingTimeInterval(length) <= close {
                let candidate = DateInterval(start: cursor, end: cursor.addingTimeInterval(length))
                if let clash = busy.first(where: { $0.start < candidate.end && candidate.start < $0.end }) {
                    cursor = roundedUp(clash.end, calendar: calendar)
                } else {
                    slots.append(candidate)
                    if slots.count == limit { return slots }
                    // Offer the next stretch after this one, not one that overlaps it.
                    cursor = candidate.end
                }
            }
        }
        return slots
    }

    /// The next half hour at or after `date`.
    static func roundedUp(_ date: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: date)
        let seconds = date.timeIntervalSince(start)
        return start.addingTimeInterval((seconds / 1_800).rounded(.up) * 1_800)
    }
}
