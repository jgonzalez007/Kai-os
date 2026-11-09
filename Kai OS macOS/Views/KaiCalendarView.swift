//
//  KaiCalendarView.swift
//  Kai OS macOS
//
//  The calendar page: a month on the left to pick a day, that day as a timeline (or the next two weeks
//  as a list) in the middle, and what an event holds on the right when you click it. It only reads
//  Apple Calendar; it never changes an event.
//

import AppKit
import KaiLocalData
import SwiftUI

struct KaiCalendarView: View {
    @EnvironmentObject var appState: AppState

    private enum Mode: String, CaseIterable { case day = "Day", upcoming = "Upcoming" }

    @State private var mode = Mode.day
    @State private var items: [KaiCalendarItem] = []
    @State private var month = Calendar.current.startOfDay(for: Date())
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    @State private var selectedID: String?
    @State private var hiddenCalendars: Set<String> = []

    private let calendar = Calendar.current
    private let hourHeight: CGFloat = 56

    private var selected: KaiCalendarItem? { items.first { $0.id == selectedID } }
    private var visible: [KaiCalendarItem] { items.filter { !hiddenCalendars.contains($0.calendarName) } }

    var body: some View {
        Group {
            if appState.calendarConnected {
                VStack(spacing: 14) {
                    header
                    KaiSourceErrorBanner(state: appState.calendarState)
                    HStack(alignment: .top, spacing: 16) {
                        sidebar.frame(width: 260)
                        center
                        if let event = selected { details(event).frame(width: 360).transition(.move(edge: .trailing).combined(with: .opacity)) }
                    }
                    .animation(.easeOut(duration: 0.18), value: selectedID)
                }
                .padding(.horizontal, 28).padding(.bottom, 24)
            } else {
                KaiConnectCard(
                    title: "Calendar",
                    icon: "calendar",
                    explanation: "Kai OS reads your events from Apple Calendar. It can't change them, and nothing leaves this Mac.",
                    state: appState.calendarState,
                    connect: appState.connectCalendar
                )
            }
        }
        .onAppear { if appState.calendarConnected { reload() } }
        .onChange(of: appState.calendarConnected) { _, connected in if connected { reload() } }
        .onChange(of: month) { _, _ in reload() }
    }

    // MARK: Data

    /// The six weeks the month grid shows, plus two weeks after, so Upcoming has something to list.
    private var loadRange: (Date, Date) {
        let start = gridDays.first ?? month
        let end = calendar.date(byAdding: .day, value: 14, to: (gridDays.last ?? month)) ?? month
        return (min(start, selectedDay), max(end, calendar.date(byAdding: .day, value: 15, to: selectedDay) ?? end))
    }

