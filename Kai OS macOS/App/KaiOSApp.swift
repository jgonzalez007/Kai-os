//
//  KaiOSApp.swift
//  Kai OS macOS
//
//  Main app — SwiftUI entry point
//  Copyright © 2026 Kai OS Labs. All rights reserved.
//

import SwiftUI
import Foundation
import AppKit
import KaiLocalAI

// MARK: - Models

struct Message: Identifiable, Equatable {
    enum Kind: Equatable {
        /// Part of the conversation sent to the model.
        case chat
        /// App-authored text the model never sees, such as the welcome message.
        case notice
        /// A failure shown in the transcript; the model never sees it.
        case error
    }

    let id: String
    var text: String
    let isUser: Bool
    let timestamp: Date
    var kind: Kind

    init(id: String = UUID().uuidString, text: String = "", isUser: Bool = false, timestamp: Date = Date(), kind: Kind = .chat) {
        self.id = id
        self.text = text
        self.isUser = isUser
        self.timestamp = timestamp
        self.kind = kind
    }
}

struct CalendarEvent: Identifiable {
    let id: String
    let title: String
    let date: Date
    let time: String
    let duration: String
    let color: String
    let location: String
    let attendees: String
    init(id: String = UUID().uuidString, title: String, date: Date, time: String, duration: String, color: String, location: String = "", attendees: String = "") {
        self.id = id; self.title = title; self.date = date; self.time = time
        self.duration = duration; self.color = color; self.location = location; self.attendees = attendees
    }
}

struct MailMessage: Identifiable {
    let id: String
    let from: String
    let subject: String
    let preview: String
    let date: Date
    let isRead: Bool
    let folder: String
    let starred: Bool
    init(id: String = UUID().uuidString, from: String, subject: String, preview: String, date: Date = Date(), isRead: Bool = false, folder: String = "Inbox", starred: Bool = false) {
        self.id = id; self.from = from; self.subject = subject; self.preview = preview
        self.date = date; self.isRead = isRead; self.folder = folder; self.starred = starred
    }
}

struct NoteItem: Identifiable {
    let id: String
    let title: String
    let content: String
    let date: Date
    let tags: [String]
    let pinned: Bool
    init(id: String = UUID().uuidString, title: String, content: String, date: Date = Date(), tags: [String] = [], pinned: Bool = false) {
        self.id = id; self.title = title; self.content = content; self.date = date
        self.tags = tags; self.pinned = pinned
    }
}

