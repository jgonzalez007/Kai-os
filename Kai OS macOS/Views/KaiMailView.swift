//
//  KaiMailView.swift
//  Kai OS macOS
//
//  The mail page: views on the left (all, unread, looks like it needs you, flagged, today), the messages
//  grouped by day in the middle, and the message on the right when you click it. The body is read from
//  Apple Mail only when you open a message, kept in memory, and never indexed. Kai can summarize it
//  here with the model on this Mac, and open a reply in Mail for you to look over. It never sends.
//

import AppKit
import KaiActions
import KaiLocalAI
import KaiLocalData
import KaiKnowledge
import KaiShared
import SwiftUI

struct KaiMailView: View {
    @EnvironmentObject var appState: AppState

    private enum Smart: String, CaseIterable, Identifiable {
        case all = "All", unread = "Unread", needsYou = "Needs you", flagged = "Flagged", today = "Today", cleanUp = "Clean up"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .all: return "tray"
            case .unread: return "circle.fill"
            case .needsYou: return "exclamationmark.bubble"
            case .flagged: return "flag"
            case .today: return "sun.max"
            case .cleanUp: return "wand.and.stars"
            }
        }
    }

    private enum BodyState: Equatable {
        case idle, loading, loaded(KaiEmailDraftSource), failed(String)
    }

    private enum Assist: Equatable {
        case none, working(String), summary(String), draft(String), failed(String)
    }

    @State private var view = Smart.all
    @State private var selectedID: String?
    @State private var bodyState = BodyState.idle
    @State private var assist = Assist.none
    @State private var readTask: Task<Void, Never>?
    @State private var assistTask: Task<Void, Never>?
    @State private var replyNote: String?
    /// Where the open message lives, as Mail said when it was read. A reply is opened from this.
    @State private var reference: KaiMailMessageReference?
    // Clean up
    @State private var mutedSet = KaiMailMuteStore.muted()
    @State private var cleanKey: String?
    @State private var pending: KaiMailCleanupPlan?
    @State private var cleanBusy = false
    @State private var cleanNote: String?
    /// What would reverse the last change, offered as an Undo button until the person does something else.
    @State private var undoPlan: KaiMailCleanupPlan?
    @State private var folders: [String]?
    /// With "Always move to…": also move the messages already here, in the same go.
    @State private var alsoMoveExisting = true

    private let calendar = Calendar.current

    #if DEBUG
    /// Set by the snapshot harness, to draw the Clean up view.
    static var startInCleanUp = false
    #endif

    // MARK: Data

    private var messages: [MailMessage] { appState.mailMessages }
    private var selected: MailMessage? { messages.first { $0.id == selectedID } }

    private func needsYou(_ message: MailMessage) -> Bool {
        !KaiMailMuteStore.isMuted(sender: message.sender, in: mutedSet)
            && KaiMailDisplay.looksLikeItNeedsYou(sender: message.sender, subject: message.subject, isRead: message.isRead, isFlagged: message.starred)
    }

    private func matches(_ message: MailMessage, _ smart: Smart) -> Bool {
        switch smart {
        case .all: return true
        case .unread: return !message.isRead
        case .needsYou: return needsYou(message)
        case .flagged: return message.starred
        case .today: return calendar.isDateInToday(message.date)
        case .cleanUp: return true
        }
    }

    private func count(_ smart: Smart) -> Int {
        smart == .cleanUp ? groups.filter { !$0.isMuted && $0.unread > 0 }.count : messages.filter { matches($0, smart) }.count
    }

    private var visible: [MailMessage] {
        let query = appState.mailQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return messages.filter { message in
            matches(message, view) && (query.isEmpty || message.subject.localizedCaseInsensitiveContains(query)
                                       || message.sender.localizedCaseInsensitiveContains(query))
        }
    }

    private var groups: [KaiMailGroup] {
        let inputs = messages.map { KaiMailCleanupInput(id: $0.id, position: $0.position, sender: $0.sender, subject: $0.subject, date: $0.date, isRead: $0.isRead, isFlagged: $0.starred) }
        return KaiMailCleanup.groups(from: inputs, muted: mutedSet)
    }

    private var selectedGroup: KaiMailGroup? { groups.first { $0.id == cleanKey } }

    private var grouped: [(day: Date, list: [MailMessage])] {
        Dictionary(grouping: visible) { calendar.startOfDay(for: $0.date) }
            .map { (day: $0.key, list: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.day > $1.day }
    }

    // MARK: Body

    var bodyView: some View {
        VStack(spacing: 14) {
            header
            KaiSourceErrorBanner(state: appState.mailState)
            HStack(alignment: .top, spacing: 16) {
                sidebar.frame(width: 210)
                list.frame(width: 390)
                reader.frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 28).padding(.bottom, 24)
    }

    var body: some View {
        Group {
            if appState.mailConnected {
                bodyView
            } else {
                KaiConnectCard(
                    title: "Mail",
                    icon: "envelope",
                    explanation: "Kai OS reads your Apple Mail inbox: who a message is from, the subject and the date, and the message itself only when you open it. It never sends or deletes anything, and nothing leaves this Mac.",
                    state: appState.mailState,
                    connect: appState.connectMail
                )
            }
        }
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.environment["KAI_PAGE_SNAPSHOT_DIR"] != nil {
                if Self.startInCleanUp { view = .cleanUp; cleanKey = groups.first?.id; folders = ["Archive", "Noise", "Projects"]; return }
                selectedID = messages.dropFirst(1).first?.id
                bodyState = .loaded(Self.sampleBody)
                assist = .summary(Self.sampleSummary)
                return
            }
            #endif
            if appState.mailConnected { appState.refreshMail() }
        }
        .onDisappear { readTask?.cancel(); assistTask?.cancel() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Mail").font(.system(size: 26, weight: .semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search mail", text: $appState.mailQuery).textFieldStyle(.plain)
                if !appState.mailQuery.isEmpty {
                    Button { appState.mailQuery = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 7).frame(width: 260)
            .background(Capsule().fill(Color.white.opacity(0.07)))
            if appState.mailState == .loading { ProgressView().controlSize(.small) }
            if let when = appState.mailUpdatedAt {
                Text(appState.mailShowingCache ? "From \(when.formatted(date: .omitted, time: .shortened)), updating…" : "Updated \(when.formatted(.relative(presentation: .named)))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Button { appState.refreshMail() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.plain).help("Read the inbox again")
        }
        .padding(.top, 4)
    }

    private var subtitle: String {
        let unread = messages.filter { !$0.isRead }.count
        return "\(messages.count) recent messages · \(unread) unread"
    }

    // MARK: Views

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Inbox").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 10).padding(.bottom, 4)
            ForEach(Smart.allCases) { smart in
                Button { view = smart } label: {
                    HStack(spacing: 10) {
                        Image(systemName: smart.symbol).frame(width: 18)
                            .foregroundStyle(smart == .needsYou ? KaiColor.magenta : smart == .unread ? KaiColor.cyan : .secondary)
                            .font(.system(size: smart == .unread ? 8 : 13))
                        Text(smart.rawValue)
                        Spacer()
                        let n = count(smart)
                        if n > 0 && smart != .all { Text("\(n)").font(.caption).foregroundStyle(.secondary) }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(view == smart ? Color.white.opacity(0.12) : .clear))
                }
                .buttonStyle(.plain)
            }
            if view == .cleanUp {
                Text("Mail grouped by sender. Mark a whole group read, move it to a folder, make a rule in Mail for what comes next, or mute the sender in Kai. Flagged messages are never touched.")
                    .font(.caption2).foregroundStyle(.secondary).padding(10)
            }
            if view == .needsYou {
                Text("A guess from the sender and the subject: unread messages from a person that ask for something, and anything you flagged.")
                    .font(.caption2).foregroundStyle(.secondary).padding(10)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxHeight: .infinity, alignment: .top)
        .kaiLiquidGlass(KaiColor.violet, radius: 18, glow: 0.06)
    }

    // MARK: List

    private var list: some View {
        Group { if view == .cleanUp { cleanupList } else { messageList } }
    }

    private var messageList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4, pinnedViews: []) {
                if visible.isEmpty && messages.isEmpty && appState.mailState == .loading {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("Reading your inbox…").font(.headline)
                        Text("Mail can take up to half a minute with a big inbox.").font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(.top, 60)
                } else if visible.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: view == .all ? "tray" : "checkmark.circle").font(.system(size: 28)).foregroundStyle(.secondary)
                        Text(emptyText).font(.headline)
                    }
                    .frame(maxWidth: .infinity).padding(.top, 60)
                }
                ForEach(grouped, id: \.day) { group in
                    Text(dayTitle(group.day)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        .padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 2)
                    ForEach(group.list) { message in row(message) }
                }
            }
            .padding(10)
        }
        .frame(maxHeight: .infinity)
        .kaiLiquidGlass(KaiColor.cyan, radius: 18, glow: 0.08)
    }

    private var emptyText: String {
        if !appState.mailQuery.isEmpty { return "Nothing matched" }
        switch view {
        case .all: return "No messages"
        case .unread: return "Nothing unread"
        case .needsYou: return "Nothing looks like it needs you"
        case .flagged: return "Nothing flagged"
        case .today: return "No mail today"
        case .cleanUp: return "Nothing to clean up"
        }
    }

    private func dayTitle(_ day: Date) -> String {
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    private func timeLabel(_ date: Date) -> String {
        calendar.isDateInToday(date) ? date.formatted(date: .omitted, time: .shortened) : date.formatted(.dateTime.month(.abbreviated).day())
    }

    private func avatar(_ name: String, size: CGFloat = 34) -> some View {
        let palette: [Color] = [KaiColor.liquidBlue, KaiColor.violet, KaiColor.magenta, KaiColor.cyan, Color(red: 1, green: 0.62, blue: 0.2), Color(red: 0.2, green: 0.8, blue: 0.55)]
        let color = palette[KaiMailDisplay.colorIndex(name, count: palette.count)]
        return Text(KaiMailDisplay.initials(name))
            .font(.system(size: size * 0.38, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(color.opacity(0.55)))
    }

    private func row(_ message: MailMessage) -> some View {
        let isSelected = message.id == selectedID
        return Button { open(message) } label: {
            HStack(alignment: .top, spacing: 10) {
                ZStack(alignment: .topLeading) {
                    avatar(message.from)
                    if !message.isRead { Circle().fill(KaiColor.cyan).frame(width: 9, height: 9).overlay(Circle().stroke(Color.black, lineWidth: 1.5)).offset(x: -2, y: -2) }
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(message.from).fontWeight(message.isRead ? .regular : .semibold).lineLimit(1)
                        Spacer(minLength: 4)
                        if message.starred { Image(systemName: "flag.fill").font(.caption2).foregroundStyle(KaiColor.warning) }
                        Text(timeLabel(message.date)).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(message.subject).font(.callout).lineLimit(2)
                        .foregroundStyle(message.isRead ? Color.white.opacity(0.6) : Color.white.opacity(0.9))
                    if needsYou(message) && view != .needsYou {
                        Text("Looks like it needs you").font(.system(size: 10, weight: .medium)).foregroundStyle(KaiColor.magenta)
                    }
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(isSelected ? Color.white.opacity(0.13) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }


    // MARK: Clean up

    private var cleanupList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                if groups.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle").font(.system(size: 28)).foregroundStyle(.secondary)
                        Text("Nothing to clean up").font(.headline)
                        Text("Groups show up when a sender has two or more recent messages, or sends automated mail.").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity).padding(.top, 60)
                }
                ForEach(groups) { group in groupRow(group) }
            }
            .padding(10)
        }
        .frame(maxHeight: .infinity)
        .kaiLiquidGlass(KaiColor.cyan, radius: 18, glow: 0.08)
    }

    private func groupRow(_ group: KaiMailGroup) -> some View {
        let isSelected = group.id == cleanKey
        return Button { chooseGroup(group) } label: {
            HStack(alignment: .top, spacing: 10) {
                avatar(group.name)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(group.name).fontWeight(.semibold).lineLimit(1)
                        if group.isAutomated { tag("Automated", KaiColor.cyan) }
                        if group.isMuted { tag("Muted", .secondary) }
                        Spacer(minLength: 4)
                        Text("\(group.messages.count)").font(.callout.weight(.semibold))
                    }
                    Text(group.messages.prefix(2).map(\.subject).joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    if group.unread > 0 { Text("\(group.unread) unread").font(.caption2).foregroundStyle(KaiColor.cyan) }
                    if group.suggestion != nil { tag("Suggested", KaiColor.warning) }
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(isSelected ? Color.white.opacity(0.13) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func tag(_ text: String, _ color: Color) -> some View {
        Text(text).font(.system(size: 9, weight: .semibold)).padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.2))).foregroundStyle(color)
    }

    private func chooseGroup(_ group: KaiMailGroup) {
        cleanKey = group.id
        pending = nil
        cleanNote = nil
        undoPlan = nil
        folders = nil
        guard let position = group.messages.first?.position else { return }
        Task {
            let found = try? await KaiMailCleanupRunner.folders(forMessageAt: position)
            guard cleanKey == group.id else { return }
            folders = found ?? []
        }
    }

    @ViewBuilder
    private var cleanupPanel: some View {
        if let group = selectedGroup {
            let unreadItems = group.changeable.filter { !$0.isRead }
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        avatar(group.name, size: 42)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.name).font(.system(size: 20, weight: .semibold))
                            Text(group.key + (group.isAutomated ? " · automated sender" : "")).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { cleanKey = nil; pending = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                    }
                    Text("\(group.messages.count) recent messages, \(group.unread) unread" + (group.messages.count != group.changeable.count ? ", \(group.messages.count - group.changeable.count) flagged (left alone)" : ""))
                        .font(.callout).foregroundStyle(.secondary)
                    FlowButtons {
                        action("Mark \(unreadItems.count) read", "envelope.open") { arm(.markRead, group, items: unreadItems) }
                            .disabled(unreadItems.isEmpty || cleanBusy)
                        Menu {
                            if let folders, !folders.isEmpty {
                                ForEach(folders, id: \.self) { folder in Button(folder) { arm(.move(to: folder), group, items: group.changeable) } }
                            } else {
                                Text(folders == nil ? "Loading folders…" : "No folder to move to")
                            }
                        } label: {
                            Label("Move to…", systemImage: "folder").font(.system(size: 12, weight: .medium))
                                .padding(.horizontal, 12).padding(.vertical, 6).background(Capsule().fill(Color.white.opacity(0.1)))
                        }
                        .menuStyle(.borderlessButton).fixedSize().disabled(group.changeable.isEmpty || cleanBusy)
                        Menu {
                            if let folders, !folders.isEmpty {
                                ForEach(folders, id: \.self) { folder in
                                    Button(folder) { alsoMoveExisting = true; arm(.moveRule(to: folder), group, items: Array(group.messages.prefix(1))) }
                                }
                            } else {
                                Text(folders == nil ? "Loading folders…" : "No folder to move to")
                            }
                        } label: {
                            Label("Always move to…", systemImage: "arrow.triangle.branch").font(.system(size: 12, weight: .medium))
                                .padding(.horizontal, 12).padding(.vertical, 6).background(Capsule().fill(Color.white.opacity(0.1)))
                        }
                        .menuStyle(.borderlessButton).fixedSize().disabled(group.messages.isEmpty || cleanBusy)
                        action("Always mark read", "gearshape") { arm(.rule, group, items: group.messages.prefix(1).map { $0 }) }.disabled(cleanBusy)
                        action(group.isMuted ? "Unmute" : "Mute in Kai", group.isMuted ? "bell" : "bell.slash") { toggleMute(group) }
                    }
                    if let pending { confirmBar(pending, group) }
                    if let cleanNote {
                        HStack(spacing: 8) {
                            Text(cleanNote).font(.callout).foregroundStyle(KaiColor.cyan)
                            if let undoPlan {
                                Button("Undo") { approve(undoPlan) }.controlSize(.small).disabled(cleanBusy)
                                    .help(undoPlan.change)
                            }
                        }
                    }
                    if let hint = group.suggestion, pending == nil {
                        Label(hint, systemImage: "lightbulb").font(.caption).foregroundStyle(KaiColor.warning)
                    }
                }
                .padding(18)
                Divider().overlay(Color.white.opacity(0.1))
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(group.messages, id: \.id) { message in
                            HStack(spacing: 10) {
                                Circle().fill(message.isRead ? Color.clear : KaiColor.cyan).frame(width: 7, height: 7)
                                Text(message.subject).lineLimit(1).foregroundStyle(message.isRead ? Color.white.opacity(0.6) : .white)
                                if message.isFlagged { Image(systemName: "flag.fill").font(.caption2).foregroundStyle(KaiColor.warning) }
                                Spacer()
                                Text(timeLabel(message.date)).font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 18).padding(.vertical, 8)
                            Divider().overlay(Color.white.opacity(0.05))
                        }
                    }
                }
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "wand.and.stars").font(.system(size: 34)).foregroundStyle(KaiColor.cyan)
                Text("Pick a sender to clean up").font(.headline)
                Text("Kai shows exactly which messages a change would touch, and asks you first. It never sends or deletes anything.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 340)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func confirmBar(_ plan: KaiMailCleanupPlan, _ group: KaiMailGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(plan.change + "?").font(.callout.weight(.semibold))
            if plan.operation == .rule {
                Text("From now on Mail marks new mail from \(plan.senderKey) as read, while Mail is open. It shows in Mail → Settings → Rules, and you can switch it off there.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if case .moveRule(let folder) = plan.operation {
                Text("From now on Mail moves new mail from \(plan.senderKey) to “\(folder)” by itself, while Mail is open. The rule stays until you remove it in Mail → Settings → Rules. Nothing is deleted.")
                    .font(.caption).foregroundStyle(.secondary)
                if !group.changeable.isEmpty {
                    Toggle("Also move the \(group.changeable.count) messages already here", isOn: $alsoMoveExisting).toggleStyle(.checkbox).font(.caption)
                }
            } else {
                Text("Only these messages, nothing else. Nothing is deleted.").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("Approve") { approve(plan) }.kaiProminent().tint(KaiColor.liquidBlue).controlSize(.small).disabled(cleanBusy)
                Button("Cancel") { pending = nil }.controlSize(.small)
                if cleanBusy { ProgressView().controlSize(.small); Text("Working in Mail…").font(.caption).foregroundStyle(.secondary) }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(KaiColor.liquidBlue.opacity(0.15)))
    }

    private func arm(_ operation: KaiMailCleanupPlan.Operation, _ group: KaiMailGroup, items: [KaiMailCleanupInput]) {
        cleanNote = nil
        pending = KaiMailCleanupPlan(operation: operation, senderKey: group.key, senderName: group.name,
                                     items: items.map { .init(id: $0.id, position: $0.position, subject: $0.subject) })
    }

    private func toggleMute(_ group: KaiMailGroup) {
        if group.isMuted { KaiMailMuteStore.unmute(group.key) } else { KaiMailMuteStore.mute(group.key) }
        mutedSet = KaiMailMuteStore.muted()
        cleanNote = group.isMuted ? "\(group.name) is no longer muted." : "Muted. \(group.name) won't show under Needs you or in your morning list."
    }

    /// Pressing Approve is the approval. It is written to the action log like any other action.
    private func approve(_ plan: KaiMailCleanupPlan) {
        var card = KaiActionCard(action: .mailCleanup(plan))
        guard card.approve() else { return }
        guard (try? appState.actionLog.record(event: "approved", card: card, detail: "mail page")) != nil else {
            cleanNote = "The action log couldn't be written, so nothing was done."
            return
        }
        cleanBusy = true
        let executor = appState.actionExecutor
        let ids = Set(plan.items.map(\.id))
        Task {
            defer { cleanBusy = false }
            do {
                let detail = try await executor.perform(card.action)
                card.finish(.succeeded(detail))
                try? appState.actionLog.record(event: "succeeded", card: card, detail: detail)
                cleanNote = detail
                pending = nil
                undoPlan = plan.undo
                switch plan.operation {
                case .markUnread: appState.applyMailUnread(ids: ids)
                case .removeRule: break
                case .markRead: appState.applyMailCleanup(ids: ids, moved: false)
                case .move: appState.applyMailCleanup(ids: ids, moved: true)
                case .rule: break
                case .moveRule(let folder):
                    if alsoMoveExisting, let group = selectedGroup, !group.changeable.isEmpty {
                        let existing = KaiMailCleanupPlan(operation: .move(to: folder), senderKey: plan.senderKey, senderName: plan.senderName,
                                                          items: group.changeable.map { .init(id: $0.id, position: $0.position, subject: $0.subject) })
                        var second = KaiActionCard(action: .mailCleanup(existing))
                        if second.approve(), (try? appState.actionLog.record(event: "approved", card: second, detail: "mail page, with the rule")) != nil {
                            let more = try await executor.perform(second.action)
                            second.finish(.succeeded(more))
                            try? appState.actionLog.record(event: "succeeded", card: second, detail: more)
                            cleanNote = detail + " " + more
                            appState.applyMailCleanup(ids: Set(existing.items.map(\.id)), moved: true)
                        }
                    }
                }
            } catch {
                card.finish(.failed(error.localizedDescription))
                try? appState.actionLog.record(event: "failed", card: card, detail: error.localizedDescription)
                cleanNote = error.localizedDescription
            }
        }
    }

    // MARK: Reader

    @ViewBuilder
    private var reader: some View {
        Group {
            if view == .cleanUp {
                cleanupPanel
            } else if let message = selected { readerContent(message) } else {
                VStack(spacing: 10) {
                    KaiLogoMark(size: 44)
                    Text("Choose a message to read it").font(.headline)
                    Text("Kai reads a message from Mail only when you open it, and it stays on this Mac.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 320)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxHeight: .infinity)
        .kaiLiquidGlass(KaiColor.liquidBlue, radius: 18, glow: 0.1)
    }

    private func readerContent(_ message: MailMessage) -> some View {
        let parts = KaiMailDisplay.parseSender(message.sender)
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text(message.subject).font(.system(size: 21, weight: .semibold)).textSelection(.enabled)
                HStack(spacing: 12) {
                    avatar(parts.name, size: 38)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(parts.name).fontWeight(.semibold)
                        if !parts.address.isEmpty && parts.address != parts.name { Text(parts.address).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(message.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())).font(.caption).foregroundStyle(.secondary)
                        if KaiMailDisplay.isAutomated(sender: message.sender) { Text("Automated").font(.caption2).foregroundStyle(.secondary) }
                    }
                    Button { selectedID = nil; bodyState = .idle; assist = .none } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                }
                HStack(spacing: 8) {
                    action("Summarize", "sparkles") { summarize() }
                    action("Draft a reply", "arrowshape.turn.up.left") { draftReply(message) }
                    action("Open in Mail", "envelope") { NSWorkspace.shared.launchApplication("Mail") }
                    Spacer()
                    if case .loaded(let source) = bodyState {
                        Button { copy(source.body) } label: { Image(systemName: "doc.on.doc") }.buttonStyle(.plain).help("Copy the message text")
                    }
                }
            }
            .padding(18)
            Divider().overlay(Color.white.opacity(0.1))
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    assistCard(message)
                    switch bodyState {
                    case .idle, .loading:
                        HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Opening the message…").foregroundStyle(.secondary) }
                    case .failed(let text):
                        Label(text, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange)
                    case .loaded(let source):
                        Text(source.body.isEmpty ? "This message has no text." : String(source.body.prefix(20_000)))
                            .font(.system(size: 14)).lineSpacing(4).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(18)
            }
        }
    }

    private func action(_ title: String, _ symbol: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Label(title, systemImage: symbol).font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 12).padding(.vertical, 6).background(Capsule().fill(Color.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func assistCard(_ message: MailMessage) -> some View {
        switch assist {
        case .none: EmptyView()
        case .working(let label):
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text(label).foregroundStyle(.secondary) }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.06)))
        case .failed(let text):
            Label(text, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange)
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.06)))
        case .summary(let text):
            card(title: "Summary", symbol: "sparkles", tint: KaiColor.cyan, text: text) { EmptyView() }
        case .draft(let text):
            card(title: "Draft reply", symbol: "arrowshape.turn.up.left", tint: KaiColor.magenta, text: text) {
                HStack(spacing: 8) {
                    Button("Copy") { copy(text) }.controlSize(.small)
                    Button("Open reply in Mail") { openReply(message, draft: text) }.controlSize(.small).kaiProminent().tint(KaiColor.liquidBlue)
                    if let replyNote { Text(replyNote).font(.caption).foregroundStyle(.secondary) }
                }
            }
        }
    }

    private func card<Footer: View>(title: String, symbol: String, tint: Color, text: String, @ViewBuilder footer: () -> Footer) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol).font(.caption.weight(.semibold)).foregroundStyle(tint)
            Text(rendered(text)).font(.system(size: 14)).lineSpacing(4).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            footer()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(tint.opacity(0.09)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(tint.opacity(0.3), lineWidth: 0.8))
    }

    private func rendered(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: KaiScreenTask.forDisplay(text), options: options)) ?? AttributedString(text)
    }

    // MARK: Actions

    private func open(_ message: MailMessage) {
        guard selectedID != message.id else { return }
        selectedID = message.id
        bodyState = .loading
        assist = .none
        replyNote = nil
        readTask?.cancel(); assistTask?.cancel()
        reference = nil
        readTask = Task {
            do {
                if let found = try await KaiMailSelection.inboxEmail(id: message.id, position: message.position) {
                    guard !Task.isCancelled, selectedID == message.id else { return }
                    reference = found.reference
                    bodyState = .loaded(found.source)
                } else {
                    bodyState = .failed("Mail returned nothing for this message.")
                }
            } catch {
                guard !Task.isCancelled, selectedID == message.id else { return }
                bodyState = .failed(error.localizedDescription)
            }
        }
    }

    /// Waits for the message to be read, then runs `work` with it. A model on this Mac does the work.
    private func withMessage(_ label: String, _ work: @escaping (KaiEmailDraftSource, String) async throws -> Assist) {
        guard let id = selectedID else { return }
        guard case .loaded(let source) = bodyState else { assist = .failed("Wait for the message to open first."); return }
        guard let model = KaiScreenTask.localModel(selected: appState.selectedModel, available: appState.chatModels) else {
            assist = .failed("This reads your mail with a model on this Mac, so nothing is sent to the cloud. Start Ollama and download a model first (the Health page can help).")
            return
        }
        assist = .working(label)
        assistTask?.cancel()
        assistTask = Task {
            do {
                let result = try await work(source, model)
                guard !Task.isCancelled, selectedID == id else { return }
                assist = result
            } catch is CancellationError {
            } catch {
                guard selectedID == id else { return }
                assist = .failed(error.localizedDescription)
            }
        }
    }

    private func run(_ messages: [KaiOllamaMessage], model: String, temperature: Double) async throws -> String {
        var text = ""
        for try await event in KaiOllamaClient().stream(model: model, messages: messages, tools: [], temperature: temperature) {
            try Task.checkCancellation()
            if case .text(let delta) = event { text += delta }
        }
        return KaiScreenTask.cleaned(text)
    }

    private func summarize() {
        let profile = KaiProfilePrompt.promptSection(appState.profile)
        let preferences = KaiAnswerStyle.promptSection(for: .summaries)
        withMessage("Reading it for you…") { source, model in
            let answer = try await run(KaiMailSummaryPrompt.messages(source: source, profile: profile, preferences: preferences), model: model, temperature: 0.2)
            return answer.isEmpty ? .failed("The model returned nothing. Try again.") : .summary(answer)
        }
    }

    private func draftReply(_ message: MailMessage) {
        replyNote = nil
        withMessage("Writing a reply…") { source, model in
            let answer = try await run(KaiReplyPrompt.messages(source: source, instruction: "", previousDraft: nil, style: KaiAnswerStyle.drafting(base: nil)), model: model, temperature: 0.4)
            let draft = KaiReplyPrompt.removingPlaceholderSignature(answer)
            return draft.isEmpty ? .failed("The model returned nothing. Try again.") : .draft(draft)
        }
    }

    /// Opens a reply in Mail with the draft in it, for the person to read and send themselves. Pressing the
    /// button is the approval, and it is written to the action log like any other action.
    private func openReply(_ message: MailMessage, draft: String) {
        guard case .loaded(let source) = bodyState, let reference else { return }
        var card = KaiActionCard(action: .mailReply(reference: reference, recipient: source.sender, subject: source.subject,
                                                    body: KaiMailReplyBody.compose(draft: draft, source: source)))
        guard card.approve() else { return }
        guard (try? appState.actionLog.record(event: "approved", card: card, detail: "mail page")) != nil else {
            replyNote = "The action log couldn't be written, so nothing was done."
            return
        }
        replyNote = "Opening in Mail…"
        let executor = appState.actionExecutor
        Task {
            do {
                let detail = try await executor.perform(card.action)
                card.finish(.succeeded(detail))
                try? appState.actionLog.record(event: "succeeded", card: card, detail: detail)
                replyNote = "Open in Mail. Nothing is sent until you send it."
            } catch {
                card.finish(.failed(error.localizedDescription))
                try? appState.actionLog.record(event: "failed", card: card, detail: error.localizedDescription)
                replyNote = error.localizedDescription
            }
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

#if DEBUG
extension KaiMailView {
    static let sampleBody = KaiEmailDraftSource(
        sender: "Ana Torres <ana.torres@acme.com>", subject: "Contract for the Austin office, can you sign by Friday?",
        body: "Hi Jose,\n\nThe final contract for the Austin office is attached. Legal signed off yesterday, so we only need your signature.\n\nCan you sign it by Friday, November 13? The landlord wants it back before the weekend, and the deposit of $12,400 is due the same day.\n\nTwo things to check before you sign:\n- The lease starts January 4, not January 1\n- Parking is now 6 spots instead of 8\n\nThanks!\nAna")
    static let sampleSummary = "**Ana needs your signature on the Austin office contract by Friday, November 13.**\n\nKey points\n- Legal has signed off; only your signature is missing\n- The $12,400 deposit is due the same day\n- Lease starts January 4, and parking is 6 spots, not 8\n\nNeeds you\n- Sign the contract by Friday, November 13\n\nNext step: check the start date and parking, then sign."

    static func sampleMessages() -> [MailMessage] {
        let now = Date()
        func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }
        return [
            MailMessage(id: "1", from: "Priya Shah", subject: "Can you review the Q4 roadmap draft before tomorrow?", preview: "", date: ago(25), isRead: false, sender: "Priya Shah <priya@acme.com>"),
            MailMessage(id: "2", from: "Ana Torres", subject: "Contract for the Austin office, can you sign by Friday?", preview: "", date: ago(70), isRead: false, starred: true, sender: "Ana Torres <ana.torres@acme.com>"),
            MailMessage(id: "3", from: "GitHub", subject: "[kai-os] Pull request #42 merged", preview: "", date: ago(140), isRead: true, sender: "GitHub <notifications@github.com>"),
            MailMessage(id: "4", from: "Sam Lee", subject: "Lunch on Thursday?", preview: "", date: ago(200), isRead: false, sender: "Sam Lee <sam@lee.io>"),
            MailMessage(id: "5", from: "Delta", subject: "Your receipt for flight to Austin", preview: "", date: ago(60 * 20), isRead: true, sender: "Delta <no-reply@delta.com>"),
            MailMessage(id: "6", from: "Marco Diaz", subject: "Re: platform migration timeline", preview: "", date: ago(60 * 27), isRead: true, sender: "Marco Diaz <marco@acme.com>"),
            MailMessage(id: "8", from: "Amazon Web Services", subject: "A new Amazon ElastiCache service update is available [AWS Account: 804385361365]", preview: "", date: ago(30), isRead: false, sender: "Amazon Web Services <no-reply@email.aws.amazon.com>", position: 8),
            MailMessage(id: "9", from: "Amazon Web Services", subject: "A new Amazon ElastiCache service update is available [AWS Account: 406205545357]", preview: "", date: ago(35), isRead: false, sender: "Amazon Web Services <no-reply@email.aws.amazon.com>", position: 9),
            MailMessage(id: "10", from: "Amazon Web Services", subject: "A new Amazon ElastiCache service update is available [AWS Account: 194416699224]", preview: "", date: ago(36), isRead: false, sender: "Amazon Web Services <no-reply@email.aws.amazon.com>", position: 10),
            MailMessage(id: "11", from: "Amazon Web Services", subject: "A new Amazon ElastiCache service update is available [AWS Account: 572756736299]", preview: "", date: ago(38), isRead: false, sender: "Amazon Web Services <no-reply@email.aws.amazon.com>", position: 11),
            MailMessage(id: "7", from: "Medium Digest", subject: "Stories for you", preview: "", date: ago(60 * 50), isRead: true, sender: "Medium <newsletter@medium.com>"),
        ]
    }
}
#endif

/// Buttons that wrap onto a second line when the pane is narrow.
private struct FlowButtons<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { content }
            VStack(alignment: .leading, spacing: 8) { content }
        }
    }
}