    private func reload() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["KAI_PAGE_SNAPSHOT_DIR"] != nil {
            items = Self.sampleEvents()
            selectedID = items.dropFirst(2).first?.id
            return
        }
        #endif
        let (start, end) = loadRange
        Task.detached {
            let found = KaiCalendarSource.events(from: start, to: end)
            await MainActor.run {
                items = found
                if let selectedID, !found.contains(where: { $0.id == selectedID }) { self.selectedID = nil }
            }
        }
    }

    private func events(on day: Date) -> [KaiCalendarItem] {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return visible.filter { $0.start < end && $0.end > start || ($0.start == $0.end && $0.start >= start && $0.start < end) }
            .sorted { ($0.isAllDay ? 0 : 1, $0.start) < ($1.isAllDay ? 0 : 1, $1.start) }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Calendar").font(.system(size: 26, weight: .semibold))
                Text(selectedDay.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { step(-1) } label: { Image(systemName: "chevron.left") }.buttonStyle(.plain).padding(.horizontal, 4)
            Button("Today") { goToToday() }.controlSize(.small)
            Button { step(1) } label: { Image(systemName: "chevron.right") }.buttonStyle(.plain).padding(.horizontal, 4)
            Picker("", selection: $mode) { ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).labelsHidden().frame(width: 160)
            Button { appState.refreshCalendar(); reload() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.plain).help("Read the calendar again")
        }
        .padding(.top, 4)
    }

    private func step(_ days: Int) {
        selectedDay = calendar.date(byAdding: .day, value: days, to: selectedDay) ?? selectedDay
        syncMonth()
    }

    private func goToToday() {
        selectedDay = calendar.startOfDay(for: Date())
        syncMonth()
    }

    private func syncMonth() {
        if !calendar.isDate(selectedDay, equalTo: month, toGranularity: .month) { month = selectedDay }
    }

    // MARK: Month

    private var gridDays: [Date] {
        guard let first = calendar.dateInterval(of: .month, for: month)?.start,
              let weekStart = calendar.dateInterval(of: .weekOfYear, for: first)?.start else { return [] }
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(spacing: 8) {
                HStack {
                    Text(month.formatted(.dateTime.month(.wide).year())).font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Button { month = calendar.date(byAdding: .month, value: -1, to: month) ?? month } label: { Image(systemName: "chevron.left") }.buttonStyle(.plain)
                    Button { month = calendar.date(byAdding: .month, value: 1, to: month) ?? month } label: { Image(systemName: "chevron.right") }.buttonStyle(.plain)
                }
                let symbols = weekdayHeaders
                HStack(spacing: 0) {
                    ForEach(symbols.indices, id: \.self) { Text(symbols[$0]).font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity) }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 2) {
                    ForEach(gridDays, id: \.self) { day in dayCell(day) }
                }
            }
            .padding(14)
            .kaiLiquidGlass(KaiColor.cyan, radius: 18, glow: 0.08)

            let names = Array(Set(items.map(\.calendarName))).filter { !$0.isEmpty }.sorted()
            if !names.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Calendars").font(.caption).foregroundStyle(.secondary)
                    ForEach(names, id: \.self) { name in
                        let off = hiddenCalendars.contains(name)
                        Button {
                            if off { hiddenCalendars.remove(name) } else { hiddenCalendars.insert(name) }
                        } label: {
                            HStack(spacing: 8) {
                                Circle().fill(color(forCalendar: name)).frame(width: 9, height: 9)
                                Text(name).lineLimit(1).font(.callout)
                                Spacer()
                                Image(systemName: off ? "eye.slash" : "eye").font(.caption).foregroundStyle(.secondary)
                            }
                            .opacity(off ? 0.45 : 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .kaiLiquidGlass(KaiColor.violet, radius: 18, glow: 0.06)
            }
            Spacer(minLength: 0)
        }
    }

    private var weekdayHeaders: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private func dayCell(_ day: Date) -> some View {
        let inMonth = calendar.isDate(day, equalTo: month, toGranularity: .month)
        let isToday = calendar.isDateInToday(day)
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDay)
        let count = events(on: day).count
        return Button {
            selectedDay = calendar.startOfDay(for: day)
            selectedID = nil
            if !inMonth { month = day }
        } label: {
            VStack(spacing: 2) {
                Text("\(calendar.component(.day, from: day))")
                    .font(.system(size: 12, weight: isToday ? .bold : .regular))
                    .foregroundStyle(isSelected ? Color.black : isToday ? KaiColor.cyan : .white.opacity(inMonth ? 0.9 : 0.3))
                Circle().fill(count > 0 ? (isSelected ? Color.black.opacity(0.6) : KaiColor.cyan.opacity(min(1, 0.4 + Double(count) * 0.15))) : .clear)
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity).frame(height: 34)
            .background(Circle().fill(isSelected ? Color.white : isToday ? KaiColor.cyan.opacity(0.15) : .clear).frame(width: 32, height: 32))
        }
        .buttonStyle(.plain)
    }

    private func color(forCalendar name: String) -> Color {
        guard let rgb = items.first(where: { $0.calendarName == name })?.calendarColor else { return KaiColor.liquidBlue }
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    private func color(_ item: KaiCalendarItem) -> Color {
        guard let rgb = item.calendarColor else { return KaiColor.liquidBlue }
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    // MARK: Center

    @ViewBuilder
    private var center: some View {
        Group {
            if mode == .day { dayTimeline } else { upcomingList }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Day timeline

    private var dayTimeline: some View {
        let day = events(on: selectedDay)
        let allDay = day.filter(\.isAllDay)
        let timed = day.filter { !$0.isAllDay }
        let firstHour = max(0, min(7, (timed.map { calendar.component(.hour, from: $0.start) }.min() ?? 8) - 1))
        let lastHour = min(24, max(19, (timed.map { calendar.component(.hour, from: $0.end) + 1 }.max() ?? 18) + 1))
        return VStack(alignment: .leading, spacing: 10) {
            if !allDay.isEmpty {
                HStack(spacing: 6) {
                    Text("All day").font(.caption).foregroundStyle(.secondary)
                    ForEach(allDay) { event in
                        Button { selectedID = event.id } label: {
                            Text(event.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(Capsule().fill(color(event).opacity(0.35)))
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
            }
            if timed.isEmpty && allDay.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "calendar").font(.system(size: 30)).foregroundStyle(.secondary)
                    Text(calendar.isDateInToday(selectedDay) ? "Nothing scheduled today" : "Nothing scheduled this day").font(.headline)
                    Button("See what's coming") { mode = .upcoming }.controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    ZStack(alignment: .topLeading) {
                        hourGrid(firstHour, lastHour)
                        GeometryReader { geo in
                            let width = geo.size.width - 52
                            ForEach(layout(timed), id: \.item.id) { placed in
                                eventBlock(placed.item, firstHour: firstHour)
                                    .frame(width: max(40, width / CGFloat(placed.columns) - 4),
                                           height: max(26, blockHeight(placed.item)))
                                    .offset(x: 52 + width / CGFloat(placed.columns) * CGFloat(placed.column),
                                            y: offset(of: placed.item.start, firstHour: firstHour))
                            }
                            if calendar.isDateInToday(selectedDay) { nowLine(firstHour: firstHour, lastHour: lastHour, width: geo.size.width) }
                        }
                    }
                    .frame(height: CGFloat(lastHour - firstHour) * hourHeight + 8)
                }
            }
        }
        .padding(16)
        .kaiLiquidGlass(KaiColor.cyan, radius: 18, glow: 0.08)
    }

    private func hourGrid(_ first: Int, _ last: Int) -> some View {
        VStack(spacing: 0) {
            ForEach(first..<last, id: \.self) { hour in
                HStack(alignment: .top, spacing: 8) {
                    Text(hourLabel(hour)).font(.system(size: 10)).foregroundStyle(.secondary).frame(width: 44, alignment: .trailing).offset(y: -6)
                    VStack { Divider().overlay(Color.white.opacity(0.08)); Spacer() }
                }
                .frame(height: hourHeight)
            }
        }
        .padding(.top, 8)
    }

    private func hourLabel(_ hour: Int) -> String {
        let date = calendar.date(bySettingHour: hour % 24, minute: 0, second: 0, of: Date()) ?? Date()
        return date.formatted(.dateTime.hour())
    }

    private func offset(of date: Date, firstHour: Int) -> CGFloat {
        let start = calendar.startOfDay(for: selectedDay)
        let clamped = max(date, start)
        let hours = clamped.timeIntervalSince(start) / 3600 - Double(firstHour)
        return CGFloat(max(0, hours)) * hourHeight + 8
    }

    private func blockHeight(_ item: KaiCalendarItem) -> CGFloat {
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: selectedDay)) ?? item.end
        let minutes = min(item.end, dayEnd).timeIntervalSince(max(item.start, calendar.startOfDay(for: selectedDay))) / 60
        return CGFloat(minutes) / 60 * hourHeight - 2
    }

    private func nowLine(firstHour: Int, lastHour: Int, width: CGFloat) -> some View {
        let y = offset(of: Date(), firstHour: firstHour)
        return Group {
            if y > 8 && y < CGFloat(lastHour - firstHour) * hourHeight + 8 {
                HStack(spacing: 0) {
                    Circle().fill(KaiColor.magenta).frame(width: 8, height: 8)
                    Rectangle().fill(KaiColor.magenta).frame(height: 1.5)
                }
                .padding(.leading, 48).offset(y: y - 4)
            }
        }
    }

    private struct Placed { let item: KaiCalendarItem; let column: Int; let columns: Int }

    /// Events that overlap sit side by side. Each group of overlapping events shares one set of columns.
    private func layout(_ events: [KaiCalendarItem]) -> [Placed] {
        var result: [Placed] = []
        var group: [(KaiCalendarItem, Int)] = []
        var groupEnd = Date.distantPast
        func flush() {
            let columns = (group.map(\.1).max() ?? 0) + 1
            result += group.map { Placed(item: $0.0, column: $0.1, columns: columns) }
            group = []
        }
        for event in events.sorted(by: { $0.start < $1.start }) {
            if event.start >= groupEnd { flush() }
            var column = 0
            while group.contains(where: { $0.1 == column && $0.0.end > event.start }) { column += 1 }
            group.append((event, column))
            groupEnd = max(groupEnd, event.end)
        }
        flush()
        return result
    }

    private func eventBlock(_ event: KaiCalendarItem, firstHour: Int) -> some View {
        let tint = color(event)
        let isSelected = event.id == selectedID
        return Button { selectedID = event.id } label: {
            HStack(spacing: 0) {
                Rectangle().fill(tint).frame(width: 4)
                VStack(alignment: .leading, spacing: 1) {
                    Text(event.title).font(.system(size: 12, weight: .semibold)).lineLimit(2)
                        .strikethrough(event.isCancelled)
                    if blockHeight(event) > 40 {
                        Text(timeRange(event)).font(.system(size: 10)).foregroundStyle(.white.opacity(0.7))
                    }
                    if blockHeight(event) > 62, !event.location.isEmpty {
                        Text(event.location).font(.system(size: 10)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                    }
                }
                .padding(.horizontal, 7).padding(.vertical, 4)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 8).fill(tint.opacity(isSelected ? 0.45 : 0.25)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isSelected ? Color.white.opacity(0.8) : tint.opacity(0.4), lineWidth: isSelected ? 1.4 : 0.8))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .opacity(event.isCancelled ? 0.5 : 1)
        }
        .buttonStyle(.plain)
    }

    // MARK: Upcoming

    private var upcomingList: some View {
        let days = (0..<15).compactMap { calendar.date(byAdding: .day, value: $0, to: selectedDay) }
        let groups = days.map { ($0, events(on: $0)) }.filter { !$0.1.isEmpty }
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                if groups.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "calendar").font(.system(size: 30)).foregroundStyle(.secondary)
                        Text("Nothing scheduled for the next two weeks").font(.headline)
                    }
                    .frame(maxWidth: .infinity).padding(.top, 60)
                }
                ForEach(groups, id: \.0) { day, list in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text(dayTitle(day)).font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(calendar.isDateInToday(day) ? KaiColor.cyan : .white)
                            Text("\(list.count) \(list.count == 1 ? "event" : "events")").font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(list) { event in upcomingRow(event) }
                    }
                }
            }
            .padding(16)
        }
        .kaiLiquidGlass(KaiColor.cyan, radius: 18, glow: 0.08)
    }

    private func dayTitle(_ day: Date) -> String {
        let prefix = calendar.isDateInToday(day) ? "Today · " : calendar.isDateInTomorrow(day) ? "Tomorrow · " : ""
        return prefix + day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    private func upcomingRow(_ event: KaiCalendarItem) -> some View {
        let isSelected = event.id == selectedID
        return Button { selectedID = event.id } label: {
            HStack(spacing: 12) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(event.isAllDay ? "All day" : event.start.formatted(date: .omitted, time: .shortened)).font(.system(size: 12, weight: .medium))
                    if !event.isAllDay { Text(durationText(event)).font(.system(size: 10)).foregroundStyle(.secondary) }
                }
                .frame(width: 74, alignment: .trailing)
                RoundedRectangle(cornerRadius: 2).fill(color(event)).frame(width: 4, height: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(event.title).fontWeight(.medium).lineLimit(2).strikethrough(event.isCancelled)
                    HStack(spacing: 10) {
                        if !event.location.isEmpty { Label(event.location, systemImage: "mappin").lineLimit(1) }
                        if event.joinLink != nil { Label("Video call", systemImage: "video") }
                        if event.attendees.count > 1 { Label("\(event.attendees.count)", systemImage: "person.2") }
                    }
                    .font(.caption).foregroundStyle(.secondary).labelStyle(.titleAndIcon)
                }
                Spacer(minLength: 0)
                if let when = relative(event) {
                    Text(when).font(.caption2.weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(KaiColor.magenta.opacity(0.2))).foregroundStyle(KaiColor.magenta)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(isSelected ? 0.12 : 0.05)))
            .opacity(event.isCancelled ? 0.5 : 1)
        }
        .buttonStyle(.plain)
    }

    /// "now" or "in 25 min", only for what is happening or about to.
    private func relative(_ event: KaiCalendarItem) -> String? {
        let now = Date()
        if event.isAllDay || event.isCancelled { return nil }
        if event.start <= now && event.end > now { return "Now" }
        let minutes = Int(event.start.timeIntervalSince(now) / 60)
        if minutes > 0 && minutes <= 90 { return "in \(minutes) min" }
        return nil
    }

    // MARK: Details

    private func timeRange(_ event: KaiCalendarItem) -> String {
        if event.isAllDay { return "All day" }
        return event.start.formatted(date: .omitted, time: .shortened) + " – " + event.end.formatted(date: .omitted, time: .shortened)
    }

    private func durationText(_ event: KaiCalendarItem) -> String {
        let minutes = Int(event.end.timeIntervalSince(event.start) / 60)
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }

    private func details(_ event: KaiCalendarItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(event.title).font(.system(size: 20, weight: .semibold)).strikethrough(event.isCancelled)
                        HStack(spacing: 6) {
                            Circle().fill(color(event)).frame(width: 8, height: 8)
                            Text(event.calendarName).font(.caption).foregroundStyle(.secondary)
                            if event.isRecurring { badge("Repeats", "repeat") }
                            if event.isTentative { badge("Tentative", "questionmark.circle") }
                            if event.isCancelled { badge("Cancelled", "xmark.circle") }
                        }
                    }
                    Spacer()
                    Button { selectedID = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                }

                fact("clock", event.start.formatted(.dateTime.weekday(.wide).month(.wide).day()) +
                     (event.isAllDay ? "\nAll day" : "\n\(timeRange(event)) · \(durationText(event))"))

                if let link = event.joinLink {
                    Button { NSWorkspace.shared.open(link) } label: {
                        Label("Join the call", systemImage: "video.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(KaiColor.liquidBlue).controlSize(.large)
                    Text(link.host ?? "").font(.caption).foregroundStyle(.secondary)
                }

                if !event.location.isEmpty {
                    HStack(alignment: .top) {
                        fact("mappin.and.ellipse", event.location)
                        Spacer()
                        if let url = mapsURL(event.location) { Button("Maps") { NSWorkspace.shared.open(url) }.controlSize(.small) }
                    }
                }

                if !event.attendees.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(event.attendees.count) \(event.attendees.count == 1 ? "person" : "people")").font(.caption).foregroundStyle(.secondary)
                        ForEach(Array(event.attendees.enumerated()), id: \.offset) { _, person in
                            HStack(spacing: 8) {
                                Image(systemName: icon(person.response)).foregroundStyle(tint(person.response)).font(.system(size: 13))
                                Text(person.isMe ? "\(person.name) (you)" : person.name).font(.callout).lineLimit(1)
                                if person.isOrganizer { Text("Organizer").font(.caption2).foregroundStyle(.secondary) }
                                Spacer()
                            }
                        }
                    }
                }

                if let reminder = event.reminderMinutes, reminder >= 0 {
                    fact("bell", reminder == 0 ? "Reminder at the start" : "Reminder \(reminder) min before")
                }
                if let url = event.url, event.joinLink == nil, url.scheme == "https" || url.scheme == "http" {
                    Button { NSWorkspace.shared.open(url) } label: { Label(url.host ?? "Open link", systemImage: "link").lineLimit(1) }
                        .buttonStyle(.plain).foregroundStyle(KaiColor.cyan)
                }
                if !event.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Notes").font(.caption).foregroundStyle(.secondary)
                        Text(event.notes).font(.callout).lineSpacing(3).textSelection(.enabled)
                    }
                }

                Divider().overlay(Color.white.opacity(0.1))
                HStack {
                    Button { askKai(event) } label: { Label("Ask Kai to prepare", systemImage: "sparkles") }
                        .controlSize(.small)
                    Button { NSWorkspace.shared.launchApplication("Calendar") } label: { Label("Open in Calendar", systemImage: "calendar") }
                        .controlSize(.small)
                    Spacer()
                    Button { copy(event) } label: { Image(systemName: "doc.on.doc") }.buttonStyle(.plain).help("Copy the details")
                }
            }
            .padding(18)
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .kaiLiquidGlass(color(event), radius: 18, glow: 0.12)
    }

    private func fact(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).frame(width: 18).foregroundStyle(.secondary)
            Text(text).font(.callout).textSelection(.enabled)
        }
    }

    private func badge(_ text: String, _ symbol: String) -> some View {
        Label(text, systemImage: symbol).font(.system(size: 10, weight: .medium)).labelStyle(.titleAndIcon)
            .padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().fill(Color.white.opacity(0.1)))
    }

    private func icon(_ response: KaiCalendarAttendee.Response) -> String {
        switch response {
        case .accepted: return "checkmark.circle.fill"
        case .declined: return "xmark.circle.fill"
        case .maybe: return "questionmark.circle.fill"
        case .noReply: return "circle.dotted"
        }
    }

    private func tint(_ response: KaiCalendarAttendee.Response) -> Color {
        switch response {
        case .accepted: return KaiColor.success
        case .declined: return KaiColor.error
        case .maybe: return KaiColor.warning
        case .noReply: return .secondary
        }
    }

    private func mapsURL(_ place: String) -> URL? {
        var parts = URLComponents(string: "https://maps.apple.com/")
        parts?.queryItems = [URLQueryItem(name: "q", value: place)]
        return parts?.url
    }

    private func copy(_ event: KaiCalendarItem) {
        var lines = [event.title, event.start.formatted(.dateTime.weekday(.wide).month(.wide).day()) + (event.isAllDay ? ", all day" : ", " + timeRange(event))]
        if !event.location.isEmpty { lines.append(event.location) }
        if let link = event.joinLink { lines.append(link.absoluteString) }
        if !event.attendees.isEmpty { lines.append("With: " + event.attendees.map(\.name).joined(separator: ", ")) }
        if !event.notes.isEmpty { lines.append("\n" + event.notes) }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }

    /// Opens a chat about this event. Only the title, time, place and names go in: the model can read the rest from the calendar itself.
    private func askKai(_ event: KaiCalendarItem) {
        let people = event.attendees.filter { !$0.isMe }.prefix(8).map(\.name).joined(separator: ", ")
        let when = event.start.formatted(date: .complete, time: event.isAllDay ? .omitted : .shortened)
        let text = "Help me prepare for my event \"\(event.title)\" on \(when)" + (people.isEmpty ? "" : " with \(people)")
            + ". Check my notes and mail for anything relevant, then give me the points I should have ready."
        appState.activeSidebar = "Chat"
        appState.sendMessage(text: text)
    }
}