// MARK: - App State

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    private static let chatModelDefaultsKey = "kai.chatModel"
    private static let themeDefaultsKey = "kai.themeMode"

    private let ollama = KaiOllamaClient()
    private var replyTask: Task<Void, Never>?
    private var activeReplyID: String?
    private var workspaceObserver: NSObjectProtocol?

    @Published var messages: [Message] = []
    @Published var chatDraft = ""
    @Published var chatModels: [String] = []
    @Published var selectedModel: String = UserDefaults.standard.string(forKey: AppState.chatModelDefaultsKey) ?? "" {
        didSet { UserDefaults.standard.set(selectedModel, forKey: AppState.chatModelDefaultsKey) }
    }
    @Published var activeSidebar: String = "Chat"
    @Published var isProcessing = false
    @Published var themeMode: String = UserDefaults.standard.string(forKey: AppState.themeDefaultsKey) ?? "auto" {
        didSet { UserDefaults.standard.set(themeMode, forKey: AppState.themeDefaultsKey) }
    }
    @Published var enableProactive = true
    @Published var frontmostApp: String = "Finder"
    @Published var appCategory: String = "Other"
    @Published var suggestions: [String] = []
    @Published var calendarEvents: [CalendarEvent] = []
    @Published var selectedEventId: String?
    @Published var mailMessages: [MailMessage] = []
    @Published var selectedMailId: String?
    @Published var mailFolder = "Inbox"
    @Published var starredCount = 0
    @Published var unreadCount = 0
    @Published var notes: [NoteItem] = []
    @Published var selectedNoteId: String?
    @Published var adaptiveMode = "Adaptive Card"
    @Published var appUsageStats: [String: Int] = [:]
    @Published var bookmarks: [String] = [
        "Kai OS Documentation",
        "SwiftUI Best Practices",
        "LLM Integration Guide",
        "macOS App Architecture",
    ]

    var preferredColorScheme: ColorScheme? {
        switch themeMode {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    private init() { generateSampleData() }

    func generateSampleData() {
        let cal = Calendar.current
        let now = Date()
        calendarEvents = [
            CalendarEvent(title: "Kai OS Dev Sync", date: now, time: "2:00 PM", duration: "45min", color: "blue", location: "Zoom", attendees: "Dev Team"),
            CalendarEvent(title: "Architecture Review", date: now, time: "4:00 PM", duration: "1hr", color: "purple", location: "Room 3B"),
            CalendarEvent(title: "Sprint Planning", date: cal.date(byAdding: .day, value: 1, to: now) ?? now, time: "10:00 AM", duration: "1.5hr", color: "green"),
            CalendarEvent(title: "Code Review", date: now, time: "5:30 PM", duration: "30min", color: "orange"),
            CalendarEvent(title: "Team Lunch", date: cal.date(byAdding: .day, value: 1, to: now) ?? now, time: "12:30 PM", duration: "1hr", color: "pink"),
        ]
        mailMessages = [
            MailMessage(from: "Sarah Chen", subject: "Build #2847 passed — ready for review", preview: "Hey! The latest build passed all tests.", isRead: false, starred: true),
            MailMessage(from: "CI System", subject: "Workflow 'macOS Build' failed on main", preview: "The macOS build workflow failed. Check logs.", isRead: false, starred: true),
            MailMessage(from: "Team Update", subject: "Sprint 14 Weekly Update", preview: "Team shipped: context engine v2, sidebar redesign.", isRead: false),
            MailMessage(from: "Alex Rivera", subject: "Re: Calendar API changes", preview: "The new calendar API looks good.", isRead: false, starred: true),
            MailMessage(from: "Newsletter", subject: "Today's AI roundup", preview: "Major updates in AI for developers.", isRead: true),
            MailMessage(from: "David Park", subject: "Design review: Settings panel", preview: "Uploaded updated design mockups.", isRead: false, starred: true),
        ]
        notes = [
            NoteItem(title: "Kai OS Architecture", content: "MVVM: SwiftUI views, ObservableObject models, LocalAI engine.\n\nComponents:\n1. Awareness\n2. LocalAI\n3. KnowledgeBase", tags: ["architecture", "kai-os"], pinned: true),
            NoteItem(title: "SwiftUI Tips", content: "Keep views thin, logic in view models. Composition over inheritance.", tags: ["swiftui", "tips"], pinned: false),
            NoteItem(title: "Sprint 14 Notes", content: "Completed:\n- Context engine v2\n- Sidebar redesign\n\nNext:\n- Full AI integration\n- Mail draft automation", tags: ["meetings", "sprint"], pinned: false),
            NoteItem(title: "API: Local AI", content: "Chat replies stream from a local Ollama model through KaiOllamaClient.", tags: ["api", "reference"], pinned: true),
        ]
        starredCount = mailMessages.filter { $0.starred }.count
        unreadCount = mailMessages.filter { !$0.isRead }.count
        suggestions = ["Summarize calendar", "Check new mail"]
        messages = [Self.welcomeMessage()]
    }

    private static func welcomeMessage() -> Message {
        Message(
            text: "Welcome to **Kai OS**. Replies come from a local model through Ollama, so this chat stays on your Mac.\n\nCalendar, Mail and Notes show sample data for now, and the assistant can't read them yet.",
            kind: .notice
        )
    }

    // MARK: Frontmost app awareness

    func startMonitoring() {
        guard workspaceObserver == nil else { return }
        updateFrontmostApp(NSWorkspace.shared.frontmostApplication)
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.updateFrontmostApp(app) }
        }
        Task { try? await refreshChatModels() }
    }

    /// Ignores Kai OS itself, so context keeps describing the app the user came from.
    private func updateFrontmostApp(_ app: NSRunningApplication?) {
        guard let app, app.bundleIdentifier != Bundle.main.bundleIdentifier, let name = app.localizedName else { return }
        frontmostApp = name
        appCategory = Self.category(forBundleIdentifier: app.bundleIdentifier ?? "")
    }

    private static func category(forBundleIdentifier identifier: String) -> String {
        switch identifier {
        case "com.apple.Safari", "com.google.Chrome", "org.mozilla.firefox", "company.thebrowser.Browser", "com.brave.Browser", "com.microsoft.edgemac":
            return "Browser"
        case "com.apple.mail", "com.microsoft.Outlook":
            return "Mail"
        case "com.apple.dt.Xcode", "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "com.apple.Terminal", "com.googlecode.iterm2":
            return "Code Editor"
        default:
            return "Other"
        }
    }

    // MARK: Chat

    func refreshChatModels() async throws {
        let models = try await ollama.listChatModels()
        chatModels = models
        if !models.contains(selectedModel) { selectedModel = models.first ?? "" }
    }

    func sendMessage(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isProcessing else { return }
        messages.append(Message(text: trimmed, isUser: true))
        let reply = Message()
        let history = conversationForModel()
        messages.append(reply)
        isProcessing = true
        activeReplyID = reply.id
        replyTask = Task { await streamReply(replyID: reply.id, history: history) }
    }

    func cancelReply() {
        replyTask?.cancel()
    }

    func startNewChat() {
        replyTask?.cancel()
        activeReplyID = nil
        isProcessing = false
        messages = [Self.welcomeMessage()]
    }

    private func streamReply(replyID: String, history: [KaiOllamaMessage]) async {
        defer {
            if activeReplyID == replyID {
                activeReplyID = nil
                isProcessing = false
            }
        }
        do {
            if !chatModels.contains(selectedModel) { try await refreshChatModels() }
            guard !selectedModel.isEmpty else { throw KaiOllamaError.noChatModel }
            for try await delta in ollama.streamChat(model: selectedModel, messages: history) {
                updateMessage(id: replyID) { $0.text += delta }
            }
            if Task.isCancelled {
                removeMessageIfEmpty(id: replyID)
            } else {
                updateMessage(id: replyID) { message in
                    if message.text.isEmpty {
                        message.text = "The model returned an empty reply."
                        message.kind = .error
                    }
                }
            }
        } catch is CancellationError {
            removeMessageIfEmpty(id: replyID)
        } catch {
            updateMessage(id: replyID) { message in
                message.text = error.localizedDescription
                message.kind = .error
            }
        }
    }

    private func conversationForModel() -> [KaiOllamaMessage] {
        let system = KaiOllamaMessage(
            role: "system",
            content: """
            You are Kai, a personal AI assistant running locally on the user's Mac. Be concise and direct. \
            You can't read the user's calendar, mail, notes or files yet; say so instead of inventing their contents. \
            Current date and time: \(Date().formatted(date: .complete, time: .shortened)). \
            The user was most recently in the app: \(frontmostApp).
            """
        )
        let turns = messages
            .filter { $0.kind == .chat && !$0.text.isEmpty }
            .map { KaiOllamaMessage(role: $0.isUser ? "user" : "assistant", content: $0.text) }
        return [system] + turns
    }

    private func updateMessage(id: String, _ change: (inout Message) -> Void) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        change(&messages[index])
    }

    private func removeMessageIfEmpty(id: String) {
        messages.removeAll { $0.id == id && $0.text.isEmpty }
    }
}

