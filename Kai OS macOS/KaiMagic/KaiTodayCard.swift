//
//  KaiTodayCard.swift
//  Kai OS macOS
//
//  Today from the notch: the whole day as it is (every event, reminder, unread mail and Slack message waiting for
//  you), read now on this Mac, and under it what Kai suggests from the morning list. Each suggestion can be
//  dismissed, or opened in For You, where replies and calendar items are approved and acted on. Nothing is
//  sent or changed from this card.
//

import AppKit
import KaiActions
import KaiLocalData
import KaiShared
import KaiSlack
import SwiftUI

@MainActor
final class KaiTodayController {
    static let shared = KaiTodayController()
    private var panel: KaiResultPanel?

    func show(appState: AppState) {
        if panel == nil {
            let panel = KaiResultPanel(contentRect: NSRect(x: 0, y: 0, width: 600, height: 680),
                                       styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isFloatingPanel = true
            panel.level = .screenSaver
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            panel.onCancel = { [weak self] in self?.close() }
            self.panel = panel
        }
        guard let panel else { return }
        panel.contentView = NSHostingView(rootView: KaiTodayCard(cards: appState.morningCards, appState: appState, close: { [weak self] in self?.close() }))
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let frame = screen?.frame {
            let width = min(600, frame.width - 80), height = min(680, frame.height - 120)
            panel.setFrame(NSRect(x: frame.midX - width / 2, y: frame.midY - height / 2 + 40, width: width, height: height), display: true)
        }
        KaiNotchWindowController.shared.collapse()
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    func close() { panel?.orderOut(nil) }
}

/// Everything the card lists, read when it opens. Each source loads on its own, so a slow mailbox or a Slack error
/// never holds back the calendar, and each one says plainly when it couldn't be read.
@MainActor
final class KaiTodayModel: ObservableObject {
    enum Part: Hashable { case calendar, reminders, mail, slack }

    @Published var schedule = KaiToday.Schedule()
    @Published var reminders: [KaiTodayReminder] = []
    @Published var remindersAccess = KaiRemindersSource.access
    @Published var mail: [KaiBriefingMail] = []
    @Published var slack: [KaiSlackSearchHit] = []
    @Published var loading: Set<Part> = []
    @Published var problems: [Part: String] = [:]
    @Published var loadedAt: Date?

    static let mailWindowDays = 3
    static let mailFetchLimit = 40

    func load(appState: AppState) {
        loadedAt = Date()
        problems = [:]
        remindersAccess = KaiRemindersSource.access
        Task { await loadCalendar(appState) }
        Task { await loadReminders() }
        Task { await loadMail(appState) }
        Task { await loadSlack(appState) }
    }

    func allowReminders(appState: AppState) {
        Task {
            _ = try? await KaiRemindersSource.requestAccess()
            remindersAccess = KaiRemindersSource.access
            await loadReminders()
        }
    }

    private func loadCalendar(_ appState: AppState) async {
        guard appState.calendarConnected else { schedule = KaiToday.Schedule(); return }
        loading.insert(.calendar); defer { loading.remove(.calendar) }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: 2, to: start) ?? start
        schedule = KaiToday.schedule(events: KaiCalendarSource.events(from: start, to: end))
    }

    private func loadReminders() async {
        guard remindersAccess == .granted else { reminders = []; return }
        loading.insert(.reminders); defer { loading.remove(.reminders) }
        reminders = await KaiRemindersSource.dueByEndOfToday()
    }

    private func loadMail(_ appState: AppState) async {
        guard appState.mailConnected else { mail = []; return }
        loading.insert(.mail); defer { loading.remove(.mail) }
        do {
            let since = Calendar.current.date(byAdding: .day, value: -Self.mailWindowDays, to: Date()) ?? Date()
            let muted = KaiMailMuteStore.muted()
            let found = try await KaiMailBriefing.unreadMessages(since: since, limit: Self.mailFetchLimit)
            mail = KaiToday.ranked(mail: found.filter { !KaiMailMuteStore.isMuted(sender: $0.sender, in: muted) })
        } catch {
            problems[.mail] = error.localizedDescription
        }
    }

    private func loadSlack(_ appState: AppState) async {
        guard let client = appState.slackClient else { slack = []; return }
        loading.insert(.slack); defer { loading.remove(.slack) }
        do {
            let me = try await client.identity()
            let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
            let day = yesterday.formatted(.iso8601.year().month().day())
            // Messages sent to you, and messages that mention you. Your own are left out.
            async let direct = client.search("to:me after:\(day)", count: 15)
            async let mentions = client.search("@\(me.user) after:\(day)", count: 15)
            var seen = Set<String>()
            let merged = (try await direct + (try await mentions)).filter { $0.username != me.user && seen.insert($0.ts + $0.channelName).inserted }
            slack = merged.sorted { $0.ts > $1.ts }
        } catch {
            problems[.slack] = error.localizedDescription
        }
    }
}

struct KaiTodayCard: View {
    @ObservedObject var cards: KaiMorningCardsController
    let appState: AppState
    let close: () -> Void
    @StateObject private var today = KaiTodayModel()