#if DEBUG
extension KaiCalendarView {
    /// Made-up events for the snapshot harness, so the page can be seen without reading anyone's calendar.
    static func sampleEvents() -> [KaiCalendarItem] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: calendar.date(byAdding: .day, value: day, to: today)!)!
        }
        let work = KaiCalendarColor(red: 0.23, green: 0.52, blue: 1.0), personal = KaiCalendarColor(red: 1.0, green: 0.38, blue: 0.35)
        let people = [KaiCalendarAttendee(name: "Jose Gonzalez", response: .accepted, isOrganizer: false, isMe: true),
                      KaiCalendarAttendee(name: "Ana Torres", response: .accepted, isOrganizer: true, isMe: false),
                      KaiCalendarAttendee(name: "Sam Lee", response: .maybe, isOrganizer: false, isMe: false),
                      KaiCalendarAttendee(name: "Priya Shah", response: .noReply, isOrganizer: false, isMe: false)]
        return [
            KaiCalendarItem(id: "1", title: "Team standup", start: at(0, 9), end: at(0, 9, 30), isAllDay: false, location: "", calendarName: "Work", calendarColor: work, isRecurring: true),
            KaiCalendarItem(id: "2", title: "Contract review with Ana", start: at(0, 10), end: at(0, 11), isAllDay: false, location: "Room 4B", calendarName: "Work", calendarColor: work),
            KaiCalendarItem(id: "3", title: "Kai OS 1.2 planning", start: at(0, 10, 30), end: at(0, 12), isAllDay: false, location: "Zoom", calendarName: "Work", calendarColor: work,
                            notes: "Agenda:\n- Night Shift portrait\n- Calendar page\n- Release notes\n\nBring the draft roadmap.",
                            joinLink: URL(string: "https://zoom.us/j/123456789"), attendees: people, reminderMinutes: 10),
            KaiCalendarItem(id: "4", title: "Lunch with Sam", start: at(0, 12, 30), end: at(0, 13, 30), isAllDay: false, location: "Cafe Luna", calendarName: "Personal", calendarColor: personal),
            KaiCalendarItem(id: "5", title: "Dentist", start: at(0, 15), end: at(0, 16), isAllDay: false, location: "Main St Dental", calendarName: "Personal", calendarColor: personal),
            KaiCalendarItem(id: "6", title: "Austin trip", start: at(0, 0), end: at(1, 0), isAllDay: true, location: "", calendarName: "Personal", calendarColor: personal),
            KaiCalendarItem(id: "7", title: "Quarterly review", start: at(1, 14), end: at(1, 15, 30), isAllDay: false, location: "", calendarName: "Work", calendarColor: work, joinLink: URL(string: "https://teams.microsoft.com/l/x")),
            KaiCalendarItem(id: "8", title: "Pay rent", start: at(3, 9), end: at(3, 9, 15), isAllDay: false, location: "", calendarName: "Personal", calendarColor: personal),
        ]
    }
}
#endif