// MARK: - Calendar View

struct CalendarView: View {
    @EnvironmentObject var appState: AppState
    var todayEvents: [CalendarEvent] {
        let cal = Calendar.current; let now = Date()
        return appState.calendarEvents.filter { cal.isDate($0.date, inSameDayAs: now) }
    }
    var upcomingEvents: [CalendarEvent] {
        let cal = Calendar.current; let now = Date()
        return appState.calendarEvents.filter { $0.date > now && !cal.isDate($0.date, inSameDayAs: now) }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Today").font(.title2).fontWeight(.bold)
                    Text("\(todayEvents.count) events").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }.padding()
            Divider()
            ScrollView {
                VStack(spacing: 8) {
                    SectionHeader(title: "Today")
                    ForEach(todayEvents) { e in CalendarEventRow(event: e) }
                    SectionHeader(title: "Upcoming")
                    ForEach(upcomingEvents) { e in CalendarEventRow(event: e) }
                }.padding()
            }
            HStack {
                Button { } label: { Image(systemName: "chevron.left").font(.title2) }
                Spacer()
                Text(Date().formatted(date: .numeric, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { } label: { Image(systemName: "chevron.right").font(.title2) }
            }.padding()
        }
    }
}

struct SectionHeader: View {
    let title: String
    var body: some View { Text(title).font(.headline).foregroundStyle(.secondary).padding(.bottom, -4) }
}

