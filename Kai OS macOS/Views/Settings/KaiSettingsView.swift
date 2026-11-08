//
//  KaiSettingsView.swift
//  Kai OS macOS
//
//  Modern settings — card-based layout, grouped sections
//  Copyright © 2026 Kai OS Labs. All rights reserved.
//

import KaiDesk
import SwiftUI
import KaiShared

struct KaiSettingsView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("kai.notch.enabled") private var notchEnabled = true
    @AppStorage(KaiNotchPreferences.hoverOpenKey) private var hoverOpen = true
    @AppStorage(KaiNotchPreferences.statusKey) private var notchStatus = true
    @AppStorage(KaiNotchPreferences.hideFullScreenKey) private var hideFullScreen = true
    @AppStorage(KaiNotchPreferences.menuBarKey) private var menuBar = true
    @ObservedObject private var desk = KaiDeskController.shared
    @ObservedObject private var updates = KaiUpdateController.shared
    @AppStorage(KaiMotion.key) private var motion = true
    
    enum Page: String, CaseIterable {
        case ai, knowledge, overnight, notch, system
        var title: String {
            switch self {
            case .ai: return "AI Models & Accounts"
            case .knowledge: return "Knowledge Sources"
            case .overnight: return "Overnight & Suggestions"
            case .notch: return "Notch & Desk"
            case .system: return "System"
            }
        }
        var subtitle: String {
            switch self {
            case .ai: return "Pick the model Kai thinks with, on this Mac or in the cloud."
            case .knowledge: return "What Kai learns from to answer your questions and prepare your day."
            case .overnight: return "Let Kai get things ready while you sleep. It only prepares cards: nothing is sent without your approval."
            case .notch: return "The notch, your Shelf, clipboard history and Claude Code."
            case .system: return "Look, updates and privacy."
            }
        }
        var symbol: String {
            switch self {
            case .ai: return "cpu"
            case .knowledge: return "tray.full"
            case .overnight: return "moon.stars"
            case .notch: return "rectangle.topthird.inset.filled"
            case .system: return "gearshape"
            }
        }
    }

    /// False in the separate Preferences window, which has no Home to go back to.
    var showsHome = true
    /// Debug snapshots start on a chosen page.
    static var startPage = Page.ai
    @State private var page = KaiSettingsView.startPage

    var body: some View {
        HStack(spacing: 0) {
            navigation
                .frame(width: 270)
            pageScroll
        }
        .background(Color(red: 0.035, green: 0.035, blue: 0.04))
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)
    }

    // ── Navigation column ──
    private var navigation: some View {
        VStack(alignment: .leading, spacing: 4) {
            if showsHome {
                Button { appState.activeSidebar = "Chat" } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.left")
                        Text("Home")
                    }
                    .fontWeight(.medium)
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(Capsule().fill(Color.white))
                    .foregroundStyle(Color.black)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 22)
            }
            Text("Settings").font(.system(size: 26, weight: .semibold)).padding(.bottom, 14)
            navGroup("App") { navItem(.ai) }
            navGroup("Personalization") {
                navItem(.knowledge)
                navLink("Sidekick", symbol: "sparkle", target: "Sidekick")
                navItem(.overnight)
                navItem(.notch)
            }
            navGroup("Support") {
                navItem(.system)
                navLink("Permissions", symbol: "checkmark.shield", target: "Permissions")
                navLink("Health", symbol: "heart.text.square", target: "Health")
            }
            Spacer()
            Divider().overlay(Color.white.opacity(0.08))
            HStack {
                Text("v\(updates.currentVersion.description)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Link(destination: URL(string: "https://github.com/jgonzalez007/Kai-os")!) {
                    HStack(spacing: 4) {
                        Image(systemName: "heart.fill").foregroundStyle(Color.yellow)
                        Text("Open source")
                        Image(systemName: "arrow.up.right").font(.caption2)
                    }
                    .font(.caption)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 10)
        }
        .padding(.horizontal, 22).padding(.vertical, 24)
    }

    private func navGroup<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).fontWeight(.medium).foregroundStyle(.secondary)
                .padding(.top, 16).padding(.bottom, 6).padding(.leading, 4)
            content()
        }
    }

    private func navItem(_ target: Page) -> some View {
        Button { page = target } label: {
            HStack(spacing: 12) {
                Image(systemName: target.symbol).frame(width: 20).foregroundStyle(.secondary)
                Text(target.title)
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 14).fill(page == target ? Color.white.opacity(0.1) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// An item that opens one of the app's other pages.
    private func navLink(_ title: String, symbol: String, target: String) -> some View {
        Button { appState.activeSidebar = target } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol).frame(width: 20).foregroundStyle(.secondary)
                Text(title)
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(page.title).font(.system(size: 30, weight: .semibold))
            Text(page.subtitle).font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var pageScroll: some View {
        ScrollView {
            VStack(spacing: 20) {
                pageHeader

                Divider().overlay(Color.white.opacity(0.08))

                if page == .system {
                // ── Appearance ──
                settingsCard {
                    SectionHeader(title: "Appearance")

                    Toggle("Animated effects", isOn: $motion)
                    Text("A shimmering Working pill, a sliding tab highlight and replies that fade in as they are written. Turn this off for the plain look from before.")
                        .font(KaiFont.caption2Strong).foregroundStyle(KaiColor.textTertiary)
                    
                    Text("Kai OS uses its dark look everywhere.")
                        .font(KaiFont.caption2Strong).foregroundStyle(KaiColor.textTertiary)
                    
                }

                }

                if page == .ai {
                // ── AI ──
                settingsCard {
                    SectionHeader(title: "AI Model")
                    
                    Picker("Model", selection: $appState.selectedModel) {
                        ForEach(appState.chatModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    
                    Button("Refresh Models") {
                        Task { try? await appState.refreshChatModels() }
                    }
                    .buttonBorderShape(.roundedRectangle)
                    .controlSize(.small)
                }
                
                }

                if page == .ai {
                // ── Cloud ──
                settingsCard {
                    SectionHeader(title: "Cloud AI")
                    
                    Toggle("Use Cloud AI", isOn: $appState.useCloud)
                    
                    if appState.useCloud {
                        Picker("Provider", selection: $appState.selectedCloudProvider) {
                            Text("OpenAI").tag("openai")
                            Text("Anthropic").tag("anthropic")
                        }
                        .pickerStyle(.segmented)
                        .padding(.top, 8)
                        
                        Divider().kaiDivider()
                        
                        VStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("OpenAI API Key").font(KaiFont.captionStrong)
                                    .foregroundStyle(KaiColor.textTertiary)
                                SecureField("", text: $appState.openAIApiKey)
                                    .kaiInput()
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Anthropic API Key").font(KaiFont.captionStrong)
                                    .foregroundStyle(KaiColor.textTertiary)
                                SecureField("", text: $appState.anthropicApiKey)
                                    .kaiInput()
                            }
                        }
                        .padding(.top, 12)
                    }
                    
                    Text("Cloud AI uses OpenAI Chat Completions API or Anthropic Messages API. API keys are stored in your keychain.")
                        .font(KaiFont.caption2Strong)
                        .foregroundStyle(KaiColor.textTertiary)
                }
                
                }

                if page == .notch {
                // ── Notch ──
                settingsCard {
                    SectionHeader(title: "Notch")
                    
                    Toggle("Show at notch", isOn: $notchEnabled)
                        .onChange(of: notchEnabled) {
                            _, _ in KaiNotchWindowController.shared.applyEnabledPreference()
                        }
                    Toggle("Open when I hover over the notch", isOn: $hoverOpen)
                    Text("Hover for a moment and the panel opens, then closes when you move away. It stays open while you are typing, talking or answering a permission request. Clicking the notch or using the hotkey opens it and keeps it open.")
                        .font(KaiFont.caption2Strong).foregroundStyle(KaiColor.textTertiary)
                    Toggle("Show status beside the notch", isOn: $notchStatus)
                        .onChange(of: notchStatus) { _, _ in KaiNotchWindowController.shared.preferencesChanged() }
                    Text("A small Kai mark and a colored dot (green ready, blue working, orange needs you, red AI offline). They cover a little of the menu bar next to the notch.")
                        .font(KaiFont.caption2Strong).foregroundStyle(KaiColor.textTertiary)
                    Toggle("Hide in full-screen apps", isOn: $hideFullScreen)
                        .onChange(of: hideFullScreen) { _, _ in KaiNotchWindowController.shared.preferencesChanged() }
                    Toggle("Show Kai in the menu bar", isOn: $menuBar)
                    
                    Divider().kaiDivider()
                    
                    VStack(spacing: 10) {
                        HStack {
                            Text("⌃⌥ Space").font(KaiFont.captionStrong)
                                .foregroundStyle(KaiColor.textTertiary)
                            Spacer()
                            Text("Toggle chat").font(KaiFont.caption)
                                .foregroundStyle(KaiColor.textSecondary)
                        }
                        
                        HStack {
                            Text("Double ⌃⌥ Space").font(KaiFont.captionStrong)
                                .foregroundStyle(KaiColor.textTertiary)
                            Spacer()
                            Text("Draft email reply").font(KaiFont.caption)
                                .foregroundStyle(KaiColor.textSecondary)
                        }
                        
                        HStack {
                            Text("Hold ⌃⌥ Space").font(KaiFont.captionStrong)
                                .foregroundStyle(KaiColor.textTertiary)
                            Spacer()
                            Text("Talk / Voice input").font(KaiFont.caption)
                                .foregroundStyle(KaiColor.textSecondary)
                        }
                        
                        HStack {
                            Text("Tap right ⌘").font(KaiFont.captionStrong)
                                .foregroundStyle(KaiColor.textTertiary)
                            Spacer()
                            if KaiSidekickHotkeyMonitor.shared.isRightCommandAvailable {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(KaiColor.success)
                                    .font(KaiFont.captionStrong)
                            } else {
                                Button("Open Permissions") {
                                    appState.activeSidebar = "Permissions"
                                }
                                .font(KaiFont.captionStrong)
                                .foregroundStyle(KaiColor.warning)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
                
                }

                if page == .knowledge { sourceGrid }

                if page == .knowledge {
                // ── Slack ──
                settingsCard {
                    SectionHeader(title: "Slack")

                    if let identity = appState.slackIdentity {
                        HStack {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(KaiColor.success)
                            Text("Connected to \(identity.team) as \(identity.user)").font(KaiFont.bodyStrong)
                            Spacer()
                            Button("Disconnect") { appState.disconnectSlack() }.controlSize(.small)
                        }
                        Toggle("Include direct messages when indexing", isOn: $appState.slackIncludeDirectMessages)
                        Text("Kai reads and searches Slack. It can't post, edit or delete. Recent messages from your channels go into the knowledge base on this Mac when you click Index now. Direct messages are left out unless you turn them on.")
                            .font(KaiFont.caption2Strong).foregroundStyle(KaiColor.textTertiary)
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Slack User OAuth Token").font(KaiFont.captionStrong).foregroundStyle(KaiColor.textTertiary)
                            SecureField("xoxp-…", text: $appState.slackTokenDraft).kaiInput()
                        }
                        Button(appState.slackState == .loading ? "Checking…" : "Connect") { appState.connectSlack() }
                            .buttonStyle(.borderedProminent).controlSize(.small)
                            .disabled(appState.slackState == .loading)
                        Text("Create a Slack app for your workspace with read-only user scopes, install it, and paste its User OAuth Token here. Steps and scopes are in BUILD.md. Company workspaces may need an admin to approve the app. The token is kept in your Keychain.")
                            .font(KaiFont.caption2Strong).foregroundStyle(KaiColor.textTertiary)
                    }

                    if case .failed(let message) = appState.slackState {
                        Text(message).font(KaiFont.caption).foregroundStyle(KaiColor.textSecondary)
                    }

                    Text("Without a token, Kai can still read the Slack window that's open on this Mac when you ask (for example, \"summarize this channel\"). That needs Accessibility permission and only sees what is on screen.")
                        .font(KaiFont.caption2Strong).foregroundStyle(KaiColor.textTertiary)
                }

                }

                if page == .knowledge {
                // ── Knowledge base ──
                settingsCard {
                    SectionHeader(title: "Knowledge base")

                    Text(appState.knowledgeDocumentCount == 0
                         ? "Nothing indexed yet. Kai searches the Markdown and text files in your knowledge folder, plus Notes, Calendar and Mail subjects for the sources you've connected. It all stays on this Mac."
                         : appState.knowledgeCounts.sorted { $0.key < $1.key }
                            .map { "\(AppState.knowledgeSourceNames[$0.key] ?? $0.key): \($0.value)" }
                            .joined(separator: " · "))
                        .font(KaiFont.caption)
                        .foregroundStyle(KaiColor.textSecondary)

                    HStack {
                        Button(appState.isIndexingKnowledge ? "Indexing…" : "Index now") { appState.indexKnowledge() }
                            .buttonStyle(.borderedProminent)
                            .disabled(appState.isIndexingKnowledge)
                        Button("Open folder") { appState.openKnowledgeFolder() }
                    }
                    .controlSize(.small)

                    Text(appState.knowledgeFolder.path)
                        .font(KaiFont.caption2Strong)
                        .foregroundStyle(KaiColor.textTertiary)

                    if case .failed(let message) = appState.knowledgeState {
                        Text(message).font(KaiFont.caption).foregroundStyle(KaiColor.textSecondary)
                    }
                }
                .onAppear { appState.refreshKnowledgeCounts() }

                }

                if page == .overnight {
                // ── Night Shift ──
                settingsCard {
                    SectionHeader(title: "Night Shift")

                    Toggle("Prepare things overnight", isOn: Binding(
                        get: { appState.nightShift.enabled },
                        set: { var next = appState.nightShift; next.enabled = $0; appState.updateNightShift(next) }
                    ))

                    if appState.nightShift.enabled {
                        DatePicker("Time", selection: Binding(
                            get: { Calendar.current.date(from: DateComponents(hour: appState.nightShift.hour, minute: appState.nightShift.minute)) ?? Date() },
                            set: {
                                var next = appState.nightShift
                                next.hour = Calendar.current.component(.hour, from: $0)
                                next.minute = Calendar.current.component(.minute, from: $0)
                                appState.updateNightShift(next)
                            }
                        ), displayedComponents: .hourAndMinute)
                        if let next = appState.nightShift.nextRun(after: Date()) {
                            Text("Next run: \(next.formatted(date: .abbreviated, time: .shortened))")
                                .font(KaiFont.caption).foregroundStyle(KaiColor.textSecondary)
                        }
                    }

                    Divider().kaiDivider()

                    Text("What to include").font(KaiFont.captionStrong).foregroundStyle(KaiColor.textTertiary)
                    ForEach(KaiNightShiftSource.allCases, id: \.self) { source in
                        nightShiftSourceRow(source)
                    }
                    Text("This list also decides what “Index now” and the 7 am morning cards read. Nothing outside it is touched.")
                        .font(KaiFont.caption2Strong).foregroundStyle(KaiColor.textTertiary)

                    Divider().kaiDivider()

                    if let record = appState.nightShiftRecord {
                        Text("Last run \(record.ranAt.formatted(date: .abbreviated, time: .shortened)). \(record.summary)")
                            .font(KaiFont.caption).foregroundStyle(KaiColor.textSecondary)
                    }

                    if let message = appState.nightShiftMessage {
                        Text(message).font(KaiFont.caption).foregroundStyle(KaiColor.textSecondary)
                    }

                    Button(appState.isRunningNightShift ? "Running…" : "Run now") { appState.runNightShiftNow() }
                        .controlSize(.small)
                        .disabled(appState.isRunningNightShift)

                    Text("At the set time, Kai OS starts in the background, updates the knowledge base and prepares your morning cards, then quits. It only prepares cards: nothing is sent or changed without your approval. It skips the run in Low Power Mode, when the Mac is hot, or on a low battery. A sleeping Mac is not woken; if the Mac is asleep at that time, the job runs when it wakes. This adds a launch agent at ~/Library/LaunchAgents/ai.kai.nightshift.plist, and turning it off removes it.")
                        .font(KaiFont.caption2Strong)
                        .foregroundStyle(KaiColor.textTertiary)
                }

                }

                if page == .notch {
                // ── Desk ──
                settingsCard {
                    SectionHeader(title: "Desk")

                    Toggle("Clipboard history", isOn: $desk.clipboardEnabled)
                    Text("Remembers your last 50 text copies so you can copy one again from the notch. Kept on this Mac only. Password managers, dictation and anything an app marks as secret are never recorded, and file copies from Finder are skipped.")
                        .font(KaiFont.caption2Strong).foregroundStyle(KaiColor.textTertiary)
                    if desk.clipboardEnabled {
                        Toggle("Ignore copies from terminals", isOn: $desk.clipboardIgnoreTerminals)
                        Toggle("Keep history after quitting", isOn: $desk.clipboardKeepAfterQuit)
                        Text(desk.clipboardKeepAfterQuit
                             ? "History is saved in a private file in Application Support, so it survives a restart. Turn this off to delete that file."
                             : "History is held in memory and disappears when Kai OS quits.")
                            .font(KaiFont.caption2Strong).foregroundStyle(KaiColor.textTertiary)
                        Button("Clear history") { desk.clearClipboard() }.controlSize(.small)
                    }

                    Divider().kaiDivider()

                    Text("Shelf").font(KaiFont.captionStrong)
                    Text("Drop files, links or text on the notch and drag them out later. Files stay where they are: the Shelf keeps a reference, not a copy.")
                        .font(KaiFont.caption2Strong).foregroundStyle(KaiColor.textTertiary)
                    Toggle("Remove an item when I drag it out (5 second Undo)", isOn: $desk.shelfRemoveOnDragOut)
                    Text("Pinned items always stay.")
                        .font(KaiFont.caption2Strong).foregroundStyle(KaiColor.textTertiary)

                    Divider().kaiDivider()

                    Text("Claude Code").font(KaiFont.captionStrong)
                    Toggle("Listen for Claude Code", isOn: $desk.hooksEnabled)
                    Text("Status: \(desk.hooksMessage)")
                        .font(KaiFont.caption).foregroundStyle(KaiColor.textSecondary)
                    Text("Shows Claude Code's permission requests in the notch so you can allow or deny them there, a Done peek when a task ends, and the helper agents that are running. Kai OS never edits your Claude settings: you paste the hooks in yourself.")
                        .font(KaiFont.caption2Strong).foregroundStyle(KaiColor.textTertiary)
                    if !desk.helperExists {
                        Text("The kai-hook helper was not found next to the app. Install with scripts/install-app.sh, which puts it in the app.")
                            .font(KaiFont.caption2Strong).foregroundStyle(KaiColor.warning)
                    }
                    Button("Copy hook setup") { desk.copySetupSnippet() }.controlSize(.small)
                    Text("Back up ~/.claude/settings.json first. If it has no \"hooks\" key, paste the copied block in as a new top-level key. If it already has one, add each event's entry next to your own and leave your existing entries alone. Then check the file with: python3 -m json.tool ~/.claude/settings.json and restart Claude Code. Full steps are in INSTALL-HOOKS.md. Kai OS never allows anything on its own: Allow is sent only when you press it, and if Kai OS is not running or you do not answer in time, Claude Code asks in the terminal as usual.")
                        .font(KaiFont.caption2Strong).foregroundStyle(KaiColor.textTertiary)
                }

                }

                if page == .system {
                // ── Updates ──
                settingsCard {
                    SectionHeader(title: "Updates")
                    Text("Kai OS \(updates.currentVersion.description)").font(KaiFont.caption).foregroundStyle(KaiColor.textSecondary)
                    Toggle("Check for updates automatically", isOn: $updates.automatic)
                    Text("Once a day Kai OS asks GitHub (api.github.com) which release is newest. Nothing else is sent. It never downloads or installs anything: it only tells you.")
                        .font(KaiFont.caption2Strong).foregroundStyle(KaiColor.textTertiary)
                    HStack {
                        Button(updates.isChecking ? "Checking…" : "Check now") { Task { await updates.check(manual: true) } }
                            .controlSize(.small).disabled(updates.isChecking)
                        if let update = updates.available {
                            Button("Open Kai OS \(update.version.description)") { updates.openReleasePage() }.controlSize(.small)
                            Button("Copy install command") { updates.copyInstallCommand() }.controlSize(.small)
                        }
                    }
                    if !updates.status.isEmpty {
                        Text(updates.status).font(KaiFont.caption).foregroundStyle(KaiColor.textSecondary)
                    }
                }

                }

                if page == .knowledge {
                // ── Mailbox access ──
                settingsCard {
                    SectionHeader(title: "Mailbox access")

                    Picker("Mailbox access", selection: $appState.mailAccess) {
                        ForEach(KaiMailAccess.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()

                    Text(appState.mailAccess.explanation)
                        .font(KaiFont.caption).foregroundStyle(KaiColor.textSecondary)

                    if appState.mailAccess.allowsChanges {
                        Text("Check each card before you approve it. A move is reversible by moving the messages back, but Kai won't do that for you without another approval.")
                            .font(KaiFont.caption2Strong).foregroundStyle(KaiColor.warning)
                    }
                    if !appState.mailConnected {
                        Text("Mail isn't connected yet. Connect it below to use any of this.")
                            .font(KaiFont.caption2Strong).foregroundStyle(KaiColor.textTertiary)
                    }
                }

                }

                if page == .system {
                // ── About ──
                settingsCard {
                    VStack(spacing: 12) {
                        Image(systemName: "cpu.chip")
                            .font(KaiFont.title2)
                            .foregroundStyle(KaiColor.primary)
                            .kaiGlow()
                        
                        Text("Kai OS").font(KaiFont.title2)
                            .fontWeight(.bold)
                        Text("1.0.0").font(KaiFont.caption)
                            .foregroundStyle(KaiColor.textTertiary)
                        
                        Divider().kaiDivider()
                        
                        Text("Personal AI for macOS").font(KaiFont.caption)
                            .foregroundStyle(KaiColor.textSecondary)
                        
                        Text("© 2026 Kai OS Labs").font(KaiFont.caption2Strong)
                            .foregroundStyle(KaiColor.textTertiary)
                    }
                }
                
                }

                if page == .system {
                // ── Privacy ──
                settingsCard {
                    VStack(spacing: 8) {
                        Text("Privacy").font(KaiFont.bodyStrong)
                            .foregroundStyle(KaiColor.textPrimary)
                        
                        Text("Chat stays on this Mac when using a local Ollama model. Cloud AI (OpenAI/Anthropic) sends data to their services — configure API keys above. Approved actions are logged in ~/Library/Application Support/Kai OS/action-log.jsonl.")
                            .font(KaiFont.caption)
                            .foregroundStyle(KaiColor.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                
                }

                Text("Private by default. Local first.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
            }
            .frame(maxWidth: 780)
            .padding(.horizontal, 40).padding(.vertical, 36)
            .frame(maxWidth: .infinity)
        }
    }
    
    // ── Card Wrapper ──
    private func settingsCard<Content: View>(
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.04))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.1), lineWidth: 1))
        )
    }

    // ── Knowledge source cards ──
    private var sourceGrid: some View {
        VStack(alignment: .leading, spacing: 28) {
            sourceSection("Email & calendars") {
                KaiSourceCard(symbol: "envelope.fill", tint: .red, title: "Gmail", state: .locked)
                KaiSourceCard(symbol: "calendar", tint: .blue, title: "Google Calendar", state: .locked)
                KaiSourceCard(symbol: "envelope.fill", tint: .cyan, title: "Outlook Mail", state: .locked)
                KaiSourceCard(symbol: "calendar", tint: .cyan, title: "Outlook Calendar", state: .locked)
                KaiSourceCard(symbol: "envelope.fill", tint: .blue, title: "Apple Mail",
                              subtitle: appState.mailConnected ? "Connected · tap to disconnect" : "Tap to connect",
                              state: appState.mailConnected ? .connected : .available) {
                    if appState.mailConnected { appState.disconnectMail() } else { appState.connectMail() }
                }
                KaiSourceCard(symbol: "calendar", tint: .red, title: "Apple Calendar",
                              subtitle: appState.calendarConnected ? "Connected · on this Mac" : "Tap to connect",
                              state: appState.calendarConnected ? .connected : .available) {
                    appState.connectCalendar()
                }
            }
            sourceSection("Messages") {
                KaiSourceCard(symbol: "message.fill", tint: .green, title: "iMessage", state: .locked)
                KaiSourceCard(symbol: "number", tint: .purple, title: "Slack",
                              subtitle: appState.slackClient != nil ? "Connected · read only" : "Add your token below",
                              state: appState.slackClient != nil ? .connected : .available)
            }
            sourceSection("Apps & notes") {
                KaiSourceCard(symbol: "externaldrive.fill", tint: .blue, title: "Google Drive", state: .locked)
                KaiSourceCard(symbol: "n.square.fill", tint: .gray, title: "Notion", state: .locked)
                KaiSourceCard(symbol: "note.text", tint: .yellow, title: "Apple Notes",
                              subtitle: appState.notesConnected ? "Connected · tap to disconnect" : "Tap to connect",
                              state: appState.notesConnected ? .connected : .available) {
                    if appState.notesConnected { appState.disconnectNotes() } else { appState.connectNotes() }
                }
            }
            Text("Apple Mail, Calendar and Notes are read on this Mac. Anything you connect is only used to answer you and prepare your cards. Locked sources are planned, not built yet.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func sourceSection<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title3).fontWeight(.semibold)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                content()
            }
        }
    }

    // ── Connection Row ──
    /// Whether a source can be read right now, and why not if it can't.
    private func nightShiftSourceNote(_ source: KaiNightShiftSource) -> String? {
        switch source {
        case .calendar: return appState.calendarConnected ? nil : "Not connected. Connect Calendar first."
        case .notes: return appState.notesConnected ? nil : "Not connected. Connect Notes first."
        case .mail: return appState.mailConnected ? nil : "Not connected. Connect Mail first."
        case .slack: return appState.slackClient != nil ? nil : "Not connected. Add your Slack token first."
        case .files, .briefing: return nil
        }
    }

    private func nightShiftSourceRow(_ source: KaiNightShiftSource) -> some View {
        let note = nightShiftSourceNote(source)
        return VStack(alignment: .leading, spacing: 2) {
            Toggle(source.title, isOn: Binding(
                get: { appState.nightShift.includes(source) },
                set: { isOn in
                    var next = appState.nightShift
                    if isOn { next.sources.insert(source) } else { next.sources.remove(source) }
                    appState.updateNightShift(next)
                }
            ))
            .disabled(note != nil && !appState.nightShift.includes(source))
            Text(note ?? source.detail)
                .font(KaiFont.caption2Strong)
                .foregroundStyle(note == nil ? (source == .mail ? KaiColor.warning : KaiColor.textTertiary) : KaiColor.textTertiary)
                .padding(.leading, 20)
            if source == .mail {
                let mailOn = appState.nightShift.includes(.mail)
                Text("How far back to read mail").font(KaiFont.captionStrong).foregroundStyle(KaiColor.textTertiary).padding(.leading, 20)
                Picker("Mail from", selection: Binding(
                    get: { appState.nightShift.mailWindow },
                    set: { var next = appState.nightShift; next.mailWindow = $0; appState.updateNightShift(next) }
                )) {
                    ForEach(KaiMailWindow.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(!mailOn)
                .padding(.leading, 20)
                Text(mailOn ? appState.nightShift.mailWindow.detail : "Switch Mail on above to use this. Your choice is kept either way.")
                    .font(KaiFont.caption2Strong).foregroundStyle(KaiColor.textTertiary).padding(.leading, 20)
            }
        }
    }

    private func connectionRow(
        title: String,
        connected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: connected ? "checkmark.circle.fill" : "questionmark.circle")
                .foregroundStyle(connected ? KaiColor.success : KaiColor.textTertiary)
                .font(KaiFont.captionStrong)
            
            Text(title).font(KaiFont.bodyStrong)
            
            Spacer()
            
            if connected {
                Button("Disconnect") { action() }
                    .buttonBorderShape(.roundedRectangle)
                    .controlSize(.small)
            } else {
                Button("Connect") { action() }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.roundedRectangle)
                    .controlSize(.small)
            }
        }
        .padding(8)
        .background(KaiColor.surfaceBg, in: RoundedRectangle(cornerRadius: 8))
    }
}

// ── Section Header ──
private struct SectionHeader: View {
    let title: String
    
    var body: some View {
        Text(title).font(KaiFont.captionStrong)
            .foregroundStyle(KaiColor.textTertiary)
            .textCase(.uppercase)
            .padding(.bottom, 4)
    }
}


/// One data source: a rounded card with a colored icon, a name, and a state on the right.
private struct KaiSourceCard: View {
    enum State { case available, connected, locked }

    let symbol: String
    let tint: Color
    let title: String
    var subtitle: String?
    let state: State
    var action: (() -> Void)?

    var body: some View {
        Button { action?() } label: {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 17))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 10).fill(tint.gradient))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).fontWeight(.medium)
                    Text(subtitle ?? (state == .locked ? "Coming soon" : ""))
                        .font(.caption).foregroundStyle(.secondary)
                        .opacity(subtitle == nil && state != .locked ? 0 : 1)
                }
                Spacer()
                switch state {
                case .available: Image(systemName: "plus").foregroundStyle(.secondary)
                case .connected: Image(systemName: "checkmark").foregroundStyle(Color.green)
                case .locked: Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(state == .connected ? Color.green.opacity(0.08) : Color.white.opacity(0.04))
                    .overlay(RoundedRectangle(cornerRadius: 22)
                        .stroke(state == .connected ? Color.green.opacity(0.55) : Color.white.opacity(0.12), lineWidth: 1))
            )
            .opacity(state == .locked ? 0.6 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(state == .locked || action == nil)
    }
}