    private var isLoading: Bool { !today.loading.isEmpty || cards.isGenerating }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Today").font(.system(size: 19, weight: .semibold))
                    Text(Date().formatted(.dateTime.weekday(.wide).month(.wide).day())).font(.caption).foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                if isLoading { ProgressView().controlSize(.small) }
                Button { today.load(appState: appState) } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).help("Read everything again").disabled(!today.loading.isEmpty)
                Button(action: close) { Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)) }.buttonStyle(.plain).help("Close")
            }
            .padding(.horizontal, 24).padding(.vertical, 18)
            Divider().overlay(Color.white.opacity(0.1))
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    scheduleSection
                    remindersSection
                    mailSection
                    slackSection
                    suggestionsSection
                }
                .padding(22)
            }
            Divider().overlay(Color.white.opacity(0.08))
            HStack {
                Button {
                    appState.activeSidebar = "ForYou"
                    KaiNotchWindowController.shared.openMainWindow()
                    close()
                } label: {
                    Label("Open For You to act on these", systemImage: "arrow.up.forward.app").font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 12).padding(.vertical, 6).background(Capsule().fill(KaiColor.liquidBlue))
                }
                .buttonStyle(.plain)
                Spacer()
                Text("Read now on this Mac. Nothing is sent from here.").font(.caption2).foregroundStyle(.white.opacity(0.5))
            }
            .padding(.horizontal, 22).padding(.vertical, 12)
        }
        .foregroundStyle(.white)
        .background(RoundedRectangle(cornerRadius: 22).fill(Color.black))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .environment(\.colorScheme, .dark)
        .onAppear { today.load(appState: appState) }
    }

    // MARK: Sections

    @ViewBuilder private func section<Content: View>(_ title: String, symbol: String, count: Int?, loading: Bool, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                Text(title).font(.system(size: 13, weight: .semibold))
                if let count, count > 0 { Text("\(count)").font(.caption).foregroundStyle(.white.opacity(0.55)) }
                if loading { ProgressView().controlSize(.mini) }
            }
            content()
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.callout).foregroundStyle(.white.opacity(0.55)).fixedSize(horizontal: false, vertical: true)
    }

    private func row(_ title: String, detail: String? = nil, trailing: String? = nil, tint: Color? = nil, dimmed: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let tint { Circle().fill(tint).frame(width: 7, height: 7).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 } }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).lineLimit(2).fontWeight(.medium)
                if let detail, !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.white.opacity(0.6)).lineLimit(2) }
            }
            Spacer(minLength: 8)
            if let trailing { Text(trailing).font(.caption).foregroundStyle(.white.opacity(0.6)).multilineTextAlignment(.trailing) }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
        .opacity(dimmed ? 0.5 : 1)
    }

    private var scheduleSection: some View {
        let s = today.schedule
        let today_ = s.allDay + s.happeningNow + s.upcoming
        return section("Schedule", symbol: "calendar", count: today_.count, loading: today.loading.contains(.calendar)) {
            if !appState.calendarConnected {
                note("Connect Calendar in Kai OS settings to see your meetings here.")
            } else if s.isEmpty {
                note("No meetings today or tomorrow.")
            } else {
                ForEach(s.allDay) { row($0.title, detail: $0.location, trailing: "All day") }
                ForEach(s.happeningNow) { event in
                    HStack(spacing: 8) {
                        row(event.title, detail: event.location, trailing: "Now · until \(event.end.formatted(.dateTime.hour().minute()))", tint: .green)
                        if let link = event.joinLink { Button("Join") { NSWorkspace.shared.open(link) }.controlSize(.small) }
                    }
                }
                ForEach(s.upcoming) { event in
                    HStack(spacing: 8) {
                        row(event.title, detail: event.location, trailing: KaiToday.timeRange(event))
                        if let link = event.joinLink { Button("Join") { NSWorkspace.shared.open(link) }.controlSize(.small) }
                    }
                }
                if today_.isEmpty { note("Nothing else on your calendar today.") }
                if !s.finished.isEmpty { note("\(s.finished.count) earlier today: " + s.finished.prefix(3).map(\.title).joined(separator: ", ") + (s.finished.count > 3 ? "…" : "")) }
                if !s.tomorrow.isEmpty {
                    Text("Tomorrow").font(.caption).foregroundStyle(.white.opacity(0.55)).padding(.top, 4)
                    ForEach(s.tomorrow.prefix(5)) { row($0.title, detail: $0.location, trailing: KaiToday.timeRange($0), dimmed: true) }
                    if s.tomorrow.count > 5 { note("and \(s.tomorrow.count - 5) more tomorrow") }
                }
            }
        }
    }

    private var remindersSection: some View {
        section("Reminders", symbol: "checklist", count: today.reminders.count, loading: today.loading.contains(.reminders)) {
            switch today.remindersAccess {
            case .notRequested:
                note("Kai can list reminders that are due or overdue. It reads them on this Mac only.")
                Button("Allow Reminders") { today.allowReminders(appState: appState) }.controlSize(.small)
            case .denied:
                note("Reminders access is off for Kai OS. Turn it on in System Settings → Privacy & Security → Reminders.")
            default:
                if today.reminders.isEmpty { note("Nothing due today, and nothing overdue.") }
                ForEach(today.reminders.prefix(12)) { reminder in
                    row(reminder.title, detail: reminder.list,
                        trailing: reminder.isOverdue ? "Overdue" : reminder.due.map { $0.formatted(.dateTime.hour().minute()) },
                        tint: reminder.isOverdue ? .red : (reminder.priority != 0 && reminder.priority <= 4 ? .orange : nil))
                }
                if today.reminders.count > 12 { note("and \(today.reminders.count - 12) more") }
            }
        }
    }

    private var mailSection: some View {
        section("Mail", symbol: "envelope", count: today.mail.count, loading: today.loading.contains(.mail)) {
            if !appState.mailConnected {
                note("Connect Mail in Kai OS settings to see what is waiting.")
            } else if let problem = today.problems[.mail] {
                note("Kai couldn't read Mail: \(problem)")
            } else if today.mail.isEmpty, !today.loading.contains(.mail) {
                note("No unread mail from the last \(KaiTodayModel.mailWindowDays) days.")
            } else {
                let more = today.mail.count >= KaiTodayModel.mailFetchLimit
                note("Unread from the last \(KaiTodayModel.mailWindowDays) days: \(today.mail.count)\(more ? " or more" : "").")
                ForEach(Array(today.mail.prefix(8).enumerated()), id: \.offset) { _, message in
                    row(message.subject.isEmpty ? "(no subject)" : message.subject, detail: message.sender,
                        trailing: message.date.formatted(.relative(presentation: .named)), tint: message.isFlagged ? .orange : nil)
                }
                if today.mail.count > 8 { note("and \(today.mail.count - 8) more in Mail") }
            }
        }
    }

    @ViewBuilder private var slackSection: some View {
        if appState.slackClient != nil {
            section("Slack", symbol: "number", count: today.slack.count, loading: today.loading.contains(.slack)) {
                if let problem = today.problems[.slack] {
                    note("Kai couldn't search Slack: \(problem)")
                } else if today.slack.isEmpty, !today.loading.contains(.slack) {
                    note("No new messages to you or mentioning you since yesterday.")
                } else {
                    ForEach(Array(today.slack.prefix(8).enumerated()), id: \.offset) { _, hit in
                        Button {
                            if let url = URL(string: hit.permalink), url.scheme == "https" { NSWorkspace.shared.open(url) }
                        } label: {
                            row(hit.text.replacingOccurrences(of: "\n", with: " "), detail: "\(hit.username) · \(hit.channelName.isEmpty ? "direct message" : "#" + hit.channelName)")
                        }
                        .buttonStyle(.plain)
                    }
                    if today.slack.count > 8 { note("and \(today.slack.count - 8) more") }
                }
            }
        }
    }

    private var suggestionsSection: some View {
        let items = cards.activeCards
        return section("Kai suggests", symbol: "sparkles", count: items.count, loading: cards.isGenerating) {
            if items.isEmpty {
                note(cards.hasSources ? "No suggestions yet today. Night Shift makes this list, or press refresh below." : "Turn on Calendar, Mail or Slack under Night Shift, and Kai suggests what to do first.")
                if cards.hasSources { Button("Make suggestions now") { cards.generate() }.controlSize(.small).disabled(cards.isGenerating) }
            }
            ForEach(items) { card in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        if let urgency = card.urgency { UrgencyPill(urgency: urgency) }
                        Text(card.title).fontWeight(.semibold).lineLimit(2)
                        Spacer(minLength: 6)
                        Button("Dismiss") { cards.dismiss(card.id) }.buttonStyle(.plain).font(.caption).foregroundStyle(.white.opacity(0.55))
                    }
                    if !card.why.isEmpty { Text(card.why).font(.callout).foregroundStyle(.white.opacity(0.7)).lineLimit(3) }
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.07)))
            }
        }
    }
}