struct CalendarEventRow: View {
    let event: CalendarEvent
    @EnvironmentObject var appState: AppState
    var color: Color {
        switch event.color { case "blue": return .blue; case "purple": return .purple; case "green": return .green; case "orange": return .orange; case "pink": return .pink; default: return .gray }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Rectangle().fill(color).frame(width: 4, height: 40).cornerRadius(2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title).fontWeight(.semibold)
                    HStack(spacing: 8) {
                        Label(event.time, systemImage: "clock").font(.caption).foregroundStyle(.secondary)
                        Label(event.duration, systemImage: "hourglass").font(.caption).foregroundStyle(.secondary)
                        if !event.location.isEmpty { Label(event.location, systemImage: "mappin").font(.caption).foregroundStyle(.secondary) }
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }.padding(12).background(appState.selectedEventId == event.id ? color.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 8)).onTapGesture { appState.selectedEventId = event.id }
        }
    }
}

// MARK: - Mail View

struct MailView: View {
    @EnvironmentObject var appState: AppState
    var starredMessages: [MailMessage] { appState.mailMessages.filter { $0.starred } }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search mail", text: .constant(""), axis: .vertical).disabled(true)
            }.padding()
            if !starredMessages.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "star.fill").foregroundStyle(.yellow).font(.caption)
                    Text("\(starredMessages.count) starred").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }.padding(.horizontal).padding(.bottom, 4)
            }
            Divider()
            List(appState.mailMessages, id: \.id) { msg in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(msg.from).fontWeight(.semibold).font(.caption)
                        Spacer()
                        Text(msg.date, style: .relative).font(.caption2).foregroundStyle(.secondary)
                        if msg.starred { Image(systemName: "star.fill").foregroundStyle(.yellow).font(.caption2) }
                        if !msg.isRead { Circle().fill(Color.blue).frame(width: 8, height: 8) }
                    }
                    Text(msg.subject).fontWeight(msg.isRead ? .regular : .semibold).font(.callout)
                    Text(msg.preview).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }.padding(8).background(msg.isRead ? .clear : Color(.controlBackgroundColor).opacity(0.4), in: RoundedRectangle(cornerRadius: 6)).onTapGesture { appState.selectedMailId = msg.id }
            }.listStyle(.plain)
            HStack {
                Spacer()
                Button { } label: { HStack(spacing: 4) { Image(systemName: "pencil"); Text("Compose") }.fontWeight(.semibold) }
                    .buttonStyle(.borderedProminent).controlSize(.small).padding(.horizontal).padding(.bottom, 8)
            }
        }
    }
}

// MARK: - Notes View

struct NotesView: View {
    @EnvironmentObject var appState: AppState
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search notes", text: .constant(""), axis: .vertical).disabled(true)
                Spacer()
                Button { } label: { Image(systemName: "plus") }
            }.padding()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button("All") { }.buttonStyle(.bordered).controlSize(.small)
                    ForEach(["architecture", "meetings", "swiftui", "api", "tips", "reference", "kai-os", "sprint"], id: \.self) { t in
                        Button(t.capitalized) { }.buttonStyle(.bordered).controlSize(.small)
                    }
                }
            }.padding(.horizontal).padding(.bottom, 8)
            Divider()
            List(appState.notes, id: \.id) { note in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        if note.pinned { Image(systemName: "pin.fill").foregroundStyle(.orange).font(.caption2) }
                        Text(note.title).fontWeight(.semibold)
                        Spacer()
                        Text(note.date, style: .relative).font(.caption2).foregroundStyle(.secondary)
                    }
                    Text(note.content).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                    HStack(spacing: 4) { ForEach(note.tags, id: \.self) { t in
                        Text("#\(t)").font(.caption2).foregroundStyle(.blue).padding(.horizontal, 4).padding(.vertical, 1).background(Color.blue.opacity(0.1), in: Capsule())
                    }}
                }.padding(8).background(Color(.controlBackgroundColor).opacity(0.4), in: RoundedRectangle(cornerRadius: 6)).onTapGesture { appState.selectedNoteId = note.id }
            }.listStyle(.plain)
        }
    }
}

// MARK: - Chat View

struct ChatView: View {
    @EnvironmentObject var appState: AppState
    @FocusState private var inputFocused: Bool

