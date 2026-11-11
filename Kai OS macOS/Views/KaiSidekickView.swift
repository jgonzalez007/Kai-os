//
//  KaiSidekickView.swift
//  Kai OS macOS
//
//  Give Kai a task and it operates your Mac for you, one approved step at a time.
//  Copyright © 2026 Kai OS Labs. All rights reserved.
//

import SwiftUI
import KaiAgent

struct KaiSidekickView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var agent: KaiAgentController

    private enum Tab: String, CaseIterable { case task = "Task", settings = "Settings" }
    @State private var tab = Tab.task

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Sidekick").font(.system(size: 26, weight: .semibold))
                Spacer()
                Picker("", selection: $tab) { ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 180)
            }
            .padding(.horizontal, 28).padding(.top, 6).padding(.bottom, 10)

            if tab == .settings {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Make everyday help feel like your own.").foregroundStyle(.secondary)
                        KaiSidekickSettingsView()
                    }
                    .frame(maxWidth: 780).padding(.horizontal, 28).padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                }
            } else {
                taskPage
            }
        }
    }

    private var taskPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Sidekick does a task in your other apps. Describe it and Kai will do it in your other apps by looking at the screen and using the mouse and keyboard, with a ring where it clicks. It uses a local model, so what's on your screen never leaves this Mac.")
                    .font(KaiFont.caption).foregroundStyle(.secondary)

                TextEditor(text: $agent.task)
                    .font(.body)
                    .frame(minHeight: 70, maxHeight: 110)
                    .padding(6)
                    .background(KaiColor.surfaceBg, in: RoundedRectangle(cornerRadius: 8))
                    .disabled(agent.isRunning)
                    .overlay(alignment: .topLeading) {
                        if agent.task.isEmpty {
                            Text("For example: open Notes and create a note called Shopping with milk and eggs")
                                .foregroundStyle(.tertiary).padding(12).allowsHitTesting(false)
                        }
                    }

                Picker("Control", selection: $agent.mode) {
                    Text("Ask me before every action").tag(KaiAgentMode.askEach)
                    Text("Run on its own").tag(KaiAgentMode.auto)
                }
                .pickerStyle(.radioGroup)
                .disabled(agent.isRunning)

                Text(agent.mode == .askEach
                     ? "Every click, keystroke and shortcut waits for your Approve."
                     : "Clicks, typing and scrolling run by themselves. It also makes notes, events and mail drafts on its own. Kai still asks before quitting or closing, before ⌘Return, and before Return or a new line in a chat app such as Slack or Messages, where that sends. Use this only for tasks where a wrong click is harmless.")
                    .font(KaiFont.caption).foregroundStyle(.secondary)

                HStack {
                    if agent.isRunning {
                        Button("Stop") { agent.stop() }.tint(.red)
                    } else {
                        Button("Start") { agent.start(appState: appState) }
                            .kaiProminent()
                            .disabled(agent.task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    if agent.isRunning { ProgressView().controlSize(.small) }
                }

                if let message = agent.message {
                    Text(message).font(KaiFont.caption).foregroundStyle(.orange)
                }

                GroupBox("Safety") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("• Esc, the Stop button, or using your own mouse or keyboard stops it at once.")
                        Text("• It never works in Terminal, System Settings, password managers or Keychain Access, and never while Kai's own window is in front.")
                        Text("• It stops after \(KaiAgentEffort.stored().limits.maxSteps) steps or \(Int(KaiAgentEffort.stored().limits.maxDuration / 60)) minutes. Change this on the Settings tab, under Speed & intelligence.")
                        Text("• It can open an app by name, but never Terminal, System Settings or the other blocked apps. It reads the names and positions of buttons and fields in the front window (never what is typed in them) to click in the right place.")
                        Text("• Where a job has a direct route it skips the screen: it can make a note, add a calendar event, open a mail draft or a link, read your calendar, recent mail, Slack, notes and files, and read what you last copied. Those reads only happen with a local model: with Claude they are refused. In Ask each time, anything that makes something waits for your Approve. It never sends mail.")
                        Text("• When it is stuck on something only you can decide, it asks one question with two answers, up to three times. It never asks for passwords. When it says it is done it has to say what on the screen shows it, and it can say it could not finish.")
                        Text("• Everything it proposes or does is logged in ~/Library/Application Support/Kai OS/agent-log.jsonl. Screenshots are not saved.")
                        Text("• Text on screen is treated as untrusted. Kai won't act on instructions it reads there.")
                    }
                    .font(KaiFont.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                }

                if !agent.lines.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("What happened").font(KaiFont.bodyStrong)
                        ForEach(agent.lines) { line in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: icon(line.kind)).foregroundStyle(color(line.kind)).frame(width: 16)
                                Text(line.text).font(KaiFont.caption)
                                    .foregroundStyle(line.kind == .thought ? .secondary : .primary)
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    private func icon(_ kind: KaiAgentController.LineKind) -> String {
        switch kind {
        case .thought: return "bubble.left"
        case .proposed: return "questionmark.circle"
        case .performed: return "checkmark.circle.fill"
        case .problem: return "exclamationmark.triangle.fill"
        case .outcome: return "flag.checkered"
        }
    }

    private func color(_ kind: KaiAgentController.LineKind) -> Color {
        switch kind {
        case .performed: return .green
        case .problem: return .orange
        case .outcome: return .purple
        default: return .secondary
        }
    }
}