    private var canSend: Bool {
        !appState.chatDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(appState.messages) { MessageBubbleView(message: $0) }
                        Color.clear.frame(height: 1).id("chat-bottom")
                    }.padding()
                }
                .background(Color(.windowBackgroundColor))
                .defaultScrollAnchor(.bottom)
                .onChange(of: appState.messages) { _, _ in
                    proxy.scrollTo("chat-bottom", anchor: .bottom)
                }
            }
            Divider()
            HStack(spacing: 8) {
                TextField("Ask Kai OS...", text: $appState.chatDraft, axis: .vertical)
                    .lineLimit(1...6)
                    .textFieldStyle(.plain)
                    .focused($inputFocused)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(.controlBackgroundColor)))
                    .onSubmit(send)
                if appState.isProcessing {
                    Button(action: appState.cancelReply) {
                        Image(systemName: "stop.circle.fill").font(.title2).foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Stop the reply")
                    .frame(width: 36, height: 36)
                } else {
                    Button(action: send) {
                        Image(systemName: "arrow.up.circle.fill").font(.title2).foregroundStyle(canSend ? .blue : .secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                    .help("Send")
                    .frame(width: 36, height: 36)
                }
            }.padding()
        }
        .onAppear { inputFocused = true }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "cpu").foregroundStyle(.secondary).font(.caption)
            if appState.chatModels.isEmpty {
                Text("Ollama not connected").font(.caption).foregroundStyle(.secondary)
            } else {
                Picker("Model", selection: $appState.selectedModel) {
                    ForEach(appState.chatModels, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                .controlSize(.small)
            }
            Spacer()
            Button(action: appState.startNewChat) {
                Label("New Chat", systemImage: "plus.bubble")
            }
            .controlSize(.small)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func send() {
        guard canSend, !appState.isProcessing else { return }
        appState.sendMessage(text: appState.chatDraft)
        appState.chatDraft = ""
        inputFocused = true
    }
}

struct MessageBubbleView: View {
    let message: Message

    private var rendered: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: message.text, options: options)) ?? AttributedString(message.text)
    }

    var body: some View {
        HStack(alignment: .top) {
            if message.isUser {
                Spacer(minLength: 60)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(message.text)
                        .textSelection(.enabled)
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(Color.blue, in: RoundedRectangle(cornerRadius: 16))
                    Text(message.timestamp, style: .time).font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: message.kind == .error ? "exclamationmark.triangle.fill" : "sparkles")
                            .foregroundStyle(message.kind == .error ? .orange : .purple)
                            .font(.caption)
                        Text(message.timestamp, style: .time).font(.caption2).foregroundStyle(.secondary)
                    }
                    if message.text.isEmpty {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(rendered).textSelection(.enabled)
                    }
                }
                .padding(12)
                .background(Color(.controlBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
                Spacer(minLength: 60)
            }
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage(KaiNotchPreferences.enabledKey) private var notchEnabled = true
    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $appState.themeMode) {
                    Text("Auto").tag("auto"); Text("Light").tag("light"); Text("Dark").tag("dark")
                }
            }
            Section("AI") {
                if appState.chatModels.isEmpty {
                    Text("Ollama not connected. Start Ollama, then refresh.").foregroundStyle(.secondary)
                } else {
                    Picker("Local model", selection: $appState.selectedModel) {
                        ForEach(appState.chatModels, id: \.self) { Text($0).tag($0) }
                    }
                }
                Button("Refresh Models") { Task { try? await appState.refreshChatModels() } }
                Toggle("Enable Proactive Suggestions", isOn: $appState.enableProactive)
            }
            Section("Notch") {
                Toggle("Show Kai at the notch", isOn: $notchEnabled)
                    .onChange(of: notchEnabled) { _, _ in KaiNotchWindowController.shared.applyEnabledPreference() }
                LabeledContent("Toggle shortcut", value: "⌃⌥Space")
                LabeledContent("Tap right ⌘") {
                    if KaiSidekickHotkeyMonitor.shared.isRightCommandAvailable {
                        Text("Enabled").foregroundStyle(.secondary)
                    } else {
                        Button("Enable…") { KaiSidekickHotkeyMonitor.shared.requestRightCommandPermission() }
                    }
                }
            }
            Section("Knowledge") {
                ForEach(appState.bookmarks, id: \.self) { bm in
                    HStack { Image(systemName: "bookmark"); Text(bm); Spacer() }
                }
            }
            Section("Privacy") {
                Text("Chat runs through Ollama on this Mac. Nothing is sent to a cloud provider.").font(.caption).foregroundStyle(.secondary)
            }
            Section("About") {
                Text("Kai OS v1.0.0").fontWeight(.semibold)
                Text("Personal AI for macOS").foregroundStyle(.secondary)
                Text("© 2026 Kai OS Labs").font(.caption)
            }
        }.formStyle(.grouped).navigationTitle("Settings")
    }
}

struct StatItem: View {
    let icon: String; let value: String; let label: String
    var body: some View {
        VStack(spacing: 2) { Image(systemName: icon).font(.caption).foregroundStyle(.blue)
            Text(value).font(.headline).fontWeight(.bold)
            Text(label).font(.caption2).foregroundStyle(.secondary) }.frame(maxWidth: .infinity)
    }
}

// MARK: - Main App

@main
struct KaiOSApp: App {
    @NSApplicationDelegateAdaptor(KaiAppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState.shared

    var body: some Scene {
        WindowGroup {
            KaiMainView()
                .environmentObject(appState)
                .preferredColorScheme(appState.preferredColorScheme)
                .frame(minWidth: 800, minHeight: 500)
                .onAppear {
                    appState.startMonitoring()
                    #if DEBUG
                    KaiChatSelfTest.runIfRequested(appState: appState)
                    KaiNotchSelfTest.runIfRequested(appState: appState)
                    #endif
                }
        }
        .windowToolbarStyle(.unified)
        .windowStyle(.hiddenTitleBar)

        Settings {
            SettingsView()
                .environmentObject(appState)
                .preferredColorScheme(appState.preferredColorScheme)
        }
    }
}

final class KaiAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        KaiNotchWindowController.shared.start(appState: AppState.shared)
    }
}

struct KaiMainView: View {
    @EnvironmentObject var appState: AppState

    private var selection: Binding<String?> {
        Binding(
            get: { appState.activeSidebar },
            set: { if let value = $0 { appState.activeSidebar = value } }
        )
    }

    var body: some View {
        NavigationSplitView {
            sidebar.navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            switch appState.activeSidebar {
            case "Calendar": CalendarView()
            case "Mail": MailView()
            case "Notes": NotesView()
            case "Settings": SettingsView()
            default: ChatView()
            }
        }
    }

    private var sidebar: some View {
        List(selection: selection) {
            Section {
                HStack {
                    Image(systemName: "sparkles").foregroundStyle(.purple).font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Kai OS").fontWeight(.bold)
                        Text("Personal AI").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                Label("Chat", systemImage: "bubble.left.and.bubble.right").tag("Chat")
                Label("Calendar", systemImage: "calendar").badge(appState.calendarEvents.count).tag("Calendar")
                Label("Mail", systemImage: "envelope").badge(appState.unreadCount).tag("Mail")
                Label("Notes", systemImage: "note.text").badge(appState.notes.count).tag("Notes")
            }
            Section("Context") {
                VStack(alignment: .leading, spacing: 4) {
                    Text(appState.frontmostApp).font(.caption).fontWeight(.semibold)
                    Text(appState.appCategory).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Section("Knowledge") {
                ForEach(appState.bookmarks, id: \.self) { bm in
                    Label(bm, systemImage: "bookmark").font(.caption2)
                }
            }
            Section("Recent Notes") {
                ForEach(Array(appState.notes.prefix(3))) { note in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            if note.pinned { Image(systemName: "pin.fill").foregroundStyle(.orange).font(.caption2) }
                            Text(note.title).font(.caption2).fontWeight(.semibold)
                        }
                        Text(note.content).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                    }.padding(.vertical, 2)
                }
            }
            Section {
                Label("Preferences", systemImage: "gearshape").tag("Settings")
            }
        }.listStyle(.sidebar)
    }
}

#if DEBUG
struct Previews: PreviewProvider {
    static var previews: some View {
        let s = AppState.shared
        Group { ChatView().environmentObject(s).frame(width: 500, height: 400)
            CalendarView().environmentObject(s).frame(width: 500, height: 400)
            MailView().environmentObject(s).frame(width: 500, height: 400)
            NotesView().environmentObject(s).frame(width: 500, height: 400) }
    }
}
#endif
